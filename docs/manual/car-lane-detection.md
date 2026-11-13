# Jajucha Car Manual, Part 4 Ch. 2: Lane Detection (digest)

Source: Korean Jajucha car manual, Part 4 ch. 2 "Lane detection" [차선 인식하기], PDF pp. 302-375 (printed page = PDF page - 1). All citations are PDF pages.
This digest restates the manual; it is not a translation. Where the manual is internally inconsistent, a "Note" says so.

## 1. Chapter map

| Section | Title | PDF pages |
|---|---|---|
| Chapter cover | 2장. 차선 인식하기 | 302 |
| 1 | Lane detection with a grid [격자(grid)로 차선 인식하기] | 303-340 |
| 1.1 | The three lane-detection missions | 303 |
| 1.2 | Canny edges + grid lines (steps 1-5, ROI, blur, Canny, feature point) | 304-313 |
| 1.3 | Driving with the jchm grid function (`gridFront`) | 313-324 |
| 1.4 | Grid-based lane driving (rule-based algorithms) | 325-340 |
| 2 | Lane detection by image classification [이미지 분류로 차선 인식하기] | 341-358 |
| 2.1 | Classifying lane images with an AI model (ResNet) | 341-352 |
| 2.2 | Driving by image classification | 352-358 |
| 3 | Lane detection by instance segmentation [인스턴스 분할로 차선 인식하기] | 359-375 |
| 3.1 | Recognizing lanes with instance segmentation (YOLO-seg) | 359-363 |
| 3.2 | Driving by instance segmentation (centerline, steer, P/PI/PID) | 364-375 |

(car manual, pp. 302-375)

## 2. Overall pipeline taught

- Three lane-detection approaches in the project: grid-based [격자 기반] (rule-based), image classification [이미지 분류] (deep learning), instance segmentation [인스턴스 분할] (deep learning). (car manual, p. 303)
- Rule-based means a person writes the rules; the deep-learning methods let a trained model derive its own rules. (car manual, p. 303)
- First practical mission: drive without leaving or crossing the lane. (car manual, p. 303)

Grid pipeline, 5 stages (car manual, p. 304):

| Step | What | Tool |
|---|---|---|
| 1 | Capture image from camera | `jchm.camera.get_image('center')` (car manual, pp. 304-305) |
| 2 | Remove noise by blurring | `cv2.GaussianBlur` (car manual, pp. 306-307) |
| 3 | Extract lane edges | `cv2.Canny` (car manual, pp. 306-307) |
| 4 | Predict lane position by drawing a grid and reading coordinates | `gridFront` / `cv2.line`, `cv2.circle` (car manual, pp. 308-315) |
| 5 | Drive: set steering and motor speed from the lane info | `jchm.control.set_motor` (car manual, p. 325) |

- The manual groups steps 1-3 as "capture and process", step 4 as "predict lane position", step 5 as "drive". (car manual, p. 304)
- The ROI crop is introduced as a preprocessing step inside steps 1-3, before blur. (car manual, p. 304)

## 3. Grid method: processing steps and parameters

### 3.1 ROI crop [관심 영역 (ROI)]

- Purpose: discard image parts irrelevant to lanes; keep only where the lane is expected. (car manual, p. 304)
- Syntax is NumPy slicing `image[y1:y2, x1:x2]` (y first, then x). (car manual, pp. 304-305)
- Value used: `roi = image[199:399, :]`, i.e. the lower half (200 rows) of the 640x400 image, all columns. (car manual, p. 305)
- Rule of thumb in the manual: usually the lower half of the image. (car manual, p. 305)
- Image displayed with `jchm.camera.show_image(roi, 'center', quality=90)`. (car manual, p. 305)

### 3.2 Gaussian blur [가우시안 블러링]

- `cv2.GaussianBlur(data, kernel, st_dev)`: kernel must be odd; st_dev is auto-computed if omitted. (car manual, p. 306)
- Value used: kernel `(3, 3)`, sigma `0`. (car manual, p. 307)

