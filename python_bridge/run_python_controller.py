"""Run the supplied center-camera BEV controller against the Godot simulator.

This file implements only the offline subset of the Jajucha jchm interface.
No robot communication or motor-control package is imported.
"""
from __future__ import annotations

import argparse
import base64
import builtins
from contextlib import redirect_stderr, redirect_stdout
import json
import os
import queue
import runpy
import socket
import struct
import sys
import threading
import time as wall_time
import types
from pathlib import Path

import cv2
import numpy as np


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SCRIPT = ROOT / "python_bridge" / "user_supplied_controller.py"
MAX_FRAME_BYTES = 8_000_000


def recv_exact(sock: socket.socket, size: int) -> bytes:
    data = bytearray()
    while len(data) < size:
        chunk = sock.recv(size - len(data))
        if not chunk:
            raise ConnectionError("Godot closed the simulator connection")
        data.extend(chunk)
    return bytes(data)


def recv_packet(sock: socket.socket) -> dict:
    (size,) = struct.unpack("!I", recv_exact(sock, 4))
    if size <= 0 or size > MAX_FRAME_BYTES:
        raise ValueError(f"Godot packet size rejected: {size}")
    message = json.loads(recv_exact(sock, size).decode("utf-8"))
    if not isinstance(message, dict):
        raise ValueError("Bridge message must be a JSON object")
    return message


class SimulationClock:
    """Wait using sensor timestamps so script timers follow simulated time."""

    def __init__(self) -> None:
        self.condition = threading.Condition()
        self.timestamp_s = 0.0
        self.latest: dict | None = None
        self.failed: BaseException | None = None
        self.stopping = False

    def update(self, frame: dict) -> None:
        with self.condition:
            self.latest = frame
            self.timestamp_s = float(frame.get("timestamp_s", self.timestamp_s))
            self.condition.notify_all()

    def fail(self, error: BaseException) -> None:
        with self.condition:
            self.failed = error
            self.condition.notify_all()

    def next_frame(self, after: int | None = None) -> dict:
        with self.condition:
            while not self.stopping and self.failed is None and (
                self.latest is None
                or (after is not None and int(self.latest.get("frame_id", -1)) <= after)
            ):
                self.condition.wait(0.5)
            if self.failed is not None:
                raise ConnectionError(str(self.failed))
            if self.stopping or self.latest is None:
                raise KeyboardInterrupt("simulator stopped")
            return self.latest

    def sleep(self, duration: float) -> None:
        deadline: float
        with self.condition:
            deadline = self.timestamp_s + max(0.0, float(duration))
            while not self.stopping and self.failed is None and self.timestamp_s < deadline:
                self.condition.wait(0.5)
            if self.failed is not None:
                raise ConnectionError(str(self.failed))

    def perf_counter(self) -> float:
        with self.condition:
            return self.timestamp_s

    def stop(self) -> None:
        with self.condition:
            self.stopping = True
            self.condition.notify_all()


