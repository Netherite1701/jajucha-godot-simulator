# Jajucha car manual: digest (user guide + jchm control API)

Source: Korean "자주차 매뉴얼" PDF, 448 pages. All citations are PDF page numbers (the printed page number is PDF page minus 1). Only pages 4-54 and 279-301 were read for this digest. Image-only cover pages (4, 5, 8, 26, 38, 278, 280) are skipped.

Other digests: lane detection is in `car-lane-detection.md`, obstacle avoidance in `car-obstacle-avoidance.md`.

## Contents of the whole manual

| Part / chapter | PDF page | Note |
|---|---|---|
| Part 1 user guide [사용 설명서]: ch.1 starting the car, ch.2 software | 4 (ch.1 p. 5, ch.2 p. 26) | digested below (car manual, pp. 4-54) |
| Part 2 coding basics [코딩 기초]: Python [파이썬] | 56 | not digested (car manual, p. 56 per index) |
| Part 2: NumPy [넘파이] | 118 | not digested (index) (car manual, p. 118) |
| Part 2: OpenCV [오픈CV] | 166 | not digested (index) (car manual, p. 166) |
| Part 3 deep learning [딥 러닝]: AI theory + PyTorch MNIST | 228 | not digested (index) (car manual, p. 228) |
| Part 3: ResNet image classification, YOLO object detection / instance segmentation | 250 | not digested (index) (car manual, p. 250) |
| Part 4 ch.1 controlling the car [자주차 제어하기] | 280 | digested below (car manual, p. 280) |
| Part 4 ch.2 lane detection [차선 인식] | 302 | see `car-lane-detection.md` (car manual, p. 302) |
| Part 4 ch.3 obstacle avoidance [장애물 회피] | 376 | see `car-obstacle-avoidance.md` (car manual, p. 376) |

Page numbers for Parts 2-3 and the Part 4 chapter starts come from the task brief and from the cover-page list in `index.json` (cover pages at 56, 118, 166, 228, 250, 280, 302, 376 are image-only).

The software's own learning menu groups content the same way: coding foundations (Python, NumPy, OpenCV) and deep learning (AI theory then PyTorch MNIST; ResNet classification; YOLO detection and instance segmentation) (car manual, pp. 28-29).

---

# PART 1: User guide (pp. 4-54)

## 1. Chapter 1: Starting the car (pp. 5-16)

### 1.1 Box contents [구성품] (pp. 6-8)

| Item | Qty | Citation |
|---|---|---|
| Car body [자주차 본품] | 1 | (car manual, p. 6) |
| Left battery [좌측 배터리] and right battery [우측 배터리] | 1 each | (car manual, p. 6) |
| Battery charging cradle [배터리 충전 크래들] | 1 | (car manual, p. 6) |
| Battery charging adapter [배터리 충전 어댑터], DC 12 V | 1 | (car manual, pp. 6-7) |
| Wireless LAN card [무선 랜 카드] (USB Wi-Fi dongle, for connecting a PC) | 1 | (car manual, pp. 6, 8) |
| Carrying case [케이스] | 1 | (car manual, pp. 6, 8) |

### 1.2 Attaching batteries (pp. 9-10)

- The batteries are not interchangeable: with the car upside down, the groove under the rear tells which battery goes on which side by mating with the battery's protrusion (car manual, p. 9).
- Fit protrusion-first at the inside of the rear wheel and press until seated. The front wheels must be straight, and the battery should stay level so the connector pins do not bend (car manual, p. 10).

### 1.3 Power on / off (pp. 10-12)

- Check charge with one short press of the battery button; one lit LED or fewer means recharge (car manual, p. 10).
- Starting: a quick double press (short, then a long hold until the LED bar is full). Both batteries must be on; switching one on before fitting is fine (car manual, p. 11).
- When power arrives, the top indicator LED [전원 표시등] lights and the front wheels align themselves (car manual, p. 11).
- Boot takes about 1 minute. It is done when the front wheels twitch once (the text says left, the figure caption says right) and the fan is audible. Unsure which direction; see notes at the end (car manual, p. 12).
- Shutdown: save work, then repeat the double press, holding the second press until the LED bar is out. One battery off is enough; afterwards the indicator is dark and the fan is silent (car manual, p. 12).

### 1.4 Charging (p. 13)