### 3.3 Canny edge detection [캐니 윤곽선 검출]

- `cv2.Canny(data, threshold1, threshold2, apertureSize)`; apertureSize is the Sobel filter size, default 3, odd only. (car manual, p. 306)
- Value used: thresholds `100` (low) and `300` (high). (car manual, p. 307)
- Why edges: lane borders (boundary between inside and outside of the road) become white on black, so only lane pixels remain. (car manual, p. 306)
- Warning: detecting too many edges makes non-lane areas look like lanes; tune the low/high thresholds. (car manual, p. 307)

### 3.4 Single reference line and feature point [특징점]

- Idea: draw a reference line on the Canny image; where it meets a lane edge, mark a feature point; the pixel distance from the image bottom to that point is the lane distance. (car manual, p. 308)
- Y axis in OpenCV grows downward, so a smaller Y of the feature point means the lane is farther away; a larger Y means closer. (car manual, p. 310)
- Canny output is single-channel, so convert to color first: `cv2.cvtColor(canny, cv2.COLOR_GRAY2BGR)` before drawing colored shapes. (car manual, pp. 308-309)
- Center line: `center_x = width // 2`, drawn green `(0, 255, 0)`, thickness 2, from `(center_x, 0)` to `(center_x, height-1)`. (car manual, p. 309)
- Search: scan y from `height-1` down to 0 along `center_x`; first pixel equal to 255 is the edge hit; stop at the first hit; `detected_y` starts at -1 meaning "not found". (car manual, p. 312)
- Marker: yellow filled circle `(0, 255, 255)`, radius 10, thickness -1. Example printed result: Y = 80. (car manual, pp. 311-312)
- Function references: `cv2.line(img, pt1, pt2, color, thickness)` (BGR colors) and `cv2.circle(img, center, radius, color, thickness)` (-1 fills). (car manual, pp. 308, 310-311)

## 4. The jchm grid function

### 4.1 What it does

- A single reference line is not enough, so the grid uses several vertical and horizontal lines. (car manual, p. 313)
- `gridFront` does ROI, blur, Canny and grid drawing automatically. Default: 3 red horizontal lines, 7 green vertical lines. (car manual, p. 313)
- Image size is 640x400 by default; with the default ROI a grid cell is 80 px x 50 px. (car manual, p. 313)
- Note: p. 313 says the ROI is split into "30 regions" in one caption and "32 regions" in the body text; the counts are inconsistent. (car manual, p. 313)
- Signature: `(V, L, R), grid = jchm.camera.gridFront(img)`; returns 7 V values, 3 L values, 3 R values plus the grid image. (car manual, pp. 314-315)

### 4.2 Meaning of the feature points

| Name | Color | Meaning | Source |
|---|---|---|---|
| L[0], L[1], L[2] | pink | Pixel distance from the center vertical line V3 to the left lane edge at the 1st, 2nd, 3rd horizontal line | (car manual, p. 316) |
| R[0], R[1], R[2] | pink | Same for the right lane edge | (car manual, p. 317) |
| V[0]..V[6] | yellow | Vertical pixel distance from the image bottom (ROI bottom) up to the lane, along vertical line Vn | (car manual, p. 318) |

- Vertical line V3 is the exact image center (4th of 7 lines) and represents the car's own center position, assuming the camera is mounted at the car's center. (car manual, pp. 316, 327)
- L larger means farther from the left lane; smaller means nearer. Same for R. Comparing L and R tells whether the camera is left or right of the lane center. (car manual, pp. 316-317)
- V values reveal lane shape ahead (straight vs left/right curve). (car manual, p. 318)
- Example printed output: V `[58, 86, 111, 126, 133, 135, 28]`, L `[235, 107, 253]`, R `[212, 232, 212]`. (car manual, p. 315)
- Note: the manual's figure captions for L and R reuse the same sentence ("from V3 to the left lane") for both; R is the right side. (car manual, p. 317)

### 4.3 Tunable parameters of `gridFront`