class GodotBridge:
    def __init__(self, host: str, port: int, script: str = "") -> None:
        self.host = host
        self.port = port
        self.script = script
        self.clock = SimulationClock()
        self.sock: socket.socket | None = None
        self.send_lock = threading.Lock()
        self.last_model_frame_id = -1
        self.images: dict[tuple[int, str], np.ndarray] = {}
        self.depths: dict[int, np.ndarray] = {}
        self.lidar: dict[int, tuple[np.ndarray, np.ndarray]] = {}
        self.log_messages: queue.Queue[str] = queue.Queue(maxsize=200)
        self.connection: socket.socket | None = None
        capture_dir = os.environ.get("JAJUCHA_CAPTURE_DIR", "")
        self.capture_dir = Path(capture_dir) if capture_dir else None
        if self.capture_dir:
            (self.capture_dir / "frames").mkdir(parents=True, exist_ok=True)

    def serve(self) -> None:
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind((self.host, self.port))
        server.listen(1)
        server.settimeout(0.5)
        print(f"Waiting for Godot on {self.host}:{self.port}", flush=True)
        while self.connection is None and not self.clock.stopping:
            try:
                self.connection, _ = server.accept()
            except TimeoutError:
                continue
        server.close()
        if self.connection is None:
            return
        print(f"Godot connected from {self.connection.getpeername()}", flush=True)
        self.sock = self.connection
        self.sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        reader = threading.Thread(target=self._reader, name="godot-sensor-reader", daemon=True)
        reader.start()
        self._run_controller()
        self.clock.stop()
        try:
            self.send_command({"stop": True, "motor": 0, "left_servo": 0, "right_servo": 0})
        except (ConnectionError, OSError):
            pass
        if self.sock is not None:
            try:
                self.sock.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            self.sock.close()

    def _reader(self) -> None:
        try:
            assert self.sock is not None
            while not self.clock.stopping:
                message = recv_packet(self.sock)
                if message.get("type") == "sensor_frame":
                    frame_id = int(message.get("frame_id", -1))
                    for name, encoded in message.get("images_png_b64", {}).items():
                        png = base64.b64decode(encoded)
                        if self.capture_dir:
                            (self.capture_dir / "frames" / f"{frame_id:06d}_{name.removesuffix('_rgb')}.png").write_bytes(png)
                        data = np.frombuffer(png, dtype=np.uint8)
                        image = cv2.imdecode(data, cv2.IMREAD_COLOR)
                        if image is None or image.shape[:2] != (400, 640):
                            raise ValueError(f"Bad {name} frame shape: {None if image is None else image.shape}")
                        self.images[(frame_id, name.removesuffix("_rgb"))] = image
                    depth_encoded = message.get("depth_gray_png_b64")
                    if depth_encoded:
                        data = np.frombuffer(__import__("base64").b64decode(depth_encoded), dtype=np.uint8)
                        image = cv2.imdecode(data, cv2.IMREAD_COLOR)
                        if image is not None:
                            self.depths[frame_id] = image
                    angles = np.asarray(message.get("lidar_angles_deg", []), dtype=np.float32)
                    ranges = np.asarray(message.get("lidar_ranges_mm", []), dtype=np.float32)
                    self.lidar[frame_id] = angles, ranges
                    if self.capture_dir:
                        self._record("frames.jsonl", {key: value for key, value in message.items() if key in ("frame_id", "timestamp_s", "vehicle_pose", "sensor_spec")})
                    self.clock.update(message)
                    self._trim_frames(frame_id)
                elif message.get("type") == "model_display":
                    self._display_in_godot(message)
                elif message.get("type") == "model_log":
                    try:
                        self.log_messages.put_nowait(str(message.get("text", "")))
                    except queue.Full:
                        pass
        except (OSError, ValueError, ConnectionError) as error:
            print(f"Sensor reader stopped: {type(error).__name__}: {error}", flush=True)
            self.clock.fail(error)
            self.send_emergency_stop()

    def _trim_frames(self, frame_id: int) -> None:
        earliest = frame_id - 4
        self.images = {key: value for key, value in self.images.items() if key[0] >= earliest}
        self.depths = {key: value for key, value in self.depths.items() if key >= earliest}
        self.lidar = {key: value for key, value in self.lidar.items() if key >= earliest}

    def _run_controller(self) -> None:
        script = Path(self.script).resolve() if self.script else DEFAULT_SCRIPT
        if not script.is_file():
            self._log(f"Driving script not found: {script}")
            return
        self._log(f"Running supplied BEV controller: {script}")
        print(f"Executing controller source: {script}", flush=True)
        facade = JchmFacade(self)
        self._facade = facade
        old_import = builtins.__import__
        clock_module = types.ModuleType("time")
        clock_module.sleep = self.clock.sleep
        clock_module.perf_counter = self.clock.perf_counter
        clock_module.monotonic = self.clock.perf_counter

        def shim_import(name: str, globals=None, locals=None, fromlist=(), level=0):
            if name == "jchm":
                return facade.module
            if name == "time":
                return clock_module
            return old_import(name, globals, locals, fromlist, level)

        module_builtins = dict(vars(builtins))
        module_builtins["__import__"] = shim_import
        def controller_print(*values, **options):
            text = options.get("sep", " ").join(str(value) for value in values)
            self._log(text)
        module_builtins["print"] = controller_print
        namespace = {"__name__": "__main__", "__file__": str(script), "__builtins__": module_builtins}
        try:
            runpy.run_path(str(script), init_globals=namespace, run_name="__main__")
        except KeyboardInterrupt:
            self._log("Controller stopped.")
        except BaseException as error:
            self.send_emergency_stop()
            self._log(f"Controller error: {type(error).__name__}: {error}")
            import traceback
            traceback.print_exc()
            raise

    def send_command(self, command: dict) -> None:
        if self.sock is None:
            return
        payload = json.dumps(command, separators=(",", ":")).encode("utf-8")
        if len(payload) > MAX_FRAME_BYTES:
            raise ValueError("Command message too large")
        with self.send_lock:
            self.sock.sendall(struct.pack("!I", len(payload)) + payload)
        if self.capture_dir and "motor" in command:
            self._record("commands.jsonl", command)

    def _record(self, filename: str, value: dict) -> None:
        assert self.capture_dir is not None
        with (self.capture_dir / filename).open("a", encoding="utf-8") as stream:
            stream.write(json.dumps(value, ensure_ascii=False) + "\n")

    def send_emergency_stop(self) -> None:
        try:
            self.send_command({"stop": True, "motor": 0, "left_servo": 0, "right_servo": 0})
        except (OSError, ValueError):
            pass

    def _display_in_godot(self, message: dict) -> None:
        pass

    def _log(self, message: str) -> None:
        if self.capture_dir:
            self._record("controller_log.jsonl", {"timestamp_s": self.clock.perf_counter(), "text": message})
        try:
            self.send_command({"type": "model_log", "text": str(message)})
        except (OSError, ValueError):
            pass