- Push the adapter plug all the way into the cradle's input port (a partial insertion will not charge), then seat the battery with the cradle pins lined up to its port (car manual, p. 13).
- Progress shows as lit battery LEDs; a full charge takes about 1 hour (car manual, p. 13).

### 1.5 Safety warnings (pp. 14-16)

| Warning | Why | Citation |
|---|---|---|
| Never touch the hot drive motor [주행 모터] or the area around the fan | burn risk; the motor heats up as soon as the car is powered (it is armed and ready), and the onboard high-performance computer exhausts hot air around the LiDAR | (car manual, p. 14) |
| Do not force the motors by hand | turning the front wheels by hand can misalign them or break the steering DC servo motor [DC 서보 모터] | (car manual, p. 14) |
| Do not push/pull the car back and forth without computer control | can damage the BLDC drive motor [BLDC 모터] | (car manual, p. 14) |
| Do not slam down or throw the car; avoid falls from height | can damage the suspension [서스펜션] | (car manual, p. 15) |
| Do not twist or pull the Wi-Fi antenna | wire can break | (car manual, p. 15) |
| Align battery port with the car's and cradle's pins before inserting | pins can bend | (car manual, p. 16) |

## 2. Chapter 2: Software (pp. 17-54)

### 2.1 Installing (pp. 17-18)

- The Jajucha software [자주차 소프트웨어] runs on Windows only; Mac and Linux are not supported (car manual, p. 17).
- Installer file name: `jajucha Setup 1.0.0.exe`; double-click it and press OK on the install screen (car manual, p. 17).

### 2.2 Connecting the car to the PC over Wi-Fi (pp. 18-25)

- The car has a built-in Wi-Fi router [무선 공유기]; the PC joins its network (car manual, p. 19).
- Only the supplied TP-Link USB wireless LAN card works (it is the only card the design accepts); the PC's built-in Wi-Fi cannot be used (car manual, p. 19).
- First launch shows an "unconnected" home screen; a "Wi-Fi connection guide" link at upper right shows the steps in-app (car manual, p. 18).
- Network name: serial number of the form `jajucha_XXXXX`, printed on the underside of the car; initial password `jajucha123` (car manual, pp. 21, 24).
- If Windows lists both "Wi-Fi" and "Wi-Fi 2", first find which one the TP-Link card is assigned to (Windows 10: network and internet settings > hardware and connection properties; Windows 11: additional Wi-Fi settings > hardware properties), then pick that adapter before choosing the car's network (car manual, pp. 19-24).
- Connected state: the home screen with the menu appears (car manual, p. 25).

### 2.3 Top bar status (p. 25)

- The top bar shows the connected car's battery, free storage and serial number; its buttons hide the screen, toggle window/fullscreen and close the software (car manual, p. 25).
- Battery advice: swap at 20% or lower, since a forced shutdown on a flat battery can lose unsaved files (car manual, p. 25).
- On first run, required system files already take about 30% of storage (car manual, p. 25).

### 2.4 Menu structure (pp. 27-32)

- Home screen has three entries: Learning [학습], Project [프로젝트], File storage [파일 보관함] (car manual, p. 27).
- Learning: coding foundation (Python, NumPy, OpenCV) and deep learning (car manual, p. 28).
- Project: Missions [미션], My project [내 프로젝트], AI model [인공지능 모델] (car manual, p. 30).
- Missions are an ordered list of tasks toward the integrated autonomous driving code; they start with controlling the car through the jchm library, then lane detection, obstacle avoidance and traffic-light recognition using the car's sensors (car manual, p. 30).
- My project creates an empty Jupyter Notebook [주피터 노트북] for your own driving algorithm (car manual, p. 31).
- AI model menu creates and manages the ResNet and YOLO models used by those tasks (car manual, p. 31).
- File storage lists every file and AI model made in Learning/Project, lets you open or bulk-delete them to free space, but cannot create new files or rename them (car manual, pp. 32, 37).

### 2.5 File handling (pp. 33-37)

- Create: hover over a learning menu entry and click the "+" icon, enter a name; duplicate names are refused with a warning (car manual, pp. 33-34).
- Per-menu folder icon lists that menu's files; double-click opens one; the gear icon renames or deletes it (car manual, p. 35).
- File storage: tick a menu in the left box to see its files; open or delete from there (car manual, pp. 36-37).
- Renaming only works from the menu's own folder, not from File storage (car manual, p. 37).

