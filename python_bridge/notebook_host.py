"""Loopback notebook host. User code executes only in a child IPython kernel."""
from __future__ import annotations

import argparse
import base64
import json
import os
import queue
import socket
import struct
import sys
import shutil
import threading
import time
import traceback
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from queue import Empty

MAX_MESSAGE = 16 * 1024 * 1024

_USER_SIM_TIME_BOOTSTRAP = r'''import builtins as _jchm_builtin_module
import time as _jchm_wall_time_module
import types as _jchm_types_module
import jchm as _jchm_api_module

_jchm_sim_time_module = _jchm_types_module.ModuleType("time")
_jchm_sim_time_module.__dict__.update(vars(_jchm_wall_time_module))
_jchm_sim_time_module.sleep = _jchm_api_module.time.sleep
_jchm_sim_time_module.perf_counter = _jchm_api_module.time.perf_counter
_jchm_sim_time_module.monotonic = _jchm_api_module.time.monotonic
_jchm_real_user_import = _jchm_builtin_module.__import__

def _jchm_user_import(name, globals=None, locals=None, fromlist=(), level=0):
    if name == "time" and level == 0:
        return _jchm_sim_time_module
    return _jchm_real_user_import(name, globals, locals, fromlist, level)

_jchm_user_builtins = dict(vars(_jchm_builtin_module))
_jchm_user_builtins["__import__"] = _jchm_user_import
get_ipython().user_ns["__builtins__"] = _jchm_user_builtins
'''


def _recv_exact(connection: socket.socket, count: int) -> bytes:
    chunks = bytearray()
    while len(chunks) < count:
        block = connection.recv(count - len(chunks))
        if not block:
            raise ConnectionError("peer closed")
        chunks.extend(block)
    return bytes(chunks)


def _recv_message(connection: socket.socket) -> dict[str, Any]:
    size = struct.unpack("!I", _recv_exact(connection, 4))[0]
    if not 0 < size <= MAX_MESSAGE:
        raise ValueError(f"message size rejected: {size}")
    value = json.loads(_recv_exact(connection, size).decode("utf-8"))
    if not isinstance(value, dict):
        raise ValueError("message must be an object")
    return value


