"""CPU-only startup evidence and shutdown tests. No engine/GPU is launched."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest

from render_startup_health import PREFIX, FirstFrameProbe, valid_frame, pause_shared, stop_owned


class StartupEvidence(unittest.TestCase):
    def row(self, **changes):
        row = dict(pid=123, nonce='fresh-owned-run', width=64, height=32,
                   frames_drawn=1, gpu_readback_completed=True, display_server='macOS')
        row.update(changes)
        return PREFIX + json.dumps(row)

    def test_valid_child_readback(self):
        self.assertIsNotNone(valid_frame(self.row(), 123, 'fresh-owned-run'))

    def test_wrong_child_or_stale_run(self):
        self.assertIsNone(valid_frame(self.row(pid=124), 123, 'fresh-owned-run'))
        self.assertIsNone(valid_frame(self.row(nonce='old-run'), 123, 'fresh-owned-run'))

    def test_banner_headless_empty_or_submission_is_not_readback(self):
        for changes in [dict(display_server='headless'), dict(width=0), dict(height=True),
                        dict(frames_drawn=0), dict(gpu_readback_completed=False)]:
            self.assertIsNone(valid_frame(self.row(**changes), 123, 'fresh-owned-run'))
        self.assertIsNone(valid_frame('Engine started frame1', 123, 'fresh-owned-run'))

    def test_incremental_split_marker(self):
        with tempfile.TemporaryDirectory() as folder:
            log = Path(folder)/'log'; log.write_text('Godot banner\n'+self.row(nonce='stale')+'\n')
            probe = FirstFrameProbe(log, 123, 'fresh-owned-run')
            self.assertIsNone(probe.poll())
            marker = self.row()
            with log.open('a') as out: out.write(marker[:35])
            self.assertIsNone(probe.poll())
            with log.open('a') as out: out.write(marker[35:]+'\n')
            self.assertEqual(probe.poll()['width'], 64)

    def test_pause_is_atomic_and_never_overwrites_existing_owner(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)/'isolated-slot'
            self.assertTrue(pause_shared(root,123,'synthetic CPU test')['created'])
            original = (root/'PAUSED').read_bytes()
            self.assertFalse(pause_shared(root,999,'different task')['created'])
            self.assertEqual((root/'PAUSED').read_bytes(), original)

    def test_stuck_render_child_is_not_killed(self):
        class Stuck:
            returncode = None
            calls = []
            def poll(self): return None
            def send_signal(self, value): self.calls.append(value)
            def wait(self, timeout): raise subprocess.TimeoutExpired('synthetic', timeout)
            def kill(self): raise AssertionError('SIGKILL must not be sent to a renderer wedge')
        child = Stuck(); pauses = []
        self.assertEqual(stop_owned(child, True, pauses.append, .01), (78, False))
        self.assertEqual(child.calls, [signal.SIGTERM])
        self.assertEqual(len(pauses), 1)

    def test_startup_health_still_polled_during_term_grace(self):
        class Stuck:
            returncode=None
            def poll(self): return None
            def send_signal(self, value): pass
            def wait(self, timeout):
                time.sleep(min(.002,timeout))
                raise subprocess.TimeoutExpired('synthetic',timeout)
            def kill(self): raise AssertionError('No renderer SIGKILL')
        start=time.monotonic(); observations=[]
        def health():
            if time.monotonic()-start>=.01:observations.append(time.monotonic()-start)
        result=stop_owned(Stuck(),True,lambda reason:None,.04,health)
        self.assertEqual(result,(78,False))
        self.assertTrue(observations)
        self.assertLess(observations[0],.03)

    def test_replayed_nonce_refused_before_child_or_pause(self):
        with tempfile.TemporaryDirectory() as folder:
            marker=Path(folder)/'child-started'
            log=Path(folder)/'run.log'
            env=dict(os.environ,GPU_SLOT_DIR=str(Path(folder)/'isolated-slot'))
            result=subprocess.run([sys.executable,str(Path(__file__).with_name('bounded_run.py')),
                '--seconds','2','--first-frame-seconds','1','--log',str(log),'--',
                sys.executable,'-c',f"from pathlib import Path; Path({str(marker)!r}).touch()",'--qa-render-health=old-run'],
                env=env,capture_output=True,text=True,timeout=10)
            self.assertEqual(result.returncode,2)
            self.assertFalse(marker.exists())
            self.assertFalse((Path(env['GPU_SLOT_DIR'])/'PAUSED').exists())

    def test_uninstrumented_legacy_render_command_refuses_before_launch(self):
        with tempfile.TemporaryDirectory() as folder:
            log=Path(folder)/'run.log'
            env=dict(os.environ,GPU_SLOT_DIR=str(Path(folder)/'isolated-slot'))
            result=subprocess.run([sys.executable,str(Path(__file__).with_name('bounded_run.py')),
                '--seconds','1','--log',str(log),'--','/nonexistent/Orchard Reach'],
                env=env,capture_output=True,text=True,timeout=10)
            self.assertEqual(result.returncode,2)
            self.assertIn('supported first-frame health protocol',result.stderr)
            self.assertFalse(log.exists())
            self.assertFalse((Path(env['GPU_SLOT_DIR'])/'PAUSED').exists())

    def test_real_cpu_child_terminates_and_reaps(self):
        child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)'])
        pauses = []
        code, reaped = stop_owned(child, True, pauses.append, 2)
        self.assertTrue(reaped)
        self.assertIsNotNone(code)
        self.assertEqual(pauses, [])

    def run_driver(self, script, frame_seconds):
        # The fake CPU child tests protocol/lifecycle only. It cannot provide
        # actual rendering evidence, and its isolated PAUSED path is never shared.
        with tempfile.TemporaryDirectory() as folder:
            log = Path(folder)/'run.log'
            env = dict(os.environ, GPU_SLOT_DIR=str(Path(folder)/'isolated-slot'))
            result = subprocess.run([sys.executable, str(Path(__file__).with_name('bounded_run.py')),
                                     '--seconds','5','--first-frame-seconds',str(frame_seconds),
                                     '--log',str(log),'--',sys.executable,'-c',script],
                                    env=env, capture_output=True, text=True, timeout=30)
            meta = json.loads(Path(str(log)+'.meta.json').read_text())
            return result.returncode, meta, (Path(env['GPU_SLOT_DIR'])/'PAUSED').exists()

    def test_supervisor_cpu_protocol_success(self):
        script = "import os,sys,json; n=next(x.split('=',1)[1] for x in sys.argv if x.startswith('--qa-render-health=')); print('SINGAPORE_RENDER_FIRST_FRAME '+json.dumps(dict(pid=os.getpid(),nonce=n,width=4,height=4,frames_drawn=1,display_server='SIMULATED_CPU_ONLY',gpu_readback_completed=True)),flush=True)"
        code, meta, paused = self.run_driver(script, 2)
        self.assertEqual(code, 0)
        self.assertTrue(meta['render_startup']['confirmed'])
        self.assertTrue(meta['child_reaped'])
        self.assertFalse(paused)

    def test_supervisor_missing_frame_pauses_before_owned_stop(self):
        code, meta, paused = self.run_driver('import time; time.sleep(20)', .1)
        self.assertEqual(code, 78)
        self.assertTrue(paused)
        self.assertTrue(meta['child_reaped'])
        self.assertFalse(meta['render_startup']['confirmed'])
        self.assertIn('first frame', meta['wedge_reason'])


if __name__ == '__main__': unittest.main()
