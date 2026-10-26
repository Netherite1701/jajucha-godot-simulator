"""Render recorded lap evidence and check the trajectory against panel artwork."""
from pathlib import Path
import argparse
import bisect
import json
import math
import re
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("run", type=Path)
args = parser.parse_args()
run = args.run.resolve()
states = [json.loads(line) for line in (run / "trajectory.jsonl").read_text().splitlines()]
frames_file = run / "frames.jsonl"
frames = [json.loads(line) for line in frames_file.read_text().splitlines()] if frames_file.exists() else []
result = json.loads((run / "result.json").read_text())
overview = Image.open(run / "overview.png").convert("RGB")
width, height = overview.size

def pixel(x, z):
    return ((x - 0.45) * width / 11.5 + width / 2,
            (z - 0.45) * width / 11.5 + height / 2)

trace = overview.copy()
draw = ImageDraw.Draw(trace)
points = [pixel(state["x_m"], state["z_m"]) for state in states]
draw.line(points, fill="#63dfdb", width=4)
for point, color, label in [(points[0], "#72f0a5", "START"), (points[-1], "#ffcf79", "FINISH")]:
    x, y = point
    draw.ellipse((x - 7, y - 7, x + 7, y + 7), fill=color, outline="#12242b", width=2)
    draw.text((x + 10, y - 16), label, fill=color, stroke_width=2, stroke_fill="#12242b")
draw.rectangle((20, 16, width - 20, 56), fill="#14212b")
draw.text((36, 30), f"{result['result']}   |   {result.get('elapsed_s', 0):.1f} s   |   {result.get('distance_m', 0):.2f} m   |   {len(result['gates'])}/7 ordered checkpoints", fill="#d9eceb")
trace.save(run / "trajectory.png")

# This is an independent check, never an input to the driving controller.
course_source = (ROOT / "scripts/course_data.gd").read_text(encoding="utf-8")
rows = re.findall(r'"([A-Z.]{11})"', course_source)[:6]
rotations = re.findall(r'"([0-3]{11})"', course_source)[:6]
textures = {letter: Image.open(ROOT / "assets/panels" / f"{letter}.png").convert("RGB") for letter in set(''.join(rows)) - {'.'}}

def on_road(x, z):
    col, row = math.floor((x + 4.5) / 0.9), math.floor((z + 2.25) / 0.9)
    if not (0 <= col < 11 and 0 <= row < 6) or rows[row][col] == '.':
        return False
    dx, dz = x - (-4.5 + (col + 0.5) * 0.9), z - (-2.25 + (row + 0.5) * 0.9)
    angle = int(rotations[row][col]) * math.pi / 2
    local_x = math.cos(angle) * dx - math.sin(angle) * dz
    local_z = math.sin(angle) * dx + math.cos(angle) * dz
    texture = textures[rows[row][col]]
    u = min(texture.width - 1, max(0, round((local_x / 0.9 + 0.5) * (texture.width - 1))))
    v = min(texture.height - 1, max(0, round((local_z / 0.9 + 0.5) * (texture.height - 1))))
    r, g, b = texture.getpixel((u, v))
    grass = g > r * 1.15 + 6 and g > b * 1.15 + 6
    curb_red = r > g * 1.5 + 30 and r > b * 1.5 + 30
    return not (grass or curb_red)

center_bad, footprint_bad = [], []
for state in states:
    x, z, yaw = state["x_m"], state["z_m"], math.radians(state["yaw_deg"])
    if not on_road(x, z):
        center_bad.append(state["elapsed_s"])
    samples = []
    for forward in (-0.06331, 0.0, 0.18869):
        for lateral in (-0.0888, 0.0, 0.0888):
            samples.append(on_road(x - math.sin(yaw) * forward + math.cos(yaw) * lateral,
                                   z - math.cos(yaw) * forward - math.sin(yaw) * lateral))
    if not all(samples):
        footprint_bad.append(state["elapsed_s"])
coverage = {
    "samples": len(states), "center_off_road_samples": len(center_bad),
    "footprint_touching_grass_or_red_curb_samples": len(footprint_bad),
    "center_off_road_times_s": center_bad,
    "footprint_touch_times_s": footprint_bad,
    "method": "Recorded ground-truth trajectory sampled against the actual 900 mm panel artwork and rotations; used for verification only.",
}
(run / "road_coverage.json").write_text(json.dumps(coverage, indent=2), encoding="utf-8")

# A compact sensor replay shows the complete attempt at roughly 8x speed.
state_times = [state["sim_time_s"] for state in states]
animation = []
next_time = -1.0
for frame in frames:
    timestamp = frame["timestamp_s"]
    if timestamp < next_time:
        continue
    next_time = timestamp + 0.8
    camera = Image.open(run / "frames" / f"{frame['frame_id']:06d}_center.png").convert("RGB")
    state = states[min(len(states) - 1, bisect.bisect_left(state_times, timestamp))]
    overlay = ImageDraw.Draw(camera)
    overlay.rectangle((0, 0, 640, 34), fill="#14212b")
    overlay.text((12, 11), f"{state['elapsed_s']:.1f}s   |   {state['distance_m']:.1f}m   |   checkpoints {state['gates_passed']}/7   |   {state['speed_mps']:.2f}m/s", fill="#d9eceb")
    animation.append(camera.quantize(colors=128))
if animation and (run / "finish_center.png").exists():
    final_frame = Image.open(run / "finish_center.png").convert("RGB")
    final_overlay = ImageDraw.Draw(final_frame)
    final_overlay.rectangle((0, 0, 640, 40), fill="#14212b")
    final_overlay.text((12, 12), f"{result['result']}  |  {result.get('elapsed_s', 0):.1f}s  |  {result.get('distance_m', 0):.2f}m  |  {len(result['gates'])}/7 checkpoints", fill="#86e6c2")
    animation.append(final_frame.quantize(colors=128))
    animation[0].save(run / "lap_replay.gif", save_all=True, append_images=animation[1:], duration=[100] * (len(animation) - 1) + [1500], loop=0, optimize=False)
print(json.dumps({"result": result["result"], "coverage": coverage, "camera_frames": len(frames), "replay_frames": len(animation), "output": str(run)}, ensure_ascii=False))