def _send_message(connection: socket.socket, lock: threading.Lock, message: dict[str, Any]) -> None:
    body = json.dumps(message, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    if len(body) > MAX_MESSAGE:
        body = json.dumps({"type": "error", "message": "output exceeded 16 MiB"}).encode()
    with lock:
        connection.sendall(struct.pack("!I", len(body)) + body)


class NotebookHost:
    def __init__(self, port: int, token: str, port_file: str = "") -> None:
        self.port = port
        self.token = token
        self.port_file = Path(port_file) if port_file else None
        self.kernel_spec_root: Path | None = None
        self.kernel_manager = None
        self.client = None
        self.connection: socket.socket | None = None
        self.api_connections: set[socket.socket] = set()
        self.api_connections_lock = threading.Lock()
        self.send_lock = threading.Lock()
        self.input_replies: queue.Queue[str] = queue.Queue()
        self.execution_lock = threading.Lock()
        self.running = True
        self.busy = False
        self.execution_count = 0
        self.latest_frame: dict[str, Any] | None = None
        self.frame_condition = threading.Condition()
        self.last_frame_id = -1
        local_app_data = Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData" / "Local"))
        self.log_path = local_app_data / "JajuchaGodotSimulatorData" / "logs" / "notebook_host.log"
        self.log_lock = threading.Lock()

    def _log_event(self, message: str) -> None:
        """Keep a small runtime trace for diagnosing kernel lifecycle failures."""
        try:
            self.log_path.parent.mkdir(parents=True, exist_ok=True)
            stamp = datetime.now(timezone.utc).isoformat(timespec="milliseconds")
            line = f"{stamp} [{threading.current_thread().name}] {message}\n"
            with self.log_lock:
                with self.log_path.open("a", encoding="utf-8") as log_file:
                    log_file.write(line)
        except OSError:
            pass

    def start(self) -> None:
        self._log_event("host_start")
        self._write_private_kernel_spec()
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind(("127.0.0.1", self.port))
        self.port = int(server.getsockname()[1])
        server.listen(32)
        server.settimeout(1)
        self._write_port_file()
        try:
            from jupyter_client import KernelManager

            bridge_dir = str(Path(__file__).resolve().parent)
            os.environ["PYTHONPATH"] = bridge_dir + os.pathsep + os.environ.get("PYTHONPATH", "")
            os.environ["JAJUCHA_NOTEBOOK_HOST"] = "127.0.0.1"
            os.environ["JAJUCHA_NOTEBOOK_PORT"] = str(self.port)
            os.environ["JAJUCHA_NOTEBOOK_TOKEN"] = self.token
            self.kernel_manager = KernelManager(kernel_name="python3")
            self._log_event("kernel_start_requested")
            self.kernel_manager.start_kernel()
            self._log_event("kernel_process_started")
            self.client = self.kernel_manager.client()
            self.client.start_channels()
            self.client.wait_for_ready(timeout=30)
            self._log_event("kernel_ready")
            self._install_user_sim_time_import()
            self._log_event("simulation_time_api_installed")
            self._write_port_file(include_kernel_pid=True)
            print(f"NOTEBOOK_HOST_READY {self.port}", flush=True)
            while self.running:
                try:
                    connection, _ = server.accept()
                except TimeoutError:
                    continue
                connection.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                threading.Thread(target=self._serve, args=(connection,), daemon=True).start()
        finally:
            self.running = False
            server.close()
            with self.api_connections_lock:
                api_connections = list(self.api_connections)
                self.api_connections.clear()
            for connection in api_connections:
                try:
                    connection.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass
                connection.close()
            self._shutdown_kernel()
            if self.port_file is not None:
                try:
                    self.port_file.unlink(missing_ok=True)
                except OSError:
                    pass
            if self.kernel_spec_root is not None:
                shutil.rmtree(self.kernel_spec_root, ignore_errors=True)

    def _write_port_file(self, *, include_kernel_pid: bool = False) -> None:
        if self.port_file is None:
            return
        self.port_file.parent.mkdir(parents=True, exist_ok=True)
        document: dict[str, int] = {"port": self.port}
        if include_kernel_pid and self.kernel_manager is not None:
            provisioner = getattr(self.kernel_manager, "provisioner", None)
            kernel_pid = getattr(provisioner, "pid", None)
            if kernel_pid is not None:
                document["kernel_pid"] = int(kernel_pid)
        temporary = self.port_file.with_suffix(self.port_file.suffix + ".tmp")
        temporary.write_text(json.dumps(document), encoding="utf-8")
        os.replace(temporary, self.port_file)

    def _install_user_sim_time_import(self) -> None:
        """Map user-cell `import time` calls to simulation time without changing the kernel's clock."""
        assert self.client is not None
        message_id = self.client.execute(
            _USER_SIM_TIME_BOOTSTRAP,
            silent=True,
            store_history=False,
            allow_stdin=False,
        )
        while True:
            try:
                message = self.client.get_iopub_msg(timeout=30)
            except Empty as error:
                raise TimeoutError("Kernel did not install the Jajucha simulation-time API") from error
            if message.get("parent_header", {}).get("msg_id") != message_id:
                continue
            if message.get("msg_type") == "error":
                content = message.get("content", {})
                raise RuntimeError("Simulation-time bootstrap failed: " + "\n".join(content.get("traceback", [])))
            if message.get("msg_type") == "status" and message.get("content", {}).get("execution_state") == "idle":
                return

    def _write_private_kernel_spec(self) -> None:
        """Use this bundled interpreter even when the user has other Jupyter kernels."""
        local_app_data = Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData" / "Local"))
        jupyter_root = local_app_data / "JajuchaGodotSimulatorData" / "jupyter_sessions" / self.token[:16]
        self.kernel_spec_root = jupyter_root
        kernel_dir = jupyter_root / "kernels" / "python3"
        kernel_dir.mkdir(parents=True, exist_ok=True)
        spec = {
            "argv": [sys.executable, "-m", "ipykernel_launcher", "-f", "{connection_file}"],
            "display_name": "Python 3 (Jajucha)",
            "language": "python",
            "metadata": {"debugger": True},
        }
        target = kernel_dir / "kernel.json"
        temporary = target.with_suffix(".json.tmp")
        temporary.write_text(json.dumps(spec, ensure_ascii=False), encoding="utf-8")
        os.replace(temporary, target)
        # The private path has priority over kernels installed elsewhere on this PC.
        os.environ["JUPYTER_PATH"] = str(jupyter_root)

    def _serve(self, connection: socket.socket) -> None:
        lock = self.send_lock
        try:
            hello = _recv_message(connection)
            if hello.get("type") != "hello" or hello.get("token") != self.token:
                return
            role = hello.get("role", "godot")
            if role == "godot":
                self.connection = connection
            _send_message(connection, lock, {"type": "ready", "token": self.token, "kernel": "Python 3"})
            if role == "api":
                with self.api_connections_lock:
                    self.api_connections.add(connection)
                try:
                    while self.running:
                        request = _recv_message(connection)
                        if request.get("token") != self.token:
                            _send_message(connection, lock, {"type": "error", "message": "authentication failed"})
                            break
                        _send_message(connection, lock, self._api_call(request))
                except (ConnectionError, OSError, ValueError, json.JSONDecodeError):
                    pass
                finally:
                    with self.api_connections_lock:
                        self.api_connections.discard(connection)
                    connection.close()
                return
            while self.running:
                command = _recv_message(connection)
                if command.get("token") != self.token:
                    _send_message(connection, lock, {"type": "error", "message": "authentication failed"})
                    continue
                kind = command.get("type")
                if kind == "sensor_frame":
                    with self.frame_condition:
                        self.latest_frame = command
                        self.last_frame_id = int(command.get("frame_id", self.last_frame_id))
                        self.frame_condition.notify_all()
                elif kind == "execute":
                    threading.Thread(target=self._execute, args=(connection, lock, command), daemon=True).start()
                elif kind == "interrupt":
                    self.input_replies.put("\x03")
                    if self.kernel_manager is not None:
                        self.kernel_manager.interrupt_kernel()
                    threading.Thread(target=self._interrupt_watchdog, args=(connection, lock, command.get("request_id"), command.get("cell_id", -1)), daemon=True).start()
                    _send_message(connection, lock, {"type": "interrupt_ack", "request_id": command.get("request_id")})
                elif kind == "input_reply":
                    self.input_replies.put(str(command.get("value", "")))
                elif kind == "restart":
                    self._log_event("restart_requested")
                    try:
                        self._restart_kernel()
                    except Exception as error:
                        detail = f"{type(error).__name__}: {error}\n{traceback.format_exc()}"
                        self._log_event("restart_failed " + detail)
                        self._safe_stop()
                        _send_message(connection, lock, {"type": "error", "message": "Kernel restart failed. See the notebook host log.\n" + detail})
                    else:
                        self._log_event("restart_complete")
                        _send_message(connection, lock, {"type": "restarted"})
                elif kind == "status":
                    _send_message(connection, lock, {"type": "status", "busy": self.busy, "kernel_alive": bool(self.kernel_manager and self.kernel_manager.is_alive())})
                elif kind == "shutdown":
                    self.running = False
                    _send_message(connection, lock, {"type": "shutdown_ack"})
                    break
        except (OSError, ValueError, ConnectionError, json.JSONDecodeError):
            if connection is self.connection:
                self.connection = None
                self.running = False

    def _api_call(self, request: dict[str, Any]) -> dict[str, Any]:
        operation = str(request.get("operation", ""))
        if operation == "sensor":
            after = int(request.get("after_frame", -1))
            deadline = time.monotonic() + 4.0
            with self.frame_condition:
                while (self.latest_frame is None or self.last_frame_id <= after) and time.monotonic() < deadline:
                    self.frame_condition.wait(0.2)
                if self.latest_frame is None:
                    return {"type": "api_result", "ok": False, "error": "No simulator sensor frames are available."}
                return {"type": "api_result", "ok": True, "frame": self.latest_frame}
        if operation == "control":
            command = request.get("command", {})
            if not isinstance(command, dict):
                return {"type": "api_result", "ok": False, "error": "Invalid motor command."}
            if self.connection is None:
                return {"type": "api_result", "ok": False, "error": "Simulator is disconnected."}
            _send_message(self.connection, self.send_lock, {"type": "notebook_control", **command})
            return {"type": "api_result", "ok": True}
        if operation == "display":
            if self.connection is None:
                return {"type": "api_result", "ok": False, "error": "Simulator is disconnected."}
            _send_message(self.connection, self.send_lock, {"type": "notebook_display", **request.get("display", {})})
            return {"type": "api_result", "ok": True}
        return {"type": "api_result", "ok": False, "error": f"Unsupported simulator API: {operation}"}

    def _execute(self, connection: socket.socket, lock: threading.Lock, command: dict[str, Any]) -> None:
        if not self.execution_lock.acquire(blocking=False):
            _send_message(connection, lock, {"type": "execution_done", "request_id": command.get("request_id"), "cell_id": command.get("cell_id"), "success": False, "output": "Kernel is already executing a cell.", "execution_count": self.execution_count})
            return
        self.busy = True
        request_id = command.get("request_id")
        cell_id = command.get("cell_id", -1)
        output: list[str] = []
        success = True
        try:
            assert self.client is not None
            message_id = self.client.execute(str(command.get("code", "")), allow_stdin=True, stop_on_error=True)
            while self.running:
                try:
                    message = self.client.get_iopub_msg(timeout=0.15)
                except Empty:
                    self._check_stdin(connection, lock, request_id)
                    continue
                if message.get("parent_header", {}).get("msg_id") != message_id:
                    continue
                kind = message.get("msg_type")
                content = message.get("content", {})
                if kind == "stream":
                    value = str(content.get("text", ""))
                    output.append(value)
                    _send_message(connection, lock, {"type": "cell_output", "request_id": request_id, "cell_id": cell_id, "text": value})
                elif kind in ("display_data", "execute_result"):
                    data = content.get("data", {})
                    if "text/plain" in data:
                        value = str(data["text/plain"]) + "\n"
                        output.append(value)
                        _send_message(connection, lock, {"type": "cell_output", "request_id": request_id, "cell_id": cell_id, "text": value})
                    for mime in ("image/png", "image/jpeg"):
                        if mime in data:
                            raw = data[mime]
                            if isinstance(raw, list):
                                raw = "".join(raw)
                            encoded = raw if isinstance(raw, str) else base64.b64encode(raw).decode("ascii")
                            _send_message(connection, lock, {"type": "cell_image", "request_id": request_id, "cell_id": cell_id, "mime": mime, "data": encoded})
                elif kind == "error":
                    success = False
                    value = "\n".join(content.get("traceback", [])) + "\n"
                    output.append(value)
                    _send_message(connection, lock, {"type": "cell_output", "request_id": request_id, "cell_id": cell_id, "text": value, "error": True})
                elif kind == "status" and content.get("execution_state") == "idle":
                    break
                self._check_stdin(connection, lock, request_id)
            if not success:
                self._safe_stop()
            self.execution_count += 1
            _send_message(connection, lock, {"type": "execution_done", "request_id": request_id, "cell_id": cell_id, "success": success, "output": "".join(output), "execution_count": self.execution_count})
        except BaseException as error:
            self._safe_stop()
            _send_message(connection, lock, {"type": "execution_done", "request_id": request_id, "cell_id": cell_id, "success": False, "output": f"{type(error).__name__}: {error}", "execution_count": self.execution_count})
        finally:
            self.busy = False
            self.execution_lock.release()

    def _check_stdin(self, connection: socket.socket, lock: threading.Lock, request_id: Any) -> None:
        assert self.client is not None
        while True:
            try:
                message = self.client.get_stdin_msg(timeout=0)
            except Empty:
                return
            content = message.get("content", {})
            _send_message(connection, lock, {"type": "input_request", "request_id": request_id, "prompt": content.get("prompt", ""), "password": content.get("password", False)})
            value = self.input_replies.get()
            if value == "\x03":
                return
            self.client.input(value)

    def _safe_stop(self) -> None:
        if self.connection is not None:
            try:
                _send_message(self.connection, self.send_lock, {"type": "safe_stop"})
            except OSError:
                pass

    def _interrupt_watchdog(self, connection: socket.socket, lock: threading.Lock, request_id: Any, cell_id: Any) -> None:
        time.sleep(2.0)
        if not self.busy or self.kernel_manager is None:
            return
        try:
            self.kernel_manager.restart_kernel(now=True)
            if self.client is not None:
                self.client.stop_channels()
            self.client = self.kernel_manager.client()
            self.client.start_channels()
            self.client.wait_for_ready(timeout=20)
            self.execution_count = 0
            self.busy = False
            self._safe_stop()
            _send_message(connection, lock, {"type": "kernel_killed", "request_id": request_id, "cell_id": cell_id, "message": "Kernel did not stop within two seconds. It was terminated; notebook variables were cleared."})
        except Exception as error:
            self._safe_stop()
            _send_message(connection, lock, {"type": "error", "message": f"Kernel restart after failed interrupt failed: {error}"})

    def _restart_kernel(self) -> None:
        assert self.kernel_manager is not None
        self._log_event("kernel_manager_restart_begin")
        self.kernel_manager.restart_kernel(now=True)
        self._log_event("kernel_manager_restart_returned")
        self.client.stop_channels()
        self.client = self.kernel_manager.client()
        self.client.start_channels()
        self.client.wait_for_ready(timeout=30)
        self._log_event("restarted_kernel_ready")
        self._install_user_sim_time_import()
        self.execution_count = 0

    def _shutdown_kernel(self) -> None:
        if self.client is not None:
            self.client.stop_channels()
        if self.kernel_manager is not None:
            try:
                self.kernel_manager.shutdown_kernel(now=True)
            except Exception:
                pass


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--port-file", default="")
    parser.add_argument("--token", required=True)
    args = parser.parse_args()
    NotebookHost(args.port, args.token, args.port_file).start()


if __name__ == "__main__":
    main()