| Parameter | Meaning | Default | Source |
|---|---|---|---|
| `rows` | number of horizontal lines | 3 | (car manual, p. 319) |
| `cols` | number of vertical lines | 7 | (car manual, p. 319) |
| `y_max` | max height of the grid ROI | 200 | (car manual, p. 319) |
| `ths1` | Canny low threshold | 100 | (car manual, p. 319) |
| `ths2` | Canny high threshold | 300 | (car manual, p. 319) |
| `v_line_color` | vertical line color (BGR) | (39, 157, 47) | (car manual, p. 319) |
| `h_line_color` | horizontal line color | (0, 0, 255) | (car manual, p. 319) |
| `v_point_color` | vertical-line intersection point color | (18, 246, 255) | (car manual, p. 319) |
| `u_point_color` | horizontal-line intersection point color | (221, 0, 255) | (car manual, p. 319) |

- More lines give finer detection but more values to reason about; fewer lines simplify but lose detail. (car manual, p. 319)
- Example: `cols=10, rows=5` gives V with 10 entries and L, R with 5 entries each. (car manual, p. 320)
- `y_max`: raise it if the lane appears higher in the image; lower it to ignore unneeded areas. Example `y_max=300`. (car manual, p. 321)
- `ths1`/`ths2`: lowering the low or raising the high threshold detects more edges; the reverse detects fewer. Example `ths2=600`. (car manual, pp. 322-323)
- Colors can be changed to tell several grid images apart; example sets all four to blue `(255, 0, 0)`. (car manual, pp. 323-324)
- Note: the prose calls BGR (18,246,255) "pink" and (221,0,255) "yellow", while the screenshots show V points yellow and L/R points pink. Treat colors as cosmetic. (car manual, pp. 314, 323)

## 5. Grid-based driving (rule-based algorithms)

- Rule-based algorithm = human-written if-then rules mapping input to output; workflow is design, code, run, debug. (car manual, p. 325)
- Motor call used throughout: `jchm.control.set_motor(a, b, c)`. From usage, the first two arguments are steering values (positive = right, negative = left, 0 = straight) and the third is speed. The manual does not define the arguments in this chapter; this is inferred from the flowcharts. (car manual, pp. 325, 329, 333)

### 5.1 Stop before a lane ahead

- Loop: capture image, `gridFront`, then if `V[3] >= 70` drive straight `set_motor(0, 0, 5)`, else `set_motor(0, 0, 0)` and break. (car manual, pp. 325-326)
- V[3] < 70 px means a lane is directly ahead. (car manual, p. 327)

### 5.2 Keep lane center

- Cause of lane departure: after obstacle avoidance or corners the car drifts to one side. (car manual, p. 326)
- When centered, L and R are similar. Example centered: L[1]=152, R[1]=158 (figure also shows 320/320). Drifted left: L[1]=71 vs R[1]=285 (about 4x). Drifted right: L[1]=219, R[1]=67. (car manual, pp. 328-329)
- L[1] and R[1] alone are sufficient in principle; other points should also be used in real driving. (car manual, p. 328)
- Implemented rules: `L[1] < 150` then `set_motor(5, 5, 3)` (right correction); `elif R[1] < 150` then `set_motor(-5, -5, 3)` (left correction); else straight `set_motor(0, 0, 5)`. Display `grid` with `quality=50`. (car manual, p. 330)
- Threshold 150, steering magnitude 5 and speed 3 are to be retuned per lane width and situation. (car manual, p. 328)
- Note: the flowchart on p. 329 also has a `V[2] >= 100?` gate before each check, but the code on p. 330 omits it. (car manual, pp. 329-330)
- Note: result item 2 on p. 331 says "turn right" for R[1] < 150, contradicting the code and flowchart (left turn). Treat as a typo. (car manual, pp. 329-331)

### 5.3 Curve driving, version 1 (gentle curves)

