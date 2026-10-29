"""Read-only final GPU inventory, supplementing the installed shared launcher."""
import importlib.util
import os
from pathlib import Path
import re
import subprocess


def engine_arguments(command):
    # Godot's standalone separator ends engine flags. A game argument named
    # --headless cannot turn a rendering process into dummy-renderer QA.
    return command[:command.index('--')] if '--' in command else command


def is_engine_command(command):
    if not command:
        return False
    executable = Path(command[0])
    name = executable.name.lower()
    if 'mcp' in name:
        return False
    resources = executable.parent.parent/'Resources'
    return (name.startswith('godot') or name in {'blender', 'unity', 'unrealeditor', 'orchard reach'}
            or re.search(r'-mac-(shipping|development|test|debug|debuggame)$', name) is not None
            or '--main-pack' in engine_arguments(command) or executable.with_suffix('.pck').exists()
            or ('.app/Contents/MacOS/' in str(executable)
                and (bool(list(resources.glob('*.pck'))) or (resources/'Data').is_dir()
                     or (executable.parent.parent/'UE').is_dir())))


def is_rendering_command(command):
    if not is_engine_command(command):
        return False
    flags = engine_arguments(command)
    name = Path(command[0]).name.lower()
    if (name.startswith('godot') or name == 'orchard reach' or '--main-pack' in flags
            or bool(list((Path(command[0]).parent.parent/'Resources').glob('*.pck')))):
        return '--headless' not in flags
    if 'unreal' in name or re.search(r'-mac-(shipping|development|test|debug|debuggame)$', name):
        return '-nullrhi' not in [arg.lower() for arg in flags]
    if name == 'unity' or (Path(command[0]).parent.parent/'Resources/Data').is_dir():
        return '-nographics' not in [arg.lower() for arg in flags]
    return True  # Blender background can initialize Metal; it is not dummy-renderer QA.


def replace_proven_uv_wrappers(clients, table, native_metal, retained_gpu_pids=None):
    result = []
    retained_gpu_pids = set(retained_gpu_pids or ())
    for row in clients:
        if row.get('kind') != 'ml' or Path(row.get('comm', '')).name.lower() not in {'uv', 'uvx'} or row['pid'] in native_metal:
            result.append(row)
            continue
        # Only a known launcher WITHOUT a Metal client can be replaced by its
        # actual GPU child. Distinct native Metal parent/child PIDs both count.
        has_native_child = False
        for pid in native_metal & retained_gpu_pids:
            ancestor = table.get(pid, {}).get('ppid'); seen = set()
            while ancestor and ancestor in table and ancestor not in seen:
                if ancestor == row['pid']:
                    has_native_child = True
                    break
                seen.add(ancestor); ancestor = table[ancestor].get('ppid')
            if has_native_child:
                break
        if not has_native_child:
            result.append(row)
    return result


def metal_client_ids(text):
    return {int(pid) for pid in re.findall(r'"IOUserClientCreator"\s*=\s*"pid\s+(\d+),', text)}


def extra_clients(table, native_metal, already, fold=True):
    """Conservative positive evidence, without logging command lines/secrets."""
    result = []
    for pid, row in table.items():
        if pid in already:
            continue
        executable = row.get('comm', '')
        base = Path(executable).name.lower()
        command = row.get('cmd', '').lower()
        known_ml_ancestor = False
        ancestor = row.get('ppid'); seen = set()
        while ancestor and ancestor in table and ancestor not in seen:
            if already.get(ancestor) in {'ml', 'metal-compute'}:
                known_ml_ancestor = True
                break
            seen.add(ancestor); ancestor = table[ancestor].get('ppid')
        kind = None
        if base == 'springboard' and ('simulator' in command or 'simruntime' in command):
            kind = 'ios-simulator'
        elif base.startswith('vtencoderxpc'):
            kind = 'video-encoder'
        elif base in {'ffmpeg', 'avconvert'} and (base == 'avconvert' or 'videotoolbox' in command):
            kind = 'hardware-video'
        elif pid in native_metal and is_engine_command([executable]):
            kind = 'native-engine'
        elif pid in native_metal and (re.fullmatch(r'python[0-9.]*|uv|uvx', base)
                                     or base.startswith(('llama', 'ollama', 'mlx', 'lms'))
                                     or known_ml_ancestor):
            kind = 'metal-compute'
        if kind:
            result.append({'pid': pid, 'ppid': row.get('ppid'), 'kind': kind,
                           'stat': row.get('stat', ''), 'comm': executable})
    # Every distinct native GPU client counts, even if it is a child of
    # another trainer. Job ancestry is not a valid GPU-capacity exemption.
    return result


def native_stuck_clients(table, native_metal):
    # A positive native GPU connection plus an exiting/zombie state is enough
    # for the wedge guard, even when the executable is not a known workload.
    result=[]
    for pid in native_metal:
        row=table.get(pid)
        if row and row.get('stat','')[:1] in {'E','Z'}:
            result.append({'pid':pid,'ppid':row.get('ppid'),'kind':'native-metal',
                           'stat':row.get('stat'),'comm':row.get('comm','')})
    return result


def snapshot(shared_root):
    library = Path(shared_root)/'bin/gpu_slot.py'
    spec = importlib.util.spec_from_file_location('singapore_shared_gpu_slot', library)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    cfg = module.Cfg()
    # A task does not acquire authority for disabled/mock safety gates merely
    # because a leftover shell environment contains a test setting.
    if (cfg.capture_util_max <= 0 or cfg.capture_util_max > 85 or cfg.capture_calm < 10
            or cfg.cooldown < 20 or cfg.slots > 2 or cfg.mock_util is not None
            or cfg.mock_util_file or cfg.mock_stuck_file or cfg.unreal_pat
            or cfg.gpu_ignore_pat is not None):
        raise RuntimeError('Shared GPU safety configuration is weakened or mocked; launch refused')
    table = module.proc_table(cfg)
    if not table:
        raise RuntimeError('Cannot observe current process inventory')
    clients = module.foreign_gpu_clients(cfg, table)
    probe = subprocess.run(['ioreg','-l','-w','0','-r','-c','IOGPUDeviceUserClient'],
                           capture_output=True, text=True, timeout=10, check=True)
    if not probe.stdout.strip():
        raise RuntimeError('Cannot observe native Metal client inventory')
    metal = metal_client_ids(probe.stdout)
    known = {row['pid']: row['kind'] for row in clients}
    all_extra = extra_clients(table, metal, known, fold=False)
    clients = replace_proven_uv_wrappers(clients, table, metal, set(known) | {row['pid'] for row in all_extra})
    clients += all_extra
    stuck = module.stuck_clients(cfg, table)
    stuck_ids = {row['pid'] for row in stuck}
    stuck += [row for row in native_stuck_clients(table,metal) if row['pid'] not in stuck_ids]
    return {'paused': module.read_paused(cfg) is not None,
            'streaming': (Path(shared_root)/'STREAMING').exists(),
            'utilization': module.read_util(cfg), 'clients': clients, 'stuck': stuck}


def safe_public_rows(rows):
    return [{key: row.get(key) for key in ('pid','kind','stat','comm')} for row in rows]
