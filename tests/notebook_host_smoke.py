"""Exercise the separate IPython kernel and authenticated Jajucha RPC bridge."""
from __future__ import annotations

import base64
import json
import os
import re
import socket
import struct
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

import cv2
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
HOST = Path(os.environ.get("JAJUCHA_NOTEBOOK_HOST", ROOT / "python_bridge" / "notebook_host.py"))


def send_message(sock: socket.socket, value: dict) -> None:
    data = json.dumps(value).encode("utf-8")
    sock.sendall(struct.pack("!I", len(data)) + data)


def read_exact(sock: socket.socket, count: int) -> bytes:
    parts = bytearray()
    while len(parts) < count:
        part = sock.recv(count - len(parts))
        if not part:
            raise ConnectionError("kernel host closed")
        parts.extend(part)
    return bytes(parts)


def read_message(sock: socket.socket) -> dict:
    size = struct.unpack("!I", read_exact(sock, 4))[0]
    return json.loads(read_exact(sock, size))


class NotebookHostSmoke(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_root = tempfile.TemporaryDirectory(prefix="jajucha-kernel-")
        self.port_file = Path(self.temp_root.name) / "kernel-port.json"
        self.port = 0
        self.token = "smoke-token-not-a-production-secret"
        self.process = subprocess.Popen(
            [sys.executable, str(HOST), "--port", "0", "--port-file", str(self.port_file), "--token", self.token],
            cwd=ROOT,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
        )
        deadline = time.monotonic() + 35
        while True:
            if self.port_file.exists():
                self.port = int(json.loads(self.port_file.read_text(encoding="utf-8"))["port"])
                try:
                    self.sock = socket.create_connection(("127.0.0.1", self.port), timeout=1)
                    break
                except OSError:
                    pass
            if self.process.poll() is not None:
                stderr = self.process.stderr.read().decode("utf-8", "replace")
                self.fail(f"notebook host exited early: {stderr}")
            if time.monotonic() >= deadline:
                self.fail("notebook host did not start within 35 seconds")
            time.sleep(0.1)
        self.sock.settimeout(12)
        send_message(self.sock, {"type": "hello", "role": "godot", "token": self.token})
        self.assertEqual(read_message(self.sock)["type"], "ready")
        ok, encoded = cv2.imencode(".png", np.full((400, 640, 3), (20, 90, 160), np.uint8))
        self.assertTrue(ok)
        image = base64.b64encode(encoded).decode("ascii")
        self.frame_id = 1
        self.sim_time_s = 12.5
        self.sensor_payload = {
            "type": "sensor_frame", "frame_id": self.frame_id, "timestamp_s": self.sim_time_s,
            "images_png_b64": {name + "_rgb": image for name in ("left", "center", "right")},
            "depth_gray_png_b64": image, "depth_valid_png_b64": image,
            "lidar_angles_deg": list(np.linspace(-180, 180, 409)),
            "lidar_ranges_mm": [1000] * 409,
        } | {"token": self.token}
        send_message(self.sock, self.sensor_payload)

    def tearDown(self) -> None:
        try:
            send_message(self.sock, {"type": "shutdown", "token": self.token})
            self.sock.close()
        except OSError:
            pass
        try:
            self.process.wait(timeout=8)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait(timeout=3)
        if self.process.stderr is not None:
            self.process.stderr.close()
        self.temp_root.cleanup()

    def execute(self, request_id: int, cell_id: int, code: str, *, input_value: str | None = None, interrupt: bool = False, advance_simulation: bool = False) -> list[dict]:
        send_message(self.sock, {"type": "execute", "token": self.token, "request_id": request_id, "cell_id": cell_id, "code": code})
        messages: list[dict] = []
        interrupted = False
        started = time.monotonic()
        self.sock.settimeout(0.05 if advance_simulation else 0.5 if interrupt else 12)
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            if advance_simulation:
                self.frame_id += 1
                self.sim_time_s += 0.05
                frame = dict(self.sensor_payload)
                frame.update(frame_id=self.frame_id, timestamp_s=self.sim_time_s)
                send_message(self.sock, frame)
            try:
                message = read_message(self.sock)
            except TimeoutError:
                if interrupt and not interrupted:
                    send_message(self.sock, {"type": "interrupt", "token": self.token, "request_id": request_id, "cell_id": cell_id})
                    interrupted = True
                continue
            messages.append(message)
            if message.get("type") == "input_request":
                send_message(self.sock, {"type": "input_reply", "token": self.token, "request_id": request_id, "value": input_value or ""})
            if interrupt and not interrupted and time.monotonic() - started > 0.5:
                send_message(self.sock, {"type": "interrupt", "token": self.token, "request_id": request_id, "cell_id": cell_id})
                interrupted = True
            if message.get("type") in ("execution_done", "kernel_killed"):
                self.sock.settimeout(12)
                return messages
        self.sock.settimeout(12)
        self.fail(f"cell {cell_id} did not finish; messages={messages[-4:]}")
        return messages

    def test_persistent_state_and_jchm_sensor_api(self) -> None:
        first = self.execute(1, 1, "value = 40 + 2\nprint(value)")
        self.assertTrue(any("42" in item.get("text", "") for item in first))
        second = self.execute(2, 2, "print(value + 1)")
        self.assertTrue(any("43" in item.get("text", "") for item in second))
        sensors = self.execute(3, 3, "from jchm import camera, lidar\nframe = camera.get_image()\nangles, ranges = lidar.get_lidar()\nprint(frame.shape, len(angles), int(ranges[0]))")
        self.assertTrue(any("(400, 640, 3) 409 1000" in item.get("text", "") for item in sensors), sensors)

    def test_input_output_and_control(self) -> None:
        messages = self.execute(4, 4, "answer = input('Name? ')\nprint('안녕하세요', answer)", input_value="Jajucha")
        self.assertTrue(any(item.get("type") == "input_request" for item in messages))
        self.assertTrue(any("안녕하세요 Jajucha" in item.get("text", "") for item in messages))
        control = self.execute(5, 5, "from jchm import control\ncontrol.set_motor(-2, 2, 10)")
        self.assertTrue(any(item.get("type") == "notebook_control" and item.get("motor") == 10 for item in control), control)

    def test_persistent_api_connection_handles_many_control_calls(self) -> None:
        count = 500
        messages = self.execute(
            12,
            12,
            "from jchm import control\n"
            f"for index in range({count}):\n"
            "    control.set_motor(0, 0, index % 20)\n"
            f"print('RPC_SOAK_DONE', {count})",
        )
        controls = [item for item in messages if item.get("type") == "notebook_control"]
        self.assertEqual(len(controls), count)
        self.assertTrue(any("RPC_SOAK_DONE 500" in item.get("text", "") for item in messages), messages[-4:])

    def test_simulation_time_import_and_restart(self) -> None:
        code = (
            "import time, sys\n"
            "sim_start = time.perf_counter()\n"
            "wall_start = sys.modules['time'].perf_counter()\n"
            "time.sleep(0.15)\n"
            "print('SIM_CLOCK', round(sim_start, 1), round(time.perf_counter() - sim_start, 1), sys.modules['time'].perf_counter() > wall_start)"
        )
        messages = self.execute(9, 9, code, advance_simulation=True)
        output = "".join(item.get("text", "") for item in messages)
        clock_match = re.search(r"SIM_CLOCK ([0-9.]+) ([0-9.]+) True", output)
        self.assertIsNotNone(clock_match, output)
        self.assertGreaterEqual(float(clock_match.group(1)), 12.5)
        self.assertLess(float(clock_match.group(1)), 13.0)
        self.assertGreaterEqual(float(clock_match.group(2)), 0.15)

        send_message(self.sock, {"type": "restart", "token": self.token, "request_id": 10})
        restarted = read_message(self.sock)
        self.assertEqual(restarted.get("type"), "restarted", restarted)
        clean = self.execute(11, 11, "import time\nprint('RESTART_CLOCK', round(time.perf_counter(), 1))")
        restart_output = "".join(item.get("text", "") for item in clean)
        restart_match = re.search(r"RESTART_CLOCK ([0-9.]+)", restart_output)
        self.assertIsNotNone(restart_match, restart_output)
        self.assertGreaterEqual(float(restart_match.group(1)), 12.5)
        self.assertLess(float(restart_match.group(1)), 13.0)

    def test_image_exception_and_interrupt(self) -> None:
        _, encoded = cv2.imencode(".png", np.zeros((8, 8, 3), np.uint8))
        image_b64 = base64.b64encode(encoded).decode("ascii")
        shown = self.execute(6, 6, "from IPython.display import Image, display\nimport base64\ndisplay(Image(data=base64.b64decode('" + image_b64 + "'), format='png'))")
        self.assertTrue(any(item.get("type") == "cell_image" and item.get("mime") == "image/png" for item in shown))
        failed = self.execute(7, 7, "raise RuntimeError('expected smoke exception')")
        result = next(item for item in failed if item.get("type") == "execution_done")
        self.assertFalse(result["success"])
        loop = self.execute(8, 8, "while True: pass", interrupt=True)
        self.assertTrue(any(item.get("type") == "execution_done" and not item.get("success") for item in loop))
        self.assertTrue(any(item.get("type") == "safe_stop" for item in loop))


if __name__ == "__main__":
    unittest.main(verbosity=2)