class CameraAPI:
    def __init__(self, bridge: GodotBridge) -> None:
        self.bridge = bridge

    def _current(self) -> dict:
        if self.bridge.clock.latest is None:
            return self.bridge.clock.next_frame()
        return self.bridge.clock.latest

    def get_image(self, source: str = "center") -> np.ndarray | None:
        source = str(source).lower()
        if source == "depth":
            return self.get_depth()
        if source == "lidar":
            return self.bridge._facade.lidar.render()
        frame = self.bridge.clock.next_frame(after=self.bridge.last_model_frame_id)
        frame_id = int(frame["frame_id"])
        self.bridge.last_model_frame_id = frame_id
        image = self.bridge.images.get((frame_id, source))
        return None if image is None else image.copy()

    def get_depth(self) -> np.ndarray:
        frame = self._current()
        return self.bridge.depths.get(int(frame["frame_id"]), np.zeros((400, 640, 3), dtype=np.uint8)).copy()

    def show_image(self, image, source="center", quality=80) -> None:
        array = np.asarray(image)
        if array.ndim == 2:
            array = cv2.cvtColor(array.astype(np.uint8), cv2.COLOR_GRAY2BGR)
        if array.ndim != 3 or array.shape[2] < 3:
            raise ValueError("show_image expects a grayscale or BGR image")
        array = np.ascontiguousarray(np.clip(array[..., :3], 0, 255).astype(np.uint8))
        ok, encoded = cv2.imencode(".png", array)
        if not ok:
            raise RuntimeError("Could not encode Python output image")
        import base64
        self.bridge.send_command({
            "type": "model_display",
            "display_source": str(source).lower(),
            "display_png_b64": base64.b64encode(encoded).decode("ascii"),
        })


class LidarAPI:
    def __init__(self, bridge: GodotBridge) -> None:
        self.bridge = bridge

    def get_lidar(self):
        frame = self.bridge.clock.latest
        if frame is None:
            return np.empty(0, np.float32), np.empty(0, np.float32)
        angles, ranges = self.bridge.lidar.get(int(frame["frame_id"]), (np.empty(0, np.float32), np.empty(0, np.float32)))
        return angles.copy(), ranges.copy()

    def render(self, theta_array=None, dist_array=None, max_dist=12000):
        if theta_array is None or dist_array is None:
            theta_array, dist_array = self.get_lidar()
        image = np.zeros((400, 640, 3), dtype=np.uint8)
        center, radius = (320, 200), 175
        max_distance = max(1.0, float(max_dist))
        for angle, distance in zip(theta_array, dist_array):
            if not np.isfinite(distance) or distance < 50.0 or distance >= 12000.0 or distance > max_distance:
                continue
            radial = min(float(distance) / max_distance, 1.0) * radius
            theta = np.deg2rad(float(angle))
            point = (round(center[0] + radial * np.sin(theta)), round(center[1] - radial * np.cos(theta)))
            cv2.circle(image, point, 2, (40, 170, 245), -1)
        return image

    def show_lidar(self, theta_array, dist_array, max_dist=12000):
        self.bridge._facade.camera.show_image(self.render(theta_array, dist_array, max_dist), "lidar")


class ControlAPI:
    def __init__(self, bridge: GodotBridge) -> None:
        self.bridge = bridge

    def set_motor(self, left, right=None, speed=None):
        if speed is None:
            speed, right = right, left
        self.bridge.send_command({
            "left_servo": float(left),
            "right_servo": float(right),
            "motor": float(speed),
            "timestamp_s": self.bridge.clock.perf_counter(),
        })


class JchmFacade:
    def __init__(self, bridge: GodotBridge) -> None:
        self.camera = CameraAPI(bridge)
        self.lidar = LidarAPI(bridge)
        self.control = ControlAPI(bridge)
        self.module = types.ModuleType("jchm")
        self.module.camera = self.camera
        self.module.lidar = self.lidar
        self.module.control = self.control


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--script", default="", help="Use another jchm-compatible Python script")
    parser.add_argument("--log-file", default="", help="Append bridge diagnostics to this local file")
    args = parser.parse_args(argv)
    bridge = GodotBridge(args.host, args.port, args.script)
    log_path = Path(args.log_file) if args.log_file else Path(os.environ.get("LOCALAPPDATA", Path.home())) / "JajuchaGodotSimulatorData" / "logs" / "controller.log"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("a", encoding="utf-8", buffering=1) as log_stream:
        try:
            with redirect_stdout(log_stream), redirect_stderr(log_stream):
                print(f"Jajucha controller bridge starting with {sys.executable}")
                bridge.serve()
        finally:
            bridge.clock.stop()


if __name__ == "__main__":
    main()