### 2.6 Learning/development environment (pp. 37-45)

- Appears when a file is created in Learning, Missions or My project (car manual, p. 37).
- Three panes (car manual, pp. 38-40):
  - Left: learning content, collapsible with an arrow button, with a chapter list behind a menu button.
  - Middle: Jupyter Notebook for running and writing Python.
  - Right: toolbar [툴바] with function search, image output, saved AI model list and virtual joystick.
- Function search covers Python, NumPy, OpenCV and Jajucha-library functions with key parameters, filterable by library (car manual, pp. 40-41).
- Image output window: shows camera and LiDAR images, or stored image files; an image window must be open before output; each window is assigned one role from `center`, `left`, `right`, `depth`, `lidar`; several windows can be open (car manual, p. 42).
- AI model search lists saved models by version (e.g. YOLO11N) and can delete them (car manual, pp. 42-43).
- Virtual joystick [가상 조이스틱]: mouse-driven only, no keyboard control; it is most useful alongside code that shows live video; at larger steering angles the maximum speed can be reduced (car manual, p. 43).
- Bottom bar: previous/next page (autosaves work) and exit (asks whether to save) (car manual, p. 44).

### 2.7 Jupyter Notebook usage (pp. 44-53)

- Only Python is installed in the in-app notebook (car manual, p. 45).
- Click the Start button [시작하기] when a file is first opened; this loads the Python runtime from the car's internal server, so code runs on the car (car manual, p. 46).
- Code lives in cells; learning and mission files come with pre-written code that can be edited (car manual, p. 46).
- Select a cell (blue bar at its left), then press run-current-cell; "[*]" marks a running cell and the bracket otherwise shows the run count; you cannot run only part of a cell (car manual, p. 47).
- Add a cell by hovering below the last cell and clicking the add button (car manual, p. 48).
- Run-all executes cells top to bottom; a `while True` loop in an earlier cell stops later cells from running (car manual, p. 48).
- Delete: select cell, press delete-current-cell, confirm (car manual, p. 49). Move: drag by the blue-bar area (car manual, p. 50).
- Stop button halts a long-running cell or an infinite loop (car manual, pp. 50-51).
- Restart kernel: clears accumulated memory and resets run counts; use when code behaves strangely after many runs (car manual, p. 52).
- Screen reset button (top bar, left): use if the kernel restart does not help or the screen freezes; unsaved work may be lost (car manual, p. 53).

### 2.8 Where the jchm API is mentioned in Part 1

- Missions begin with learning to drive the car with the `jchm` library (car manual, p. 30).
- The toolbar's function search includes the Jajucha library's functions (car manual, p. 40).
- Image windows named `center/left/right/depth/lidar` match the `location` argument of `jchm.camera.show_image` (car manual, pp. 42, 288).
- No other jchm function is described in pp. 4-54.

---

# PART 4, chapter 1: Controlling the car (pp. 279-301)

## 3. Practice track (p. 279)

- The page is a drawing titled "Jajucha practice track" [자주차 연습용 트랙] (car manual, p. 279).
- Labelled elements: start [출발], parking [주차] marked P, tunnel [터널], speed bump [방지턱], obstacle [장애물], traffic light [신호등] (car manual, p. 279).
- Mission types labelled TYPE-0, TYPE-1, TYPE-2 (car manual, p. 279).
- Footnote: mission positions may be changed arbitrarily (car manual, p. 279).
- The page has no dimensions in its text; geometry is only in the drawing (car manual, p. 279).

## 4. Importing the library (p. 281)

- `import jchm`; the name abbreviates "Jajucha and Hyundai Mobis" (car manual, p. 281).
- The library covers steering and drive-speed control, sensor data collection (camera, LiDAR), and a module for loading trained AI models such as ResNet and YOLO (car manual, p. 281).

## 5. API reference

### 5.1 Drive: `jchm.control.set_motor(left, right, speed)` (pp. 281-284)

| Parameter | Type / range | Meaning | Citation |
|---|---|---|---|
| `left` | integer, -10 to 10 | angle of the left front wheel | (car manual, p. 281) |
| `right` | integer, -10 to 10 | angle of the right front wheel | (car manual, p. 281) |
| `speed` | integer, -30 to 30 | drive motor speed | (car manual, p. 281) |

