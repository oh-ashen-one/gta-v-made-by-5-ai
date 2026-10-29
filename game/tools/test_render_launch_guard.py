"""CPU-only tests of missing-client detection; never invoke an engine."""
import unittest
from render_launch_guard import extra_clients, is_engine_command, is_rendering_command, metal_client_ids, replace_proven_uv_wrappers, native_stuck_clients


def process(pid, executable, command='', ppid=1, state='S'):
    return dict(pid=pid, ppid=ppid, stat=state, comm=executable, cmd=command)


class FinalInventory(unittest.TestCase):
    def test_native_creator_pid_extraction(self):
        data='"IOUserClientCreator" = "pid 42, Python"\n"IOUserClientCreator" = "pid 43, WindowServer"'
        self.assertEqual(metal_client_ids(data), {42, 43})

    def test_unknown_python_only_counts_with_actual_metal_client(self):
        table={42:process(42,'/local/bin/python3','python worker.py'),43:process(43,'/local/bin/python3','python cpu.py')}
        self.assertEqual([p['pid'] for p in extra_clients(table,{42},{})],[42])

    def test_simulator_and_hardware_encoder_count(self):
        table={5:process(5,'/runtime/SpringBoard','/iOS.simruntime/SpringBoard'),6:process(6,'/sys/VTEncoderXPCService')}
        self.assertEqual({p['kind'] for p in extra_clients(table,set(),{})},{'ios-simulator','video-encoder'})

    def test_cpu_ffmpeg_and_desktop_compositor_are_not_extra_gpu_compute(self):
        table={7:process(7,'/bin/ffmpeg','ffmpeg -c:v libx264'),8:process(8,'/sys/WindowServer')}
        self.assertEqual(extra_clients(table,{8},{}),[])

    def test_distinct_encoder_child_of_training_job_is_not_hidden(self):
        table={10:process(10,'/bin/python3'),11:process(11,'/sys/VTEncoderXPCService',ppid=10),12:process(12,'/bin/python3',ppid=10)}
        self.assertEqual([p['pid'] for p in extra_clients(table,{10,12},{10:'ml'})],[11,12])

    def test_distinct_native_compute_child_is_counted_and_visible_if_stuck(self):
        table={10:process(10,'/bin/python3'),12:process(12,'/bin/python3',ppid=10,state='E')}
        self.assertEqual([p['pid'] for p in extra_clients(table,{10,12},{10:'ml'})],[12])
        self.assertEqual(extra_clients(table,{10,12},{10:'ml'},fold=False)[0]['stat'],'E')

    def test_only_proven_non_gpu_uv_launcher_is_removed(self):
        table={10:process(10,'/bin/uv'),12:process(12,'/bin/python3',ppid=10)}
        launcher=dict(table[10],kind='ml')
        self.assertEqual(replace_proven_uv_wrappers([launcher],table,{12},{12}),[])
        self.assertEqual(replace_proven_uv_wrappers([launcher],table,{10,12},{12}),[launcher])
        self.assertEqual(replace_proven_uv_wrappers([launcher],table,set()),[launcher])

    def test_unknown_native_children_of_ml_launcher_are_retained(self):
        table={10:process(10,'/bin/uv','uv run ./torch-bench'),
               12:process(12,'/custom/torch-bench',ppid=10),
               13:process(13,'/custom/another-metal-worker',ppid=10)}
        launcher=dict(table[10],kind='ml')
        self.assertEqual(replace_proven_uv_wrappers([launcher],table,{12,13},set()),[launcher])
        extras=extra_clients(table,{12,13},{10:'ml'})
        self.assertEqual({p['pid'] for p in extras},{12,13})
        self.assertEqual(replace_proven_uv_wrappers([launcher],table,{12,13},{p['pid'] for p in extras}),[])

    def test_unknown_native_metal_stuck_client_is_never_ignored(self):
        table={44:process(44,'/custom/unlisted-renderer',state='E'),
               45:process(45,'/sys/WindowServer',state='S'),
               46:process(46,'/bin/cpu-worker',state='Z')}
        self.assertEqual([p['pid'] for p in native_stuck_clients(table,{44,45})],[44])

    def test_renderer_shutdown_classification_is_independent_of_nonce(self):
        self.assertTrue(is_rendering_command(['/opt/homebrew/bin/godot','--path','game']))
        self.assertFalse(is_rendering_command(['/opt/homebrew/bin/godot','--headless']))
        self.assertTrue(is_rendering_command(['/game/Game-Mac-Shipping']))
        self.assertFalse(is_rendering_command(['/game/Game-Mac-Shipping','-nullrhi']))
        self.assertTrue(is_rendering_command(['/bin/blender','--background']))
        self.assertFalse(is_rendering_command(['/bin/python3','-c','print(1)']))

    def test_game_argument_does_not_disable_rendered_shutdown_safety(self):
        command=['/bin/godot','scene.tscn','--','--qa-session','/owned','--headless']
        self.assertTrue(is_rendering_command(command))
        self.assertFalse(is_rendering_command(['/bin/godot','--headless','scene.tscn','--','--capture']))

    def test_positive_native_engine_is_not_hidden_by_shared_flag_parse(self):
        table={44:process(44,'/bin/godot','godot scene.tscn -- --headless')}
        self.assertEqual(extra_clients(table,{44},{}),[{'pid':44,'ppid':1,'kind':'native-engine','stat':'S','comm':'/bin/godot'}])

    def test_engine_vs_cpu_command(self):
        self.assertTrue(is_engine_command(['/opt/homebrew/bin/godot','--headless']))
        self.assertTrue(is_engine_command(['/app/Orchard Reach']))
        self.assertFalse(is_engine_command(['/bin/python3','-c','print(1)']))


if __name__=='__main__':unittest.main()
