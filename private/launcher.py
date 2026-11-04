#!/usr/bin/env python3
"""alertmanager_server launcher.

  launcher.py --alertmanager BIN --amtool BIN --config-dir DIR
              --env-file PATH --state-dir DIR --ready-timeout SECONDS
              [-- EXTRA_ALERTMANAGER_FLAGS...]

1. Copies the staged config directory (alertmanager.yml + templates) into
   the state dir and expands ${NAME} placeholders from the environment;
   an unset one is an error naming it.
2. Picks a free port and starts alertmanager on 127.0.0.1 with clustering
   (gossip) disabled and storage in the state dir. Retries on a port
   clash, up to 5 times.
3. Polls GET /-/ready until it answers 200 or --ready-timeout passes.
4. Writes the env file atomically (tmp + rename):
     ALERTMANAGER_URL=http://127.0.0.1:<port>
     ALERTMANAGER_HOST=127.0.0.1
     ALERTMANAGER_PORT=<port>
     AMTOOL=<absolute path to amtool>
5. Waits. SIGTERM / SIGINT (rules_itest teardown) stops alertmanager,
   removes the env file and exits 0; if alertmanager dies, exits with its
   status.
"""

import argparse
import os
import re
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request

_PLACEHOLDER = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}")


def _log(msg):
    print(f"[alertmanager_server] {msg}", file=sys.stderr, flush=True)


def expand_placeholders(text, env):
    """Replace each ${NAME} with env[NAME]. Raises KeyError listing every
    unset name."""
    missing = sorted({m.group(1) for m in _PLACEHOLDER.finditer(text)
                      if m.group(1) not in env})
    if missing:
        raise KeyError(", ".join(missing))
    return _PLACEHOLDER.sub(lambda m: env[m.group(1)], text)


def stage_config(config_dir, state_dir, env):
    """Copy config_dir into state_dir/config with placeholders expanded.
    Returns the path of the expanded alertmanager.yml."""
    dest = os.path.join(state_dir, "config")
    if os.path.isdir(dest):
        shutil.rmtree(dest)
    os.makedirs(dest)
    for name in os.listdir(config_dir):
        shutil.copyfile(os.path.join(config_dir, name), os.path.join(dest, name))
    path = os.path.join(dest, "alertmanager.yml")
    with open(path) as f:
        text = f.read()
    with open(path, "w") as f:
        f.write(expand_placeholders(text, env))
    return path


def _free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


def _ready(url):
    try:
        with urllib.request.urlopen(url + "/-/ready", timeout=2) as r:
            return r.status == 200
    except (urllib.error.URLError, OSError):
        return False


def _write_env(env_file, url, port, amtool):
    tmp = env_file + ".tmp"
    with open(tmp, "w") as f:
        f.write(f"ALERTMANAGER_URL={url}\n")
        f.write("ALERTMANAGER_HOST=127.0.0.1\n")
        f.write(f"ALERTMANAGER_PORT={port}\n")
        f.write(f"AMTOOL={amtool}\n")
    os.replace(tmp, env_file)


def _start(args, config, log_path):
    """Start alertmanager and wait for /-/ready. Returns (proc, url)."""
    for attempt in range(1, 6):
        port = _free_port()
        url = f"http://127.0.0.1:{port}"
        cmd = [
            args.alertmanager,
            f"--config.file={config}",
            f"--storage.path={os.path.join(args.state_dir, 'data')}",
            f"--web.listen-address=127.0.0.1:{port}",
            "--cluster.listen-address=",  # no gossip: one isolated instance
        ] + args.extra
        log = open(log_path, "w")
        proc = subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT)
        deadline = time.monotonic() + args.ready_timeout
        while time.monotonic() < deadline:
            if proc.poll() is not None:
                break
            if _ready(url):
                return proc, url
            time.sleep(0.2)
        if proc.poll() is None:
            proc.kill()
            proc.wait()
            _log(f"not ready within {args.ready_timeout}s at {url}. Log:")
            _log(open(log_path).read())
            sys.exit(1)
        out = open(log_path).read()
        if "address already in use" in out and attempt < 5:
            _log(f"port {port} taken (attempt {attempt}); retrying")
            continue
        _log(f"alertmanager exited with status {proc.returncode}. Log:")
        _log(out)
        sys.exit(1)
    sys.exit(1)


def main(argv):
    p = argparse.ArgumentParser()
    p.add_argument("--alertmanager", required=True)
    p.add_argument("--amtool", required=True)
    p.add_argument("--config-dir", required=True)
    p.add_argument("--env-file", required=True)
    p.add_argument("--state-dir", required=True)
    p.add_argument("--ready-timeout", type=float, default=30.0)
    p.add_argument("extra", nargs="*")
    args = p.parse_args(argv)
    if not args.ready_timeout > 0:
        _log(f"--ready-timeout must be positive, got {args.ready_timeout}")
        return 1

    os.makedirs(args.state_dir, exist_ok=True)
    try:
        config = stage_config(args.config_dir, args.state_dir, os.environ)
    except KeyError as e:
        _log(f"config placeholders not set in the environment: {e.args[0]}")
        return 1

    proc, url = _start(args, config, os.path.join(args.state_dir, "alertmanager.log"))
    port = url.rsplit(":", 1)[1]
    _write_env(args.env_file, url, port, os.path.abspath(args.amtool))
    _log(f"ready at {url}; env file {args.env_file}")

    # The handler only asks alertmanager to stop: the main thread is
    # blocked in proc.wait(), which holds Popen's wait lock, so waiting
    # here as well would stall until a timeout.
    stopping = []

    def _stop(signum, _frame):
        if not stopping:
            _log(f"signal {signum}; stopping")
            stopping.append(signum)
            proc.terminate()
            killer = threading.Timer(10, proc.kill)
            killer.daemon = True
            killer.start()

    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)
    rc = proc.wait()
    try:
        os.remove(args.env_file)
    except FileNotFoundError:
        pass
    if stopping:
        return 0
    _log(f"alertmanager exited with status {rc}")
    return rc or 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