Steering facts:

- Each front wheel has its own DC servo motor, so left and right angles can differ (car manual, p. 281).
- Sign: negative = counter-clockwise, positive = clockwise (car manual, p. 282).
- Scale: each 1 unit of |value| changes the real wheel angle by 2 degrees, so the range is -20 to +20 degrees (car manual, p. 282).
- Figure anchors: -10 = -20 deg, -5 = -10 deg, 0 = 0 deg, 5 = 10 deg, 10 = 20 deg (car manual, p. 282).
- Example `set_motor(-10, 0, 0)` turns only the left wheel 20 deg counter-clockwise; `set_motor(0, 10, 0)` turns only the right wheel 20 deg clockwise (car manual, p. 282).
- `set_motor(0, 0, 0)` re-straightens both wheels (and stops) (car manual, pp. 282-283).

Drive facts:

- Rear wheels are driven by a BLDC motor; positive speed = forward, negative = reverse (car manual, p. 284).
- Each unit of |speed| adds 4 rad/s of motor speed; a differential gear reduces it at 38:15; wheel diameter is 6.5 cm; resulting ground speed changes by about 5.13 cm/s per unit (car manual, p. 284).
- Check of the manual's own number: speed 3 gives about 15.3 cm/s (3 x 5.13 = 15.39, manual says ~15.3) (car manual, p. 284).
- Max |speed| 30 therefore corresponds to about 154 cm/s by linear scaling (derived, not stated in the manual) (car manual, pp. 281-284).
- Rear-wheel drive: front wheels steer, rear wheels drive (car manual, p. 286).
- Turning: combine steering and speed. Example `set_motor(-5, -5, 3)` is a left turn at about 15.3 cm/s and `set_motor(5, 5, 3)` is a right turn (car manual, p. 286).
  So steering values negative = left turn, positive = right turn.
- Grip effect: on the real track, wheel contact/grip makes actual speed differ from the nominal figure, so the best steering and speed values must be tuned by repeated test runs (car manual, p. 286).
- Joystick: maximum speed may drop with steering angle (car manual, p. 43).

### 5.2 Camera (pp. 288-294)

#### `jchm.camera.get_depth()` (p. 289)

- Returns the car's built-in depth image [깊이 이미지] (car manual, p. 289).
- The car obtains distance by stereo vision [스테레오 비전] from its two cameras (car manual, p. 287).
- Depth image is grayscale and encodes distance as brightness: near = bright/white, far = dark/black (car manual, p. 287).
- Returned as a NumPy array; indexing a pixel, e.g. `depth_img[y, x]`, gives a 3-element array of equal values such as `[35 35 35]`, so index `[0]` for a scalar (car manual, p. 290).
- Larger pixel value = closer; smaller = farther (car manual, p. 290).
- Shape is read with `depth_img.shape[:2]` giving `(height, width)`; the centre pixel is `depth_img[height//2, width//2]` (car manual, p. 290).
- Example readings: centre pixel 59 with an obstacle in front; live values 14-24 when clear (car manual, pp. 291-292).
- Manual's example threshold: centre pixel >= 35 means an object ahead, so stop; otherwise drive at `speed=5` (car manual, pp. 291-292). Real missions use several regions of the depth image (car manual, p. 291).
- The depth image's resolution is not stated in pp. 288-294.

#### `jchm.camera.show_image(img, "location", quality=80)` (p. 289)

| Parameter | Meaning | Citation |
|---|---|---|
| `img` | image to display | (car manual, p. 288) |
| `location` | optional string, window to show it in; default `center`; also `right`, `left`, `depth`, `lidar` | (car manual, p. 288) |
| `quality` | output quality, default 80; higher is better quality but slower | (car manual, p. 288) |

- The matching image window must already be open in the toolbar before output (car manual, pp. 42, 289).
- Example: `jchm.camera.show_image(depth_img, 'depth')` (car manual, p. 289).

#### Not found in pp. 279-301

- `get_image` (colour camera capture, its location argument values) and the 640x400 resolution do not appear in this chapter; text search shows `get_image` first at pp. 305 onward, i.e. in the lane-detection chapter (see `car-lane-detection.md`).

### 5.3 LiDAR (pp. 294-300)

Sensor facts:

