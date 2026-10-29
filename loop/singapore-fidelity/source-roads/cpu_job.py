"""Owned bounded CPU-only worker lifecycle; no engine or foreign process API."""
import datetime
import fcntl
import json
import os
from pathlib import Path
import resource
import shutil
import signal
import subprocess
import sys
import time
import uuid

MAX_RSS = 2 * 1024**3


def output_bytes(root):
    total = 0
    for path in root.rglob('*'):
        try:
            if path.is_file() and not path.is_symlink():
                total += path.stat().st_size
        except FileNotFoundError:
            pass  # An owned atomic state-file rename raced this sample.
    return total


def stamp():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def write_state(path, data):
    path = Path(path)
    if path.is_symlink() or any(parent.is_symlink() for parent in path.parents):
        raise ValueError('Owned CPU state cannot traverse symlinks')
    temporary = path.with_name(path.name + '.writing')
    with temporary.open('x') as stream:
        json.dump(data, stream, sort_keys=True, indent=2)
        stream.write('\n')
    os.replace(temporary, path)


def worker_guard(args):
    path = args.output / 'lifecycle.json'
    if path.is_symlink():
        raise ValueError('CPU lifecycle symlink refused')
    state = json.loads(path.read_text())
    if not args.job_token or state['job_token'] != args.job_token or state['supervisor_pid'] != os.getppid():
        raise ValueError('Worker is not the bounded owned supervisor child')
    resource.setrlimit(resource.RLIMIT_CPU, (3600, 3630))


def supervise(args, script, kind, protected=()):
    output = args.output
    if output.exists() or output.is_symlink() or any(parent.is_symlink() for parent in output.parents):
        raise ValueError('Fresh non-symlink owned CPU directory required')
    resolved = output.resolve()
    for path in protected:
        protected_root = Path(path).resolve()
        if resolved == protected_root or protected_root in resolved.parents:
            raise ValueError('Output aliases an immutable source artifact')
    output.mkdir(parents=True)
    lock = (output / 'worker.lock').open('xb')
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    token = uuid.uuid4().hex
    state = {'kind': kind, 'status': 'STARTING', 'created_utc': stamp(),
             'supervisor_pid': os.getpid(), 'worker_pid': None, 'job_token': token,
             'script': str(Path(script).resolve()),
             'limits': {'rss_bytes': MAX_RSS, 'cpu_seconds': 3600, 'wall_seconds': 7200}}
    disk_budget = getattr(args, 'output_budget_bytes', None)
    minimum_free = getattr(args, 'minimum_free_bytes', None)
    if disk_budget is not None:
        if disk_budget <= 0 or minimum_free is None or minimum_free <= 0:
            raise ValueError('Positive explicit disk budget/free-space reserve required')
        state['limits'].update(output_logical_bytes=disk_budget, minimum_filesystem_free_bytes=minimum_free)
        if shutil.disk_usage(output).free < minimum_free:
            raise ValueError('Direct filesystem free space below task reserve before launch')
    write_state(output / 'lifecycle.json', state)
    started, peak, reason = time.monotonic(), 0, None
    stopped = []
    prior_signals = {sig: signal.signal(sig, lambda number, _frame: stopped.append(number)) for sig in (signal.SIGTERM, signal.SIGINT)}
    checked_disk_at, maximum_disk = started - 10, 0
    with (output / 'worker.log').open('xb') as log:
        process = subprocess.Popen([sys.executable, str(Path(script).resolve()), *sys.argv[1:],
                                    '--worker', '--job-token', token], stdout=log, stderr=subprocess.STDOUT)
        state.update(status='RUNNING', worker_pid=process.pid,
                     worker_lstart=subprocess.run(['/bin/ps', '-o', 'lstart=', '-p', str(process.pid)], capture_output=True, text=True).stdout.strip())
        write_state(output / 'lifecycle.json', state)
        try:
            while process.poll() is None:
                if stopped:
                    reason = 'Owned supervisor received signal ' + str(stopped[0])
                    break
                text = subprocess.run(['/bin/ps', '-o', 'rss=', '-p', str(process.pid)], capture_output=True, text=True).stdout.strip()
                if text:
                    peak = max(peak, int(text) * 1024)
                if peak > MAX_RSS:
                    reason = 'Owned CPU worker exceeded 2GiB RSS'
                    break
                if time.monotonic() - started > 7200:
                    reason = 'Owned CPU worker exceeded 7200s wall'
                    break
                if disk_budget is not None and time.monotonic() - checked_disk_at >= 10:
                    sizes = output_bytes(output)
                    maximum_disk = max(maximum_disk, sizes)
                    checked_disk_at = time.monotonic()
                    if sizes > disk_budget or shutil.disk_usage(output).free < minimum_free:
                        reason = 'Owned CPU output exceeded disk budget or direct free-space reserve'
                        break
                time.sleep(1)
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=30)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
            for sig, handler in prior_signals.items():
                signal.signal(sig, handler)
    if disk_budget is not None:
        maximum_disk = max(maximum_disk, output_bytes(output))
        if reason is None and (maximum_disk > disk_budget or shutil.disk_usage(output).free < minimum_free):
            reason = 'Owned CPU output exceeded disk budget or direct free-space reserve at completion'
    state.update(status='COMPLETE' if process.returncode == 0 and reason is None else 'INCOMPLETE',
                 terminal_utc=stamp(), worker_exit=process.returncode, reason=reason,
                 sampled_peak_rss_bytes=peak, wall_seconds=time.monotonic() - started)
    if disk_budget is not None:
        state['sampled_peak_output_logical_bytes'] = maximum_disk
    write_state(output / 'lifecycle.json', state)
    with (output / 'supervisor.json').open('x') as stream:
        json.dump(state, stream, sort_keys=True, indent=2)
        stream.write('\n')
    lock.close()
    return state
