# 2026 Jajucha Competition Manual: English Digest

Digest of the Korean "2026 Hyundai Mobis Engineering Leader Festival" guide (53 PDF pages), covering the autonomous-car competition [자율주행자동차 경진 대회, "jajucha" 자주차]. Citations use PDF page numbers; the printed page number is PDF page minus 4. The manual is dated 2026-10-21. Course-layout drawings are images in the PDF and were not available as text, so exact panel layouts are not captured here.

## 1. Event and schedule (brief)

- Festival date: Saturday 2026-11-07, 09:00-17:00, at Hana Academy gymnasium (competition and academic conference); the debate contest is held in classrooms. (competition manual, p. 2)
- Eligible participants: students who completed or are taking a Hyundai Mobis engineering-leader course, selected through an in-school qualifier; one teacher per school gets travel pay. (competition manual, p. 2, p. 17)
- Practice: track open 09:00-13:00 on a first-come basis, up to 20 minutes per school (the detailed schedule says up to 20 minutes, twice). (competition manual, pp. 2-3)
- Practice locations on the day: gym 2nd-floor competition track allows one test lap only and no AI training; ground-floor dance room allows driving practice without the obstacle zone, and sign-recognition AI training is allowed there. (competition manual, p. 4)
- Opening ceremony 14:00; old-model [구형 자주차] preliminary 14:15-15:30, one attempt per team, top 3 advance; eliminated teams must stay until the awards. (competition manual, p. 3)
- New-model [신형 자주차] league (3 teams, 2027-model briefing, then one attempt each) 15:30-16:00; old-model final (3 teams, one attempt each, ranks 1-3) 16:00-16:30; awards 16:30-17:00. (competition manual, p. 3)
- Old-model preliminary field: 7 teams are named, though the schedule text says 8 in places (see uncertain facts). (competition manual, pp. 3-4)
- Final tie-break: a tie triggers a rematch. (competition manual, p. 4)
- Other events (engineering debate, "Youth Engineering" academic conference) are out of scope for the simulator. (competition manual, pp. 11-16)

## 2. Course overview

Two courses: a preliminary course (10 numbered zones) and a final course (9 numbered zones plus extra missions). One track panel is 90 cm x 90 cm. (competition manual, pp. 18-22)

### 2.1 Preliminary course zones

| Zone | Task |
|---|---|
| 1 | Start on the starting-light signal (competition manual, p. 18) |
| 2 | S-curve section (competition manual, p. 18) |
| 3 | Right-angle [직각] section (competition manual, p. 18) |
| 4 | Tunnel (competition manual, p. 18) |
| 5 | Ramp (competition manual, p. 18) |
| 6 | Ramp, then right turn and straight (competition manual, p. 18) |
| 7 | Zigzag section (competition manual, p. 18) |
| 8 | Obstacle zone, avoiding obstacles (competition manual, p. 18) |
| 9 | Curved course, then straight (competition manual, p. 18) |
| 10 | Drive to the finish line without hitting the partition [격벽 = pit sign] (competition manual, p. 18) |

(competition manual, p. 18)

### 2.2 Final course zones

| Zone | Task |
|---|---|
| 1 | Start on the starting-light signal (competition manual, p. 20) |
| 2 | S-shaped tunnel (competition manual, p. 20) |
| 3 | Right-angle section (competition manual, p. 20) |
| 4 | U-turn, then straight (competition manual, p. 20) |
| 5 | L-shaped ("ㄱ") corner ramp (competition manual, p. 20) |
| 6 | Zigzag section (competition manual, p. 20) |
| 7 | Obstacle zone, avoiding obstacles (competition manual, p. 20) |
| 8 | Curved course, then straight (competition manual, p. 20) |
| 9 | Drive to the finish line without hitting the partition (pit sign) (competition manual, p. 20) |
| extra | Yellow flag plus speed measurement, and sudden obstacle (Track Marshal) |

(competition manual, p. 20)

- Differences from preliminary: the S-curve becomes an S-shaped tunnel, the straight tunnel becomes the corner ramp, a U-turn is added, the obstacle zone is split into A and B, and two extra missions are added. (competition manual, pp. 18, 20, 22)

## 3. Missions: geometry and physical specs

### 3.1 Starting light [스타팅 라이트]

