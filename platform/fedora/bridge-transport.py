import os
import shutil
import socket
import stat
import sys
import threading
import time

DEFAULT_LISTEN_PATH = os.path.expanduser("~/tmp/pi-cache/herdr-bridge/herdr.sock")

holder = [None, None]


def log(msg):
    print("herdr-bridge: %s" % msg, file=sys.stderr, flush=True)


def listen_path():
    return sys.argv[1] if len(sys.argv) > 1 else DEFAULT_LISTEN_PATH


def bind_listen(listen_path):
    listen_dir = os.path.dirname(listen_path)
    if listen_dir:
        os.makedirs(listen_dir, exist_ok=True)
    try:
        os.unlink(listen_path)
    except FileNotFoundError:
        pass
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(listen_path)
    os.chmod(listen_path, 0o600)
    server.listen(16)
    server.settimeout(5)
    return server


def bind_holder(listen_path):
    server = bind_listen(listen_path)
    return [server, os.stat(listen_path).st_ino]


def listen():
    holder[:] = bind_holder(listen_path())
    log("listening on %s" % listen_path())
    return holder[0]


def keep_alive(server):
    if holder[0] is not server:
        raise RuntimeError("listen holder diverged from the server passed to keep_alive")
    threading.Thread(
        target=self_heal, args=(holder, listen_path()), daemon=True
    ).start()
    return holder


def self_heal(holder, listen_path):
    failures = 0
    while True:
        time.sleep(5)
        try:
            sock_ok = False
            foreign = False
            try:
                st = os.lstat(listen_path)
                sock_ok = stat.S_ISSOCK(st.st_mode)
                foreign = sock_ok and st.st_ino != holder[1]
            except FileNotFoundError:
                pass
            if sock_ok and not foreign:
                failures = 0
                continue
            if foreign:
                os.unlink(listen_path)
                log("foreign socket replaced at %s" % listen_path)
            elif os.path.islink(listen_path):
                os.unlink(listen_path)
                log("removed symlink at %s" % listen_path)
            elif os.path.isdir(listen_path):
                os.chmod(listen_path, 0o700)
                shutil.rmtree(listen_path)
                log("removed directory at %s" % listen_path)
            elif os.path.lexists(listen_path):
                os.unlink(listen_path)
                log("removed file at %s" % listen_path)
            try:
                holder[0].close()
            except OSError:
                pass
            holder[:] = bind_holder(listen_path)
            log("rebound after replacement")
            failures = 0
        except Exception as exc:
            failures += 1
            log("heal cycle failed (%d): %s" % (failures, exc))
            if failures >= 3:
                log("self-heal exhausted, restarting via systemd")
                os._exit(1)
