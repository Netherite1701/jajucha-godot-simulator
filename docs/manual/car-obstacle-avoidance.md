# Jajucha car manual: Part 4 ch.3 obstacle avoidance (digest)

Source: Korean Jajucha car manual, Part 4 ch.3 "Avoiding obstacles" [3장. 장애물 회피하기], PDF pp. 376-448.
Citations use PDF page numbers (printed page = PDF page - 1). p. 448 is blank; pp. 431-447 are an appendix, not mission content.
All code uses the `jchm` library plus NumPy/OpenCV, in a `while True` loop calling `set_motor(a, b, speed)`.

## 0. Chapter scope and map

| Section | Title | PDF pages |
|---|---|---|
| 1 | Avoiding with depth sensing [깊이 감지(depth)로 회피하기] | 376-390 |
| 1.1 | Set obstacle detection areas with ROI [관심 영역으로 장애물 탐지 영역 설정하기] | 376-382 |
| 1.2 | Avoid obstacles [장애물 회피하기] | 382-390 |
| 2 | Avoiding with LiDAR [라이다(LiDAR)로 회피하기] | 391-416 |
| 2.1 | Avoid a front obstacle [전방 장애물 회피하기] | 391-402 |
| 2.3 (numbered so in the manual; no 2.2 appears) | Escape an obstacle area [장애물 지역 탈출하기] | 403-416 |
| 3 | Avoiding with object detection [객체 인식(object detection)으로 회피하기] | 417-430 |
| 3.1 (first) | Estimate distance to decide when to avoid | 417-423 |
| 3.1 (second, numbering repeated) | Steer by obstacle position | 424-430 |
| Appendix | Function reference [부록. 함수 모음] (Python, NumPy, OpenCV) | 431-447 |

- The chapter covers only three sensing methods: depth image, LiDAR, YOLO object detection (pp. 376, 391, 417).
- No tunnel, parking-lot, traffic-light, or final-project mission appears in these pages; the closest is the "boxed-in" escape scenario, compared to parallel parking (car manual, p. 413).
- No numbered practice tasks or exercises appear; each step is a worked example with outputs to compare (car manual, pp. 376-430).

## 1. Depth-image avoidance (pp. 376-390)

### 1.1 Goals and ROI setup

- Depth image is grayscale; brightness encodes distance (brighter means closer). Only meaningful regions should be used, chosen with an OpenCV region of interest (ROI) [관심 영역] (car manual, p. 376).
- Two avoidance styles are taught: simply steering sideways, and approaching close, reversing, then turning sideways (car manual, p. 376).
- ROI is plain array slicing, `image[y1:y2, x1:x2]` (car manual, p. 376).
- Image from `jchm.camera.get_depth()`; example shape is height 202, width 220, 3 channels (car manual, p. 378).
- Step 1, left/right areas: width split into thirds (`tri_x = width // 3`, which is 73) giving left, center, right ROIs (car manual, pp. 377-378).
- Step 2, up/down areas: a small obstacle leaves many black (far) pixels, so the brightness mean barely changes as it approaches; therefore only the vertical middle third is used (`tri_y = height // 3`, which is 67) (car manual, p. 379).
- Final ROIs: `roi_A` left, `roi_B` center, `roi_C` right, all rows `tri_y : tri_y*2` (car manual, p. 379).
- Step 3, readability: draw `cv2.rectangle` borders (left red, center yellow, right blue; BGR tuples, thickness 2) and join with `np.concatenate(..., axis=1)` to show one "depth" window via `jchm.camera.show_image` (car manual, p. 381).
- Note: in the manual's loop, the means are taken after the rectangles are drawn on the copies, so border pixels are included in the mean (car manual, p. 386).

### 1.2 Brightness-mean avoidance

- Principle: turning radius is limited, so avoidance must start while there is still room; decide a brightness-mean threshold per ROI (car manual, p. 382).
- Metric: `np.mean(roi)` per area, printed as left/center/right brightness (car manual, p. 384).
- Sample means, obstacle ahead: left 34.1, center 89.4, right 43.6; farther obstacle: 27.2 / 48.8 / 33.8 (car manual, p. 384).
- Sample means, obstacle moved left/right: 65.2 / 55.0 / 46.0 and 32.0 / 50.4 / 63.2 (car manual, pp. 384-385).
- Reader is told to repeat this to find the best trigger per area (car manual, p. 385).
- Lighting changes shift when avoidance triggers (car manual, p. 387).

#### Sideways-steer avoidance (pp. 385-388)

- Advice: start slow, then tune speed and trigger point; too much speed risks collision even with spare distance (car manual, p. 385).