- Straight lane: V values are large and nearly equal (example V[2]=130, V[4]=129). Lane ahead blocking: V shrinks (example V[2]=57 near a right-turn lane). (car manual, p. 332)
- V[2] is mainly used for right turns, V[4] for left turns; more values may be needed for wide or angled lanes. (car manual, p. 333)
- Rules: `V[2] < 100` then `set_motor(5, 5, 5)` (right); `elif V[4] < 100` then `set_motor(-5, -5, 5)` (left); else `set_motor(0, 0, 5)`. Display `quality=100`. (car manual, pp. 333-334)
- Example readings: V[2]=84 triggers right; V[4]=75 triggers left; 130/129 means straight. (car manual, p. 335)

### 5.4 Curve driving, version 2 (right-angle corners) and full-lap combination

- The track has two corner types: gentle curves and sharp (right-angle) corners; version 1 leaves the lane at sharp corners. (car manual, p. 336)
- Average several V values (here V[2] and V[3]) to resist heading or speed changes. Before the corner: 137 and 138; inside the corner: 100 and 101. (car manual, pp. 336-337)
- V is a list; convert via `np.array(V)`, slice, then `np.mean()`. Signatures of `np.array`, slicing and `np.mean(array, axis, dtype, keepdims)` are described. (car manual, pp. 337-338)
- Full-lap rule set (priority order):
  1. If the mean of the selected V values is `< 125`, `set_motor(-10, -10, 5)` (sharp left). (car manual, p. 339)
  2. Else apply lane centering: `L[2] < 150` then `set_motor(5, 5, 3)`; `elif R[2] < 150` then `set_motor(-5, -5, 3)`; else `set_motor(0, 0, 5)`. (car manual, p. 339)
- Note: the code takes `V_arr[2:3]`, which selects only V[2], while the comment and text say V[2] and V[3]; `V_arr[2:4]` would match the intent. (car manual, pp. 338-339)
- Closing advice: grid values and layouts are not fixed; design and validate many algorithms. (car manual, p. 340)

## 6. Image-classification method (ResNet)

### 6.1 Concept

- Supervised learning of lane images into 3 classes: left (left-turn lane), right (right-turn lane), straight. The AI model is ResNet. (car manual, p. 341)
- The car runs a fixed model track, so lane types met are limited, which is why classification works. (car manual, p. 341)
- Classes may be split further (e.g., gentle vs sharp right turn) for finer decisions. (car manual, p. 343)

### 6.2 Three-stage training workflow

| Stage | Content | Source |
|---|---|---|
| 1 | Prepare: set classes [클래스], collect data (camera) | (car manual, p. 342) |
| 2 | Train: pick a ResNet model, train with PyTorch, test | (car manual, p. 342) |
| 3 | Save: register the model in the car's internal storage, check it | (car manual, p. 342) |

- Class creation uses the "add class +" button; assigning a class to images is data labeling [데이터 레이블링]. (car manual, p. 342)
- Data collection tool parts: class select, camera image, record/capture buttons, joystick, captured image viewer. (car manual, pp. 343-345)
- Camera: `center`, 640x400. Red button = continuous capture; blue = single capture. Joystick can fix speed or steering angle. (car manual, pp. 344-345)
- An ROI box can be chosen on the camera image (top-left white square, then blue box) to capture only the lower lane area. (car manual, p. 345)
- Collect at least 100 images per class, from varied angles. (car manual, p. 346)
- Model choices: RESNET18, RESNET34, RESNET50, RESNET101; deeper means more accurate but slower to train. (car manual, p. 346)
- Training settings: `EPOCH = 20`, `pre_epoch = 0`, `LR = 0.01`, `TRAIN_DATA_PERCENT = 0.8`, `BATCH_SIZE = 16`. (car manual, p. 347)
- Meaning: epoch = total passes; batch = how many chunks per epoch; LR = weight step size; train ratio = train/test split. (car manual, pp. 347-348)
- Result charts: training loss and accuracy; example loss 0.035, train accuracy 98.78%, test accuracy 99.03%. A good model has high, similar train and test accuracy. (car manual, p. 348)
- Testing: find epoch names under checkpoints, train, weights; put the name (string) in `NAME`; the center window shows the predicted class number (e.g., 1 = right, 2 = straight). Printed outputs are per-class probabilities; the largest wins. (car manual, pp. 348-350)
- Registering: enter the saved path manually and give a new English-only name; saved models are listed under the "AI model" toolbar item and can be deleted via the three-dot menu. (car manual, pp. 350-352)