- Four LEDs light one after another; once all four are lit, they all go out together after a random wait, and the car starts at that moment. (competition manual, p. 18)
- LEDs turn on at 1.5 s intervals; all-off occurs randomly 3-6 s after the fourth LED lights. (competition manual, pp. 18, 21)
- A team may forgo the bonus and start manually; a separate, ready-to-run manual-start program must be prepared. (competition manual, p. 18)
- The device is an Arduino Nano with a MAX7219 dot-matrix module (rows act as the lamps), an active piezo buzzer, two buttons, and a 4xAA pack. (competition manual, pp. 29-30)
- Pins: matrix DIN D11, CS D10, CLK D13; buzzer D5; yellow button D7; red button D2. (competition manual, p. 30)
- Red button (D2) runs the sequence: 3 s all dark, then rows light from the bottom at 1.5 s steps with short beeps, then a random 3-6 s wait, then all go dark with a long beep. (competition manual, p. 36)
- Yellow button (D7) lights one more row per press (from the bottom) and clears after the fourth; useful for testing code or gathering YOLO training images. (competition manual, p. 37)
- Practice is recommended with a sign board and a cover (see Appendix 4); the starting-light placard is 3 cm x 13 cm. (competition manual, pp. 37, 51)

### 3.2 Tunnels [터널]

- Preliminary: U-shaped tunnel; final: S-shaped tunnel. (competition manual, pp. 18, 21)
- On competition day the tunnel is roofed with a top panel, the lane markings are hidden with black tape, and the interior is painted black; a few holes in the roof let judges look inside. (competition manual, pp. 18, 21)
- Built from corrugated plastic board [단프라]; the 2026 tunnel is assembled from panels joined with Velcro for competition use. (competition manual, pp. 49-50)
- Panel types: A and B for curved lanes (one curved lane needs 2 A and 1 B), C for straight lanes (one straight lane needs 2 C). Joining tabs protrude 30 mm. (competition manual, pp. 49-50)

| Panel | Preliminary | Final | Total to build |
|---|---|---|---|
| A | 4 | 12 | 12 |
| B | 2 | 6 | 6 |
| C | 2 | 0 | 2 |

(competition manual, p. 50)

### 3.3 Ramps [경사로]

- Preliminary: a hill on the straight (zones 5-6). Final: a hill at the corner ("ㄱ" ramp). (competition manual, pp. 18-19, 21)
- Slope angle about 6 degrees, height about 100 mm. (competition manual, pp. 19, 21)
- Ramps are judged under the lane rules (lane touch and departure). (competition manual, p. 25)

### 3.4 Obstacle zone [장애물 구역]

- Obstacles are 15 cm cubes of sponge; one track panel is 90 cm x 90 cm. (competition manual, pp. 19, 22)
- Final course: scored as zone A and zone B separately; if zone A fails, the car is moved to the zone B restart point and drives again. (competition manual, p. 22)
- Collision with an obstacle fails the mission; the car is moved to a judge-designated spot. (competition manual, p. 26)

### 3.5 Pit sign / partition [피트 표지판, 격벽]

- A sign stands at the pit (vehicle storage) entrance; the car must pass without touching it. Sign size 32 cm x 13 cm. (competition manual, pp. 19, 21, 51)
- Collision fails the mission and the car is relocated by the judge. (competition manual, p. 26)

### 3.6 Yellow flag plus speed measurement (final only) [옐로 플래그]

- On recognising the yellow flag the car must slow down until the next panel. (competition manual, p. 22)
- Speed must be 1-3 in terms of the `set_motor()` speed argument (`jchm.control.set_motor()`); speed 4 or more fails. (competition manual, pp. 22, 26)
- The flag is 15 cm x 18 cm. (competition manual, p. 51)
- On competition day an infrared speed meter measures speed; the install position is revealed on the day. In practice, simply slow down in that section. (competition manual, p. 22)

### 3.7 Sudden obstacle / Track Marshal [돌발 장애물] (final only)

- When the obstacle appears the car must stop; once it leaves the track the car restarts. (competition manual, p. 23)
- The obstacle sits at the exact centre of a track panel; the sign is 24 cm x 24 cm. (competition manual, pp. 23, 51)
- The stop counts only if the car's front-wheel contact patch touches the panel holding the obstacle (judging text: at least one front wheel). (competition manual, pp. 23, 26)
- It is moved by a motor on competition day; in practice it may be hand-moved on a stick. (competition manual, p. 51)
- The yellow-flag/speed meter and the sudden obstacle are installed within candidate spots 1-5 of the final course; positions are revealed on the day. (competition manual, p. 23)

### 3.8 Speed meter hardware [속도 측정기]