| Condition | Call | Meaning |
|---|---|---|
| left mean > 30 | `set_motor(10, 10, 3)` | steer +10 (right turn), speed 3 (car manual, p. 387) |
| elif right mean > 30 | `set_motor(-10, -10, 3)` | steer -10 (left turn), speed 3 (car manual, p. 387) |
| else | `set_motor(0, 0, 3)` | straight, speed 3 (car manual, p. 387) |

- The center ROI is computed but not used for this decision (car manual, p. 387).
- Sample logs: left 55.0 triggers right turn; right 46.2 triggers left turn (car manual, pp. 387-388).

#### Reverse-then-steer avoidance (pp. 388-390)

- Motivation: in narrow alleys with limited turning radius, a plain sideways turn may hit surroundings (car manual, p. 388).
- Three design decisions: (1) trigger on the center mean, closer to the obstacle than before; (2) reverse for a fixed time using `time.sleep()` (distance depends on speed, so time and speed must be tuned); (3) choose a tight steering angle to hug the obstacle (car manual, p. 388).

| Condition | Action |
|---|---|
| center mean > 70 | `set_motor(0, 0, -3)`, `time.sleep(1)` (reverse 1 s), then `set_motor(10, 10, 3)`, `time.sleep(1)` (steer right 1 s) (car manual, p. 390) |
| else | `set_motor(0, 0, 3)` (car manual, p. 390) |

- This version always turns right; it does not choose a side by obstacle position (car manual, p. 390).

## 2. LiDAR avoidance (pp. 391-416)

### 2.0 Data model and conventions

