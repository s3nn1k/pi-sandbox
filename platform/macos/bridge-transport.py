import socket
import sys

PORT = 4761


def log(msg):
    print("herdr-bridge: %s" % msg, file=sys.stderr, flush=True)


def listen():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", PORT))
    server.listen(16)
    log("listening on 127.0.0.1:%d" % PORT)
    return server
