"""Notebook-safe Jajucha API. Calls are authenticated, local RPCs to Godot."""
from __future__ import annotations

import base64
import os
import socket
import struct
import threading
import time as _wall_time
from types import SimpleNamespace

import cv2
import numpy as np


_api_lock = threading.Lock()
_api_connection: socket.socket | None = None


def _read_exact(connection: socket.socket, size: int) -> bytes:
    data = bytearray()
    while len(data) < size:
        block = connection.recv(size - len(data))
        if not block:
            raise ConnectionError("Jajucha simulator disconnected")
        data.extend(block)
    return bytes(data)


def _recv(connection: socket.socket) -> dict:
    size = struct.unpack("!I", _read_exact(connection, 4))[0]
    if not 0 < size <= 16 * 1024 * 1024:
        raise ValueError("Jajucha response exceeds the size limit")
    import json
    return json.loads(_read_exact(connection, size).decode("utf-8"))


def _send(connection: socket.socket, value: dict) -> None:
    import json
    body = json.dumps(value, separators=(",", ":")).encode("utf-8")
    connection.sendall(struct.pack("!I", len(body)) + body)


def _rpc(operation: str, **payload) -> dict:
    global _api_connection
    host = os.environ.get("JAJUCHA_NOTEBOOK_HOST", "127.0.0.1")
    port = int(os.environ["JAJUCHA_NOTEBOOK_PORT"])
    token = os.environ["JAJUCHA_NOTEBOOK_TOKEN"]
    with _api_lock:
        for attempt in range(2):
            try:
                if _api_connection is None:
                    _api_connection = socket.create_connection((host, port), timeout=8)
                    _api_connection.settimeout(8)
                    _api_connection.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                    _send(_api_connection, {"type": "hello", "role": "api", "token": token})
                    ready = _recv(_api_connection)
                    if ready.get("type") != "ready":
                        raise ConnectionError("Jajucha notebook session authentication failed")
                _send(_api_connection, {"type": "api_call", "token": token, "operation": operation, **payload})
                result = _recv(_api_connection)
                break
            except (OSError, ConnectionError, ValueError) as error:
                if _api_connection is not None:
                    try:
                        _api_connection.close()
                    except OSError:
                        pass
                    _api_connection = None
                if attempt:
                    raise ConnectionError("Jajucha simulator connection failed after reconnecting") from error
    if not result.get("ok"):
        raise RuntimeError(result.get("error", "Jajucha API request failed"))
    return result


class _Camera:
    def __init__(self):
        self._last_frame = -1

    def _frame(self, after: int = -1) -> dict:
        result = _rpc("sensor", after_frame=after)
        self._last_frame = int(result["frame"].get("frame_id", self._last_frame))
        return result["frame"]

    def get_image(self, source: str = "center") -> np.ndarray:
        if str(source).lower() == "depth":
            return self.get_depth()
        if str(source).lower() == "lidar":
            return lidar.render()
        frame = self._frame(self._last_frame)
        key = str(source).lower()
        if key not in ("left", "center", "right"):
            raise ValueError("camera source must be left, center, right, depth, or lidar")
        raw = base64.b64decode(frame["images_png_b64"][key + "_rgb"])
        image = cv2.imdecode(np.frombuffer(raw, np.uint8), cv2.IMREAD_COLOR)
        if image is None or image.shape[:2] != (400, 640):
            raise RuntimeError("simulator camera returned an invalid 640 x 400 image")
        return image

    def get_depth(self) -> np.ndarray:
        frame = self._frame()
        raw = base64.b64decode(frame["depth_gray_png_b64"])
        image = cv2.imdecode(np.frombuffer(raw, np.uint8), cv2.IMREAD_COLOR)
        return image if image is not None else np.zeros((400, 640, 3), np.uint8)

    def show_image(self, image, source="center", quality=80) -> None:
        array = np.asarray(image)
        if array.ndim == 2:
            array = cv2.cvtColor(array.astype(np.uint8), cv2.COLOR_GRAY2BGR)
        if array.ndim != 3 or array.shape[2] < 3:
            raise ValueError("show_image expects grayscale or BGR pixels")
        ok, encoded = cv2.imencode(".png", np.ascontiguousarray(np.clip(array[..., :3], 0, 255).astype(np.uint8)))
        if not ok:
            raise RuntimeError("Could not encode image")
        _rpc("display", display={"display_source": str(source).lower(), "display_png_b64": base64.b64encode(encoded).decode("ascii")})


class _Lidar:
    def get_lidar(self):
        frame = camera._frame()
        return np.asarray(frame.get("lidar_angles_deg", []), np.float32), np.asarray(frame.get("lidar_ranges_mm", []), np.float32)

    def render(self, theta_array=None, dist_array=None, max_dist=12000):
        if theta_array is None or dist_array is None:
            theta_array, dist_array = self.get_lidar()
        image = np.zeros((400, 640, 3), np.uint8)
        center, radius = (320, 200), 175
        for angle, distance in zip(theta_array, dist_array):
            if not np.isfinite(distance) or distance < 50 or distance >= 12000 or distance > max_dist:
                continue
            r = min(float(distance) / max(1.0, float(max_dist)), 1.0) * radius
            theta = np.deg2rad(float(angle))
            cv2.circle(image, (round(center[0] + r * np.sin(theta)), round(center[1] - r * np.cos(theta))), 2, (40, 170, 245), -1)
        return image

    def show_lidar(self, theta_array=None, dist_array=None, max_dist=12000):
        camera.show_image(self.render(theta_array, dist_array, max_dist), "lidar")


class _Control:
    def set_motor(self, left, right=None, speed=None):
        if speed is None:
            speed, right = right, left
        _rpc("control", command={"left_servo": float(left), "right_servo": float(right), "motor": float(speed)})


class _SimulationTime:
    def __init__(self):
        self._origin = 0.0

    def _now(self):
        frame = camera._frame()
        return float(frame.get("timestamp_s", 0.0))

    def perf_counter(self):
        return self._now()

    monotonic = perf_counter

    def sleep(self, seconds):
        deadline = self._now() + max(0.0, float(seconds))
        while self._now() < deadline:
            _wall_time.sleep(0.01)


camera = _Camera()
lidar = _Lidar()
control = _Control()
sim_time = _SimulationTime()
time = SimpleNamespace(sleep=sim_time.sleep, perf_counter=sim_time.perf_counter, monotonic=sim_time.monotonic)
