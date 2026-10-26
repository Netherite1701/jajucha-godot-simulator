"""Inspect recorded sensor inputs with the active controller's own functions."""
from pathlib import Path
import argparse
import json
import math
import cv2
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("run", type=Path)
parser.add_argument("--start", type=float, default=0)
parser.add_argument("--end", type=float, default=1e9)
parser.add_argument("--stride", type=int, default=1)
parser.add_argument("--controller", type=Path, default=ROOT / "python_bridge/user_supplied_controller.py")
args = parser.parse_args()
source = args.controller.read_text(encoding="utf-8")
definitions = source.split("# ---------- 5)")[0].replace("import jchm\n", "")
controller = {}
exec(compile(definitions, "user_supplied_controller.py", "exec"), controller)
records = [json.loads(line) for line in (args.run / "frames.jsonl").read_text().splitlines()]
records = [r for r in records if args.start <= r["timestamp_s"] <= args.end][::args.stride]
output = args.run / "replay"
output.mkdir(exist_ok=True)
for frame in records:
    frame_id = frame["frame_id"]
    img = cv2.imread(str(args.run / "frames" / f"{frame_id:06d}_center.png"))
    bev = controller["to_bev"](img)
    edges = controller["lane_edges"](bev)
    result = controller["findpath"](edges)
    state = {"frame": frame_id, "time": frame["timestamp_s"], "edge_pixels": int(np.count_nonzero(edges))}
    if result is not None:
        vs, us, free = result
        xs = controller["BEV_X_MAX"] - vs * controller["BEV_RES"]
        ys = controller["BEV_Y_MAX"] - us * controller["BEV_RES"]
        d = np.hypot(xs, ys)
        target = np.argmin(abs(d - 0.38))
        delta = math.degrees(math.atan(2 * 0.183 * math.sin(math.atan2(ys[target], xs[target])) / 0.38))
        state.update(reach=float(d.max()), target=[float(xs[target]), float(ys[target])], steering_deg=delta)
        bev[vs, us] = (0, 0, 255)
    else:
        state["path"] = None
    print(json.dumps(state))
    cv2.imwrite(str(output / f"{frame_id:06d}.png"), np.hstack([bev, cv2.cvtColor(edges, cv2.COLOR_GRAY2BGR)]))


