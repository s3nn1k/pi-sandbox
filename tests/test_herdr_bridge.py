import contextlib
import importlib.machinery
import importlib.util
import io
import json
import os
import shutil
import sys
import tempfile
import unittest
from unittest import mock

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BRIDGE_PATH = os.path.join(REPO_ROOT, "bin", "herdr-sock-bridge")
FEDORA_TRANSPORT_PATH = os.path.join(
    REPO_ROOT, "platform", "fedora", "bridge-transport.py"
)


def load_module(name, path):
    loader = importlib.machinery.SourceFileLoader(name, path)
    spec = importlib.util.spec_from_loader(name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


BRIDGE = load_module("herdr_sock_bridge", BRIDGE_PATH)
REAL_SOCKET = BRIDGE.socket
REAL_PIPE_RESPONSES = BRIDGE.pipe_responses


class FakeSocket:
    def __init__(self, recv_chunks=()):
        self.recv_chunks = list(recv_chunks)
        self.sent = []
        self.closed = False
        self.shut_down = False
        self.connected_to = None

    def settimeout(self, timeout):
        pass

    def shutdown(self, how):
        self.shut_down = True

    def connect(self, address):
        self.connected_to = address

    def recv(self, bufsize):
        if self.recv_chunks:
            return self.recv_chunks.pop(0)
        return b""

    def sendall(self, data):
        self.sent.append(bytes(data))

    def close(self):
        self.closed = True


class FakeSocketModule:
    AF_UNIX = REAL_SOCKET.AF_UNIX
    SOCK_STREAM = REAL_SOCKET.SOCK_STREAM
    SHUT_RDWR = REAL_SOCKET.SHUT_RDWR

    def __init__(self, upstream):
        self.upstream = upstream

    def socket(self, family, type):
        return self.upstream


class HandleTests(unittest.TestCase):
    def setUp(self):
        self.upstream = FakeSocket()
        self.client = FakeSocket()
        BRIDGE.socket = FakeSocketModule(self.upstream)
        BRIDGE.pipe_responses = lambda upstream, client: None
        self.addCleanup(setattr, BRIDGE, "socket", REAL_SOCKET)
        self.addCleanup(setattr, BRIDGE, "pipe_responses", REAL_PIPE_RESPONSES)

    def run_handle(self):
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            BRIDGE._handle(self.client)
        return stderr.getvalue()

    def assert_rejected_with(self, request_id):
        self.assertEqual(self.upstream.sent, [])
        self.assertEqual(self.client.sent, [BRIDGE.reject_response(request_id)])

    def test_report_agent_forwards_normalized_request(self):
        self.client.recv_chunks = [b'{"id": 3,  "method": "pane.report_agent"}\n', b""]
        self.run_handle()
        self.assertEqual(
            self.upstream.sent,
            [b'{"id": 3, "method": "pane.report_agent"}\n'],
        )

    def test_report_agent_session_forwards_normalized_request(self):
        self.client.recv_chunks = [
            b'{"id": "s1", "method": "pane.report_agent_session", "params": {"a": 1}}\n',
            b"",
        ]
        self.run_handle()
        self.assertEqual(len(self.upstream.sent), 1)
        sent = json.loads(self.upstream.sent[0])
        self.assertEqual(sent["id"], "s1")
        self.assertEqual(sent["method"], "pane.report_agent_session")

    def test_foreign_method_rejects_with_client_id_and_closes(self):
        self.client.recv_chunks = [b'{"id": 7, "method": "pane.close"}\n', b""]
        self.run_handle()
        self.assert_rejected_with(7)
        self.assertTrue(self.client.closed)
        self.assertTrue(self.upstream.closed)

    def test_invalid_json_rejects_with_null_id_without_raising(self):
        self.client.recv_chunks = [b"not json\n", b""]
        self.run_handle()
        self.assert_rejected_with(None)

    def test_non_dict_json_rejects_without_raising(self):
        self.client.recv_chunks = [b'[{"method": "pane.close"}]\n', b""]
        self.run_handle()
        self.assert_rejected_with(None)

    def test_empty_lines_are_skipped(self):
        self.client.recv_chunks = [b"\n\n", self.allowed_line(), b""]
        self.run_handle()
        self.assertEqual(len(self.upstream.sent), 1)

    def test_two_requests_in_single_chunk_both_forwarded(self):
        chunk = self.allowed_line("pane.report_agent", 1) + self.allowed_line(
            "pane.report_agent_session", 2
        )
        self.client.recv_chunks = [chunk, b""]
        self.run_handle()
        self.assertEqual(len(self.upstream.sent), 2)

    def test_oversized_line_rejects_and_closes(self):
        self.client.recv_chunks = [b"x" * (BRIDGE.MAX_LINE + 1), b""]
        stderr = self.run_handle()
        self.assertIn("reject", stderr)
        self.assertEqual(self.upstream.sent, [])
        self.assertTrue(self.client.closed)
        self.assertTrue(self.upstream.closed)

    def allowed_line(self, method="pane.report_agent", request_id=1):
        return json.dumps({"id": request_id, "method": method}).encode("utf-8") + b"\n"


class RejectHardeningTests(HandleTests):
    def test_method_as_list_rejects_with_scalar_id_without_raising(self):
        self.client.recv_chunks = [b'{"id": 1, "method": []}\n', b""]
        self.run_handle()
        self.assert_rejected_with(1)

    def test_deeply_nested_json_rejects_without_raising(self):
        self.client.recv_chunks = [b"[" * 100000 + b"]" * 100000 + b"\n", b""]
        self.run_handle()
        self.assert_rejected_with(None)

    def test_every_exit_shuts_down_both_sockets(self):
        self.client.recv_chunks = [b'{"id": 7, "method": "pane.close"}\n', b""]
        self.run_handle()
        self.assertTrue(self.client.shut_down)
        self.assertTrue(self.upstream.shut_down)
        self.client = FakeSocket(recv_chunks=[self.allowed_line()])
        self.run_handle()
        self.assertTrue(self.client.shut_down)
        self.assertTrue(self.upstream.shut_down)

    def test_parse_request_keeps_request_for_non_string_method(self):
        self.assertEqual(
            BRIDGE.parse_request(b'{"id": 5, "method": 1}'), ({"id": 5, "method": 1}, None)
        )

    def test_nested_id_echoed_as_null_in_reject(self):
        self.client.recv_chunks = [b'{"id": {"a": 1}, "method": "pane.close"}\n', b""]
        self.run_handle()
        self.assert_rejected_with(None)

    def test_unserializable_allow_request_closes_without_raising(self):
        depth = 60000
        line = (b'{"id": 1, "method": "pane.report_agent", "params": ' + b"[" * depth + b"]" * depth + b"}\n")
        self.client.recv_chunks = [line, b""]
        self.run_handle()
        self.assertTrue(self.client.closed)
        self.assertTrue(self.upstream.closed)


class LoadTransportTests(unittest.TestCase):
    def test_missing_transport_exits_loud(self):
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            with self.assertRaises(SystemExit):
                BRIDGE.load_transport("no-such-platform")
        self.assertIn("bridge transport not found", stderr.getvalue())


class FedoraTransportTests(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.mkdtemp(prefix="herdr-bridge-test.")
        self.addCleanup(shutil.rmtree, self.tempdir, True)
        self.listen_path = os.path.join(self.tempdir, "herdr.sock")
        argv = mock.patch.object(sys, "argv", ["bridge", self.listen_path])
        argv.start()
        self.addCleanup(argv.stop)
        self.transport = load_module("fedora_transport", FEDORA_TRANSPORT_PATH)
        heal = mock.patch.object(self.transport, "self_heal", lambda holder, path: None)
        heal.start()
        self.addCleanup(heal.stop)

    def test_keep_alive_returns_the_shared_holder_that_accept_loop_reads(self):
        server = self.transport.listen()
        holder = self.transport.keep_alive(server)
        self.assertIs(holder[0], server)
        replacement = self.transport.bind_holder(self.listen_path)
        holder[:] = replacement
        self.assertIs(holder[0], replacement[0])
        replacement[0].close()

    def test_keep_alive_rejects_a_foreign_server(self):
        server = self.transport.listen()
        foreign = self.transport.bind_holder(self.listen_path)[0]
        self.addCleanup(foreign.close)
        self.addCleanup(server.close)
        with self.assertRaises(RuntimeError):
            self.transport.keep_alive(foreign)


class ResolvePlatformTests(unittest.TestCase):
    def resolve(self, forced, system):
        env = {"PI_SANDBOX_PLATFORM": forced} if forced is not None else {}
        with mock.patch.dict(os.environ, env, clear=True):
            with mock.patch.object(BRIDGE.platform, "system", return_value=system):
                return BRIDGE.resolve_platform()

    def test_env_forces_fedora(self):
        self.assertEqual(self.resolve("fedora", "Darwin"), "fedora")

    def test_env_forces_macos(self):
        self.assertEqual(self.resolve("macos", "Linux"), "macos")

    def test_unknown_env_exits_loud(self):
        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit):
                self.resolve("solaris", "Linux")

    def test_uname_linux_maps_to_fedora(self):
        self.assertEqual(self.resolve(None, "Linux"), "fedora")

    def test_uname_darwin_maps_to_macos(self):
        self.assertEqual(self.resolve(None, "Darwin"), "macos")

    def test_unknown_uname_exits_loud(self):
        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit):
                self.resolve(None, "FreeBSD")


if __name__ == "__main__":
    unittest.main()