### 6.3 Driving with the classifier

- AI classifies the lane; the human writes the motor rules. Flowchart: left lane then `set_motor(-5, -5, 3)`; right lane then `set_motor(5, 5, 3)`; else straight `set_motor(0, 0, 5)`. (car manual, p. 351)
- Known problem: misclassification occurs because training images were ROI crops while test input was the full 640x400 frame. Fix: crop the live image to the same region used in training. (car manual, p. 353)
- Training image filenames encode crop geometry as `time_(xcenter ycenter)_(xsize ysize).jpg` in fractions of the image; example `1903019_050081_100039` gives center (0.5, 0.81), size (1.0, 0.39), i.e. width 640 px and height about 156 px. (car manual, p. 354)
- Note: the manual's figure writes the y-center product as 320, but 0.81 x 400 = 324; treat the fractions as authoritative. (car manual, p. 354)
- Code C steps: `jchm.load_ai()`; set `NAME`; set fractions `center_x=0.5, center_y=0.81, width=1.0, height=0.39`; each loop, take the image, compute `cx, cy, box_w, box_h` from the fractions and image size, clamp `x1,y1,x2,y2` to the image, crop `image[y1:y2, x1:x2]`. (car manual, pp. 355-356)
- Inference: `jchm.ai.get_model_output(cropped, NAME)`, then `torch.max(output, 1)` gives `predicted_index`; label drawn with `cv2.putText`. (car manual, p. 356)
- Motor mapping in code: index 0 `set_motor(7, 7, 2)`, index 1 `set_motor(-7, -7, 2)`, index 2 `set_motor(0, 0, 2)`. (car manual, p. 357)
- Note: code comments say 0 = left, 1 = right, 2 = straight, while the result text says 0 = right turn, 1 = left turn; positive steering (7) is otherwise a right turn. Class index meaning depends on class creation order; verify against your own model. (car manual, pp. 357-358)

## 7. Instance-segmentation method (YOLO-seg)

### 7.1 Concept and training

- Instance segmentation [인스턴스 분할] is an extension of YOLO that learns objects at pixel level, giving precise outlines rather than boxes. (car manual, p. 359)
- Labeling uses polygon labeling [다각형 레이블링]: click points along the lane outline; undo with the back button; trace densely. (car manual, pp. 360, 362)
- Only one class (the lane) is needed. Fewer images than classification suffice, but vary angles and lane kinds. Suggested capture: divide the lane into six sections and vary car position and heading in each. (car manual, pp. 360-361)
- After labeling, press "create data" (bottom-left) to export polygons as text files. (car manual, p. 363)
- Model choices: YOLO8N-SEG and YOLO11N-SEG (CNN-based; higher version = newer). Output shows a blue mask over the lane. (car manual, p. 363)

### 7.2 Centerline from the mask

- Method: for each image row from top to bottom, find x positions inside the lane mask, average them to get `cx`, store `(cx, y)`; connect points to form a center path. (car manual, p. 364)
- Code steps: `jchm.load_ai()`; `NAME`; silence ultralytics logging; `jchm.ai.get_model_output(image, NAME)`; take `results[0]`; `result.plot()` for the overlay. (car manual, p. 365)
- Pick the best instance: `scores = boxes.conf`, `best_idx = np.argmax(scores)`; `best_mask = masks[best_idx]`. (car manual, pp. 365-366)
- Resize mask to image size with `cv2.resize(..., interpolation=cv2.INTER_NEAREST)`; binarize with `> 0.5`. (car manual, p. 366)
- Per row: `np.where(binary_mask[y, :] == 1)`, `cx = int(np.mean(x_indices))`; draw red `(0, 0, 255)` thickness-2 lines between consecutive points. (car manual, p. 366)