- Arduino Uno R3, two E18-D80NK infrared proximity sensors, MAX7219 matrix, two buttons, active buzzer, 4xAA pack through a DC jack. (competition manual, p. 38)
- Pins: front sensor D2, rear sensor D3, red button D4, blue button D6, buzzer D5, matrix DIN/CS/CLK on D11/D10/D13. (competition manual, p. 39)
- Speed is computed from the time difference between the two sensors; the car must trigger D2 first, then D3. (competition manual, pp. 26, 45)
- Default limit is 21 cm/s: at or below shows PASS (3 s, short beep), above shows blinking OVER (3 s, long beep). (competition manual, p. 47)
- Measurement is void if D3 triggers first, both trigger at once from the start, or D3 is not reached within 5 s of D2. (competition manual, p. 47)
- Sensors must be tuned so a car on the outer side of the lane is detected; the nominal range is about 3-80 cm. (competition manual, p. 45)
- Red button (D4) starts or stops measuring; ready after 0.1 s with nothing detected. Blue button (D6) shows the previous speed for 3 s. (competition manual, pp. 46-47)
- During the 3 s result display no new measurement is taken. (competition manual, p. 47)

## 4. Rules for competitors

### 4.1 Before the start

- Every waiting car and laptop is kept in one holding area; using an unsubmitted spare car or laptop is disqualifying. (competition manual, p. 24)
- On your turn: take over the school's car from the assistant judge, power it, link the laptop, and within 1 minute verify the motors (via the joystick) and the driving loop, then report to the judge. Practising while waiting counts as cheating and costs the lane-departure penalty. (competition manual, p. 24)
- The judge sets the car on the start line. The team announces auto start (driving loop already running, car leaves on the light signal, loop launched on the judge's cue before the light runs) or manual start (loop launched by hand after the buzzer). (competition manual, p. 24)
- A failed auto start forces manual start on attempt 2, so an unedited manual-start program must be ready. (competition manual, p. 24)
- A judge starts the timer at the buzzer. (competition manual, p. 24)

### 4.2 During the run

- The car handler follows the car and relocates it on the head judge's orders after a departure or failure; other teammates, the laptop operator included, wait at the assigned spot, and rushing the track is disqualifying. (competition manual, p. 24)
- Once timing has begun the laptop may only start, stop or restart the driving program, with no code changes. (competition manual, p. 24)

### 4.3 Coding rules

- Code is editable only in the preparation phase; nothing may change after the 14:00 start, and swapping in a pre-made spare file is disqualifying. (competition manual, p. 25)
- A team whose code was written by an adult (parent, teacher, expert, vendor), with the student only running the car, is disqualified. (competition manual, p. 25)
- Any driving style is fine (sharp turns, reversing to correct) provided the car stays on the course. (competition manual, p. 25)

### 4.4 Other rules

- Only bottled water is supplied and outside food or drink is banned; teachers may film from a distance without disturbing play; school uniform is required. (competition manual, p. 25)
- Car skins are optional; a skin may show only the team name, school logo and Hyundai Mobis CI. (competition manual, p. 25)
- The pages read give no policy on hardware or sensor modification; only the `jchm.control.set_motor()` speed convention is mentioned (see uncertain facts). (competition manual, pp. 22, 26)

## 5. Judging definitions

### 5.1 Lane driving (including ramps)

| Term | Criterion |
|---|---|
| Lane touch [차선 침범] | At least one wheel contact patch is on or inside the white line |
| Driving while touching | Lane-touch state held for 1 s or longer (competition manual, p. 25) |
| Lane departure [차선 이탈] | Three or more wheels outside the white line |

(competition manual, p. 25)

- After a departure the car goes where the head judge says; the clock stops until restart and resumes at restart; the restart must occur within 1 minute. (competition manual, p. 25)

### 5.2 Other missions

| Element | Rule |
|---|---|
| Starting light | Starting before all LEDs go off (before the buzzer) is a false start |
| Starting light | If the car has not moved within 5 s of the buzzer, the mission fails (competition manual, p. 26) |
| Starting light | Manual start uses the same standards; on false start or failure follow the judge |
| Tunnel | Contact with the tunnel fails the mission; relocate to the judge's spot |
| Obstacle zone | Collision fails; relocate to the judge's spot |
| Speed measurement | Time between two IR sensors gives speed; based on `set_motor()` speed; 4 or more fails (3 or less passes) (competition manual, p. 26) |
| Sudden obstacle | Collision fails; success requires stopping with at least one front-wheel contact patch on the panel with the obstacle; stopping without that still fails |
| Pit | Collision with the pit sign fails; relocate to the judge's spot |

(competition manual, p. 26)

- When the head judge calls a mission failure the timer stops until restart and resumes then; restart must be within 1 minute. (competition manual, p. 26)

## 6. Scoring

Both sheets start from a base of 100 points. (competition manual, pp. 27-28)

### 6.1 Preliminary sheet

| Item | Effect |
|---|---|
| A. Lane touch | -1 per occurrence (competition manual, p. 27) |
| B. Driving while touching | -1 extra per second; if it leads to a departure, departure points also apply (competition manual, p. 27) |
| C. Lane departure | -10 per occurrence; relocate and restart (competition manual, p. 27) |
| D. Pit sign failure | -3; relocate and restart (competition manual, p. 27) |
| E1. False start | -4 (competition manual, p. 27) |
| E2. Starting-light success | +4 (competition manual, p. 27) |
| E3. Time-delay failure | timer reset, manual restart, no bonus or penalty (competition manual, p. 27) |
| F. Tunnel success | +5 (competition manual, p. 27) |
| G. Obstacle zone success | +10 (competition manual, p. 27) |
| H. Completion time | Relative ranking among 8 schools: 15, 12, 10, 8, 6, 4, 2, 1 points in order; none if the run is not finished (competition manual, p. 27) |

(competition manual, p. 27)

- Total: 100 - [A + B + C + D + E1] + [E2 + F + G + H]. (competition manual, p. 27)

### 6.2 Final sheet

| Item | Effect |
|---|---|
| A. Lane touch | -1 per occurrence (competition manual, p. 28) |
| B. Driving while touching | -1 extra per second (competition manual, p. 28) |
| C. Lane departure | -10 per occurrence (competition manual, p. 28) |
| D. Pit sign failure | -3 (competition manual, p. 28) |
| E1. False start | -4 (competition manual, p. 28) |
| E2. Starting-light success | +4 (competition manual, p. 28) |
| E3. Time-delay failure | no bonus or penalty (reset and manual restart) (competition manual, p. 28) |
| F1. Sudden obstacle collision | -4 (competition manual, p. 28) |
| F2. Stopping near the obstacle successfully | +4 (competition manual, p. 28) |
| F3. Distance-control failure | no points either way (competition manual, p. 28) |
| G. Speed violation (speed 4 or more) | printed as "4 points" in the sheet (see uncertain facts) (competition manual, p. 28) |
| H. Tunnel success | +5 (competition manual, p. 28) |
| I. Obstacle zone | +5 for zone A success, +5 for zone B success (competition manual, p. 28) |
| J. Completion time | Relative ranking among 3 schools: 15, 12, 10 points in order; none if not finished (competition manual, p. 28) |

(competition manual, p. 28)

- Total: 100 - [A + B + C + D + E1 + F1] + [E2 + F2 + G + H + I + J]. (competition manual, p. 28)

### 6.3 Disqualification

- Three or more lane departures, exceeding a time limit (value not stated in the pages read), or cheating means disqualification. (competition manual, pp. 27-28)
- Other disqualifying acts: spare car or laptop use, code swapping, adult-written code, teammates entering the track (see section 4). (competition manual, pp. 24-25)

## 7. Officials

- Commentator and announcer, head judge (real-time scoring), and assistant judges: one verifies score sheets, two monitor cheating (one also handles timing, one handles car handover and participant management). (competition manual, p. 26)

## 8. Sign set (2026) [표지판]

| Sign | Size |
|---|---|
| Starting-light placard | 3 cm x 13 cm (competition manual, p. 51) |
| Yellow flag | 15 cm x 18 cm (competition manual, p. 51) |
| Pit sign | 32 cm x 13 cm (competition manual, p. 51) |
| Sudden obstacle (Track Marshal) | 24 cm x 24 cm (competition manual, p. 51) |

(competition manual, p. 51)

- Printed on matte-coated synthetic paper and mounted on foam board, as in 2025; image files are downloadable by link. (competition manual, p. 51)

## 9. Uncertain facts

- Preliminary field size: the overview lists 7 old-model teams, the detailed schedule says 8, and one line says 8 teams are eliminated; scoring uses 8 for the time ranking. (competition manual, pp. 2-4, 27)
- The final-sheet speed-violation row says "4 points" awarded for speed 4 or more, which reads like a penalty; the sign is not confirmed. (competition manual, p. 28)
- The disqualification time limit is stated only as "a certain time" with no number. (competition manual, pp. 27-28)
- Track-layout drawings, tunnel panel drawings and exact positions are images, not captured as text. (competition manual, pp. 17-20, 49-50)
- Practice-time text varies: "up to 20 minutes" once, "up to 20 minutes, twice" elsewhere. (competition manual, pp. 2-3)
- Vehicle hardware or sensor modification rules are not present in the pages read. (competition manual, pp. 24-25)