- `theta_array, dist_array = jchm.lidar.get_lidar()` returns two 1-D NumPy arrays: angles (degrees) and distances (car manual, pp. 391, 393).
- One revolution yields roughly 300 to 450 points (car manual, p. 391).
- Samples are not spaced exactly 1 degree apart (more than 360 pulses), so "60 degrees" cannot be assumed to equal 60 values; check how many samples really fall in the sector (car manual, p. 392).
- Arrays are ordered by angle starting near 0, so the front sector straddles both ends; slice head and tail separately, then join with `np.concatenate` (car manual, pp. 391-392).
- Observed angle samples run from about 0.36 up to 359.64 (car manual, p. 394).
- Distances are in millimetres: the manual comments 500 as 50 cm, 1,000 as 1 m, 300 as 30 cm (car manual, pp. 396, 401, 415).
- Large far values appear in raw output (for example 3341, 5787) beside near readings around 285-290 (car manual, p. 406).
- Angle direction (inferred from the manual's examples): 0 is straight ahead; an obstacle on the left reads about 340-350 degrees, on the right about 9 degrees, so angle grows clockwise as seen from above (car manual, pp. 399-400).
- Rear is about 180 degrees (rear sector 140-220) (car manual, p. 405).
- Visual debug: `jchm.lidar.show_lidar(theta_array, dist_array, 1000)` draws the scan with max display range 1,000 (1 m) (car manual, p. 396).
- Hardware caveat: the LiDAR cannot detect the small sponge obstacle; use the large sponge in LiDAR missions (car manual, p. 395).

### 2.1 Front obstacle avoidance (pp. 391-402)

Goal: use only meaningful data (direction and distance of the nearest obstacle) (car manual, p. 391).

- Step 1, front sector by slicing: about +/-30 degrees (about 60) is approximated with the first 35 and last 35 samples (about 70 values) (car manual, pp. 391-393).
- Slicing code pattern: `np.concatenate((theta_array[:35], theta_array[-35:]))`, same for `dist_array` (car manual, p. 392).
- Result: angles from about 0.45 to 25.9 plus about 334.8 to 359.7, matching roughly +/-30 degrees (car manual, p. 394).
- Step 2, nearest distance: `front_mindist = np.min(front_dist)`; sample output 264.0 (car manual, pp. 394-396).
- Step 3, direction: `np.argmin(front_dist)` gives the index, used to read the angle of the nearest point (car manual, pp. 396-398).

| Nearest-point angle | Rule | Evidence |
|---|---|---|
| 0 to 30 degrees (right side) | turn left | sample: 262 mm at 9.34 degrees gives left turn (car manual, pp. 398, 400) |
| otherwise (left side, 330-360) | turn right | sample: 275 mm at 349.79 degrees gives right turn (car manual, pp. 398-399) |

- The comment says an exact 0 degree reading maps to right turn, but the code condition `0 <= theta <= 30` sends 0 to left turn (car manual, p. 398).
- Step 4, drive logic (nested conditions): (car manual, p. 401)

| Condition | Call | Meaning |
|---|---|---|
| min distance <= 500 and angle in 0-30 | `set_motor(-10, -10, 2)` | steer left, speed 2 (car manual, p. 401) |
| min distance <= 500 and angle otherwise | `set_motor(10, 10, 2)` | steer right, speed 2 (car manual, p. 401) |
| min distance > 500 | `set_motor(0, 0, 2)` | straight, speed 2 (car manual, p. 401) |

- Threshold 500 equals 50 cm; sample logs show minimums of 274-356 triggering steering (car manual, pp. 401-402).

### 2.3 Escape an obstacle area (pp. 403-416)

Scenario and setup:
- Alley or parked-in situation; place large sponge obstacles about 10 cm in front of and behind the car (car manual, p. 403).
- Slicing is too imprecise because the number of returned points varies per revolution, so sectors are chosen by angle condition with `np.where` (car manual, p. 403).

Sector selection:
- Logical operators: `~` NOT, `|` OR, `&` AND (the pipe may display as a backtick in some environments) (car manual, p. 404).
- `np.where(cond)` returns a tuple of index arrays; 1-D data means taking `[0]` (car manual, p. 404).
- Front sector (about 80 degrees): `np.where((theta >= 320) | (theta <= 40))[0]` (car manual, p. 405).
- Rear sector (about 80 degrees): `np.where((theta >= 140) & (theta <= 220))[0]` (car manual, p. 405).
- Sample front output covers 320-360 and 0-40 degrees; rear covers about 140-220 degrees (car manual, p. 406).

Polar to Cartesian [극좌표계 / 직교 좌표계]:
- Polar (radius, angle) does not account for vehicle width or turning radius; the LiDAR sits at the car center, so equal distances can mean different collision risk (car manual, p. 407).
- In Cartesian form, only the y value needs to be checked, giving a consistent forward/backward distance (car manual, pp. 407-408).
- Manual's formulas: x = r sin(theta), y = r cos(theta), with `np.radians()` first (the manual text writes cos for x and sin for y in prose, but its code uses sin for x and cos for y) (car manual, pp. 407, 409).
- Code form: `front_y = front_dist * np.cos(np.radians(front_theta))`; `np.column_stack` builds (x, y) pairs for display (car manual, p. 409).
- Front y values are positive (about 220 in the sample), rear y values negative (car manual, pp. 409-410).

Averaging nearest values:
- Using only the single minimum y makes the car stop after very short moves even when more space exists (car manual, p. 410).
- Better: average a few of the closest y values. Face-on obstacle means close approach and larger travel; off-center obstacle means collision avoided (car manual, pp. 410-411).
- Parameters: mean of the 5 smallest front y (`np.sort(front_y)[:5]`) and the 5 most negative rear y (`np.sort(rear_y)[-5:]`) (car manual, p. 413).
- Sample: obstacle close gives front 168.9, rear -161.2; obstacle far gives front 308.8, rear -316.4 (car manual, p. 413).
- Reader is invited to tune their own criterion (car manual, p. 410).

Escape algorithm (pp. 413-416):
- Idea: like pulling a parallel-parked car out; alternate forward and reverse with opposite steering to open space (car manual, pp. 413-414).
- Rule 1: both ends blocked, so repeat forward and backward moves with opposite steering (reverse steers right, forward steers left) (car manual, p. 414).
- Rule 2: if one side is judged clear, move that way to escape; set the reference distances sensibly (car manual, p. 414).
- Parameters: blocked threshold 300 (30 cm); steer magnitude 5; speed magnitude 2; absolute values of the averaged y are compared (car manual, p. 415).

| Condition (front_mean, rear_mean = abs of averaged y) | Call | Meaning |
|---|---|---|
| both < 300 and front_mean > rear_mean | `set_motor(-5, -5, 2)` | forward, steer left (more room in front) (car manual, p. 415) |
| both < 300 and front_mean <= rear_mean | `set_motor(5, 5, -2)` | reverse, steer right (car manual, p. 415) |
| only front < 300 | `set_motor(5, 5, -2)` | reverse, steer right (car manual, p. 415) |
| only rear < 300 | `set_motor(-5, -5, 2)` | forward, steer left (car manual, p. 415) |

- The "escape when a side is free" outcome is only described in a caption; the shown code has no branch that drives out when both distances are at least 300 (car manual, pp. 415-416).
- The loop also calls `show_lidar(..., 1000)` each iteration (car manual, p. 413).

## 3. Object-detection (YOLO) avoidance (pp. 417-430)

### 3.0 Concepts

- A mono camera cannot use stereo disparity, so distance is estimated from the YOLO bounding box position (car manual, p. 417).
- Practice obstacles are cubic sponges: 10 cm small and 15 cm large, in several colors (blue, pink, others); the mission here uses a single class regardless of size or color (car manual, pp. 416-418).
- Rationale for restricting obstacle types: more classes need a more powerful computer than the car's (car manual, p. 416).
- Untrained objects cannot be detected; train the sponge as one class using the YOLO method from Part 3 ch.4 (car manual, p. 418).

### 3.1 Distance from bounding-box y

- Box is (x1, y1, x2, y2): top-left and bottom-right corners, plus class (integer) and confidence (car manual, p. 419).
- Detection code pattern: `jchm.load_ai()`, `image = jchm.camera.get_image()`, `jchm.ai.get_model_output(image, model_name)`, loop over `result.boxes` reading `box.xyxy[0]`, `box.conf[0]`, `box.cls[0]`. `model_name` is the user's own trained model (example 'MyModel') (car manual, pp. 419-420).
- Sample box: x1 242, y1 191, x2 368, y2 321 (car manual, p. 421).
- Perspective projection [원근 투영] / pinhole camera model: closer objects have a smaller gap between the object's bottom edge and the image bottom (car manual, pp. 420-422).
- Rule: as the box bottom y2 rises toward the image bottom, the obstacle is closer. OpenCV y runs top to bottom, so larger y2 means closer (car manual, p. 423).
- Samples: far obstacle gives y2 = 296 (also 330 and 271 in the figure), near obstacle gives y2 = 375 (car manual, p. 423).

### 3.2 Steering by horizontal position

- A fixed single-direction dodge fails when the obstacle is on that side, so direction must depend on obstacle position (car manual, p. 424).
- Obstacle center x = (x1 + x2) // 2 (example: 242 and 368 give 305) (car manual, pp. 424-425).
- YOLO image width is 640 px; center is about 319-320 (car manual, p. 424).
- Sample centers: middle 313, right 504, left 109 (car manual, pp. 426-427).
- Style: nested conditions (distance first, then direction) (car manual, p. 427).

| Condition | Call | Meaning |
|---|---|---|
| y2 >= 320 and center <= 320 (obstacle left) | `set_motor(10, 10, 3)` | steer right, speed 3 (car manual, p. 428) |
| y2 >= 320 and center > 320 (obstacle right) | `set_motor(-10, -10, 3)` | steer left, speed 3 (car manual, p. 428) |
| y2 < 320 | `set_motor(0, 0, 3)` | straight, speed 3 (car manual, p. 428) |

- Trigger threshold y2 = 320 (car manual, p. 428).
- Sample logs: left-side obstacle (center about 253-264) with y2 from 318 upward; right-side (center 363-472) with y2 from 319 to 366 (car manual, pp. 429-430).
- Output captions on pp. 429-430 are internally inconsistent with the code (see uncertain facts below) (car manual, pp. 429-430).
- Loop quirks: `obstacle_center` and `y2` come from the last box found; with no detection, stale or undefined values may be used (car manual, p. 428).

## 4. Parameter summary

| Method | Sector or ROI | Trigger | Steer | Speed |
|---|---|---|---|---|
| Depth, sideways | left/right middle-third ROI means | mean > 30 | +/-10 | 3 (car manual, p. 387) |
| Depth, reverse-then-turn | center ROI mean | mean > 70 | reverse 0 steer 1 s, then +10 for 1 s | -3, then 3 (car manual, p. 390) |
| LiDAR front | about +/-30 degrees (35+35 samples) | min distance <= 500 | +/-10 | 2 (car manual, p. 401) |
| LiDAR escape | front 320-40, rear 140-220 degrees | mean of 5 nearest y < 300 | +/-5 | +/-2 (car manual, p. 415) |
| YOLO | box bottom y2 and center x | y2 >= 320; split at x = 320 | +/-10 | 3 (car manual, p. 428) |

- Common `set_motor` pattern in this chapter: first two arguments equal and used as steering (positive is right, negative is left), third is speed (negative is reverse). The pages read do not define the arguments explicitly (car manual, pp. 387, 390, 401, 415, 428).

## 5. Appendix (pp. 431-447)

- Quick-reference of Python built-ins, NumPy and OpenCV functions with parameters; none of it is mission logic (car manual, pp. 432-447).
- NumPy entries relevant here include `np.where`, `np.radians`, `np.concatenate`, `np.mean` (car manual, pp. 437, 439, 443).
- OpenCV entries include `cv2.rectangle` and `cv2.putText` (car manual, p. 447).
- Page 448 is blank (car manual, p. 448).

## 6. Uncertain or inconsistent points

- Angle direction is inferred from the sample outputs rather than stated outright (car manual, pp. 399-400).
- Meaning of the first two `set_motor` arguments (front/rear steering) is not defined in these pages (car manual, p. 387).
- Prose after the YOLO samples on p. 429 says "right" for center >= 320 although the code turns left there; p. 430 says "right" for center < 320, which matches the code only for that case (car manual, pp. 428-430).
- Section numbering: LiDAR escape is labeled 2.3 with no 2.2, and two sections are labeled 3.1 (car manual, pp. 403, 417, 424).
- The YOLO side-steer section is headed "using LiDAR" in its example title though the code uses YOLO (car manual, p. 427).