### 7.3 Steering and speed

- Take `avg_cx`, the mean of all centerline x values, as the single representative value; compare it with the image center x (320). (car manual, p. 367)
- Center line right of image center means the car is left of the lane, so steer right; and vice versa. (car manual, p. 367)
- Basic formula: the printed form lacks parentheses, but the code is `steer = (avg_cx - 320) * 0.1`; the scale smooths steering. (car manual, pp. 367, 369)
- Clamp: `steer = max(min(steer, 10), -10)`. (car manual, p. 370)
- Output: `jchm.control.set_motor(int(steer), int(steer), 2)`, i.e. both steering args are the same steer value and speed is fixed at 2. (car manual, p. 370)
- Sign convention stated: negative steer = left turn, positive = right turn. (car manual, pp. 370-371)
- Default `steer = 0` when no mask is found. Overlay: green vertical line at `avg_cx`, text "Avg X" and "Steer", `quality=80`. (car manual, pp. 368, 370)
- Note: the sample code has typos (`frame.shape`, `imgae`) that would fail as printed; the intent is `image.shape`. (car manual, p. 368)

### 7.4 P, PI, PID control

| Controller | Formula in manual | Notes | Source |
|---|---|---|---|
| P [비례 제어] | `steer = (mean_x - w/2) * Kp` | w = 640 so w/2 = 320; Kp user-chosen (earlier fixed 0.1); still clamp to +/-10 | (car manual, pp. 371-372) |
| PI | `steer = (mean_x - w/2)*Kp + integral*Ki` | integral = error accumulated over time; fixes steady-state error [정상 상태 오차] | (car manual, pp. 373-374) |
| PID | `steer = (mean_x - w/2)*Kp + integral*Ki + Kd*derivative` | derivative = rate of change of error (`avg_cx - 320`) over dt; damps sudden changes | (car manual, pp. 374-375) |

- Larger error means larger steer; smaller error means gentler steer. (car manual, p. 371)
- The manual gives no numeric Kp, Ki or Kd; the reader is told to find them by repeated driving trials (`kp =` left blank). (car manual, p. 372)
- P control suffices for the project; PI/PID are optional refinements. (car manual, p. 373)

## 8. Practice tasks and missions in this chapter

- Task: crop the ROI and display it (`image[199:399, :]`). (car manual, pp. 303-305)
- Task: blur and Canny, then display the edge image. (car manual, p. 307)
- Task: draw a green center line on the edge image. (car manual, p. 309)
- Task: find the first edge pixel on that line and mark it with a yellow circle. (car manual, pp. 311-312)
- Task: print `V`, `L`, `R` from `gridFront` and view the grid. (car manual, pp. 314-315)
- Task: change `cols`/`rows` (10 and 5), `y_max` (300), `ths2` (600), and colors. (car manual, pp. 319-324)
- Task: drive straight and stop when `V[3] < 70`. (car manual, pp. 325-327)
- Task: lane centering with `L[1]`/`R[1]` threshold 150, placing the car off-center first. (car manual, p. 330)
- Task: right/left curve driving with `V[2]`/`V[4]` threshold 100. (car manual, pp. 333-335)
- Task: complete a full lap by combining sharp-corner detection (V mean < 125) with centering (`L[2]`/`R[2]` < 150). (car manual, pp. 338-340)
- Task: collect >= 100 images per class, train a ResNet, test, register the model, then drive with it using a crop matching training. (car manual, pp. 341-358)
- Task: label polygons, train YOLO-seg, draw the centerline, steer from `avg_cx`, then tune `kp`. (car manual, pp. 359-372)

## 9. Not covered in pages 302-375

- No HSV/color thresholding, Hough transform, perspective/bird's-eye-view transform, or morphology appears in this chapter; the grid approach uses only ROI crop, Gaussian blur, Canny, and grid sampling. (car manual, pp. 303-340)
- No PID gain values are provided; only the formulas. (car manual, pp. 372-375)
