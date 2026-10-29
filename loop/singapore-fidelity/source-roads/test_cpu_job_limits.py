import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest

HERE = Path(__file__).resolve().parent
SCRIPT = '''import argparse,sys,time
from pathlib import Path
sys.path.insert(0, %r)
import cpu_job
p=argparse.ArgumentParser();p.add_argument('--output',type=Path);p.add_argument('--mode');p.add_argument('--worker',action='store_true');p.add_argument('--job-token')
a=p.parse_args();a.output_budget_bytes=2048 if a.mode=='disk' else 1024**2;a.minimum_free_bytes=1
if a.worker:
 cpu_job.worker_guard(a)
 (a.output/'ready').write_bytes(b'x'*8192 if a.mode=='disk' else b'ready')
 if a.mode=='signal':time.sleep(30)
else:
 print(cpu_job.supervise(a,__file__,'test-only-bounded-cpu'))
'''


class BoundedCpuLifecycle(unittest.TestCase):
    def test_fast_finished_output_still_checks_disk_limit(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp).resolve();script=root/'job.py';script.write_text(SCRIPT % str(HERE));output=root/'result'
            result=subprocess.run([sys.executable,str(script),'--output',str(output),'--mode','disk'],capture_output=True,text=True,timeout=8)
            self.assertEqual(result.returncode,0)
            receipt=json.loads((output/'supervisor.json').read_text())
            self.assertEqual(receipt['status'],'INCOMPLETE')
            self.assertIn('disk budget',receipt['reason'])
            self.assertGreater(receipt['sampled_peak_output_logical_bytes'],2048)

    def test_owned_supervisor_sigterm_reaps_child_and_records_reason(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp).resolve();script=root/'job.py';script.write_text(SCRIPT % str(HERE));output=root/'result'
            process=subprocess.Popen([sys.executable,str(script),'--output',str(output),'--mode','signal'],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
            until=time.monotonic()+5
            while not (output/'ready').exists() and time.monotonic()<until:
                time.sleep(.02)
            self.assertTrue((output/'ready').exists())
            worker=json.loads((output/'lifecycle.json').read_text())['worker_pid']
            process.send_signal(signal.SIGTERM)
            process.communicate(timeout=8)
            receipt=json.loads((output/'supervisor.json').read_text())
            self.assertEqual(receipt['status'],'INCOMPLETE')
            self.assertIn('signal',receipt['reason'])
            self.assertIsNotNone(receipt['worker_exit'])
            with self.assertRaises(ProcessLookupError):os.kill(worker,0)


if __name__=='__main__':unittest.main()