- Type: 2D LiDAR using time-of-flight [ToF], spinning 360 degrees to build a flat map (car manual, p. 294).
- A 2D LiDAR only sees objects at its own scan-plane height; objects below or above are missed (car manual, p. 294).
- It has a blind range [블라인드 범위] very near the sensor: 0.05 m (car manual, p. 294).
- Maximum range: 12 m radius (car manual, p. 294).
- Per revolution it returns about 300 to 450 range/angle samples as NumPy arrays; an example scan had 398 (car manual, pp. 294-295).
- Angle direction: the scan starts at the car's front and goes clockwise (car manual, p. 294).

#### `theta_array, dist_array = jchm.lidar.get_lidar()` (p. 295)

| Return | Meaning | Citation |
|---|---|---|
| `theta_array` | NumPy array of angles; first element is the front (0 deg) | (car manual, pp. 295, 298) |
| `dist_array` | NumPy array of distances, same length | (car manual, p. 295) |

- Example output: angles like 1.26, 1.98, 2.69, ... (so degrees, with gaps where no return arrived, e.g. 6.28 to 9.14), and distances like 1276, 1286, ... (car manual, pp. 295-296).
- Because samples are not evenly spaced and the count varies per revolution, the index does not map to a fixed angle (derived from the example scan, car manual, pp. 295-296).
- Units: distances are millimetres (the display function takes mm, and a front reading of 312.0 is compared against 300) (car manual, pp. 296, 298). Angle unit (degrees) is inferred from the values.
- `dist_array[0]` is described as the front reading at 0 deg; example front value 312.0 (car manual, p. 298).

#### `jchm.lidar.show_lidar(theta_array, dist_array, max_dist)` (p. 296)

- The printed signature on p. 296 reads `jchm.lidar.show_image(...)` but the example code on the same page calls `jchm.lidar.show_lidar(...)`; use `show_lidar` (car manual, p. 296).
- `max_dist`: maximum display distance, in mm, up to 12,000 (car manual, p. 296).
- Draws a 2D image in the `lidar` window: a red arrow at the centre marks the sensor, and the scan is drawn as green lines (car manual, p. 296).
- Example: `jchm.lidar.show_lidar(theta_array, dist_array, 5000)` shows a 5 m radius (car manual, p. 296).

#### Obstacle check example (pp. 298-300)

- Front reading under 300 mm means an object ahead, so stop; 300 or more, drive at `speed=5` (car manual, p. 298).
- Real missions convert angle/distance pairs to x, y coordinates using many LiDAR points (car manual, p. 298).

## 6. Timing and loop notes

- `time.sleep(1)` is used between commands in the examples so each motion lasts about 1 s; the last command is `set_motor(0, 0, 0)` to stop (car manual, pp. 281-282, 284, 286).
- Motor commands persist until replaced; the examples always finish with a zero-speed command, which implies no automatic stop (inferred from the examples).
- Sensor-polling loops are written as `while True:` with no sleep in the examples (car manual, pp. 292, 299).
- Infinite loops block later notebook cells and must be stopped with the stop button (car manual, pp. 48, 50-51).
- No sensor update rates or command latencies are stated in pp. 279-301.

## 7. Quick reference

```
import jchm
jchm.control.set_motor(left, right, speed)   # -10..10, -10..10, -30..30
img = jchm.camera.get_depth()                # NumPy, bright = near
jchm.camera.show_image(img, 'depth', quality=80)
theta_array, dist_array = jchm.lidar.get_lidar()   # deg (inferred), mm
jchm.lidar.show_lidar(theta_array, dist_array, 5000)
```

(car manual, pp. 281, 289, 295-296)

| Physical constant | Value | Citation |
|---|---|---|
| Steering step | 2 deg per unit, +/-10 units = +/-20 deg, per wheel | (car manual, p. 282) |
| Drive motor step | 4 rad/s per unit of speed | (car manual, p. 284) |
| Gear ratio | 38:15 reduction | (car manual, p. 284) |
| Wheel diameter | 6.5 cm | (car manual, p. 284) |
| Ground speed | about 5.13 cm/s per unit | (car manual, p. 284) |
| LiDAR range / blind range | 12 m / 0.05 m | (car manual, p. 294) |
| LiDAR samples per turn | about 300-450 | (car manual, p. 294) |
| Boot time | about 1 minute | (car manual, p. 12) |
| Full charge time | about 1 hour | (car manual, p. 13) |
