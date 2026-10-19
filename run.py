"""Run the app and keep its permanent LAN link current in Snippets."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

from server import physical_networks, PORT

ROOT = Path(__file__).resolve().parent
SKILL = Path('/Users/anna/.agents/skills/record-deployment-links/scripts')
PROJECT = 'TV Glow'
stopping = False


def stop(signum, frame):
    global stopping
    stopping = True


def save(url=None, status='auto'):
    args = [sys.executable, str(SKILL / 'save_project_link.py'), '--project', PROJECT, '--status', status]
    if url:
        args += ['--url', url]
    result = subprocess.run(args, text=True, capture_output=True)
    if result.returncode:
        print('Snippets update failed: ' + result.stderr.strip(), flush=True)
        return False
    try:
        data = json.loads(result.stdout)
        snippet = data['snippet']
        valid = snippet['isEnabled'] and snippet['isPinned'] and (not url or snippet['content'] == url)
        if not valid:
            print('Snippets entry needs attention: ' + result.stdout, flush=True)
            return False
        print(f"{snippet['name']}: {snippet['content']} (app-tv-glow)", flush=True)
        return True
    except (ValueError, KeyError):
        print('Could not verify Snippets response: ' + result.stdout, flush=True)
        return False


def main():
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    server = subprocess.Popen([sys.executable, str(ROOT / 'server.py')], cwd=ROOT)
    watcher = None
    url = None
    saved = False
    try:
        # Let the listener start before the first reachability check.
        time.sleep(1)
        while server.poll() is None and not stopping:
            networks = physical_networks()
            next_url = f'http://{networks[0][0]}:{PORT}' if networks else None
            if next_url and (url != next_url or not saved):
                if watcher:
                    watcher.terminate()
                    watcher.wait(timeout=5)
                    watcher = None
                url = next_url
                saved = save(url)
                if saved:
                    watcher = subprocess.Popen([
                        sys.executable, str(SKILL / 'watch_project_link.py'), '--project', PROJECT,
                        '--url', url, '--pid', str(server.pid),
                    ])
            if saved and watcher and watcher.poll() is not None:
                saved = False
            for _ in range(10):
                if stopping or server.poll() is not None:
                    break
                time.sleep(1)
    finally:
        if server.poll() is None:
            server.terminate()
            try:
                server.wait(timeout=8)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait()
        if watcher and watcher.poll() is None:
            watcher.terminate()
            try:
                watcher.wait(timeout=5)
            except subprocess.TimeoutExpired:
                watcher.kill()
                watcher.wait()
        if url:
            save(status='offline')
    return server.returncode or 0


if __name__ == '__main__':
    raise SystemExit(main())
