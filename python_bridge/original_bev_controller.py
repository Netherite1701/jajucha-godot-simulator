# ==========================================================================
# BEV 변환 -> 가우시안 블러링 -> 캐니 엣지 검출 (자주차 중앙 카메라)
# 교재(4부 2장 격자 차선 인식)의 블러링 + 캐니 과정을, 원본 ROI 대신 BEV 이미지에 적용
# 셀 하나에 넣고 실행. 멈출 때는 실행 중지 버튼.
#
# 좌표계: 원점 = 뒷바퀴 축 중심 바닥, x = 전방, y = 왼쪽 (단위 m)
# ==========================================================================
import math
import cv2
import numpy as np
import jchm
import time
from collections import deque


# ---------- 내부 파라미터 (k3 고정 결과) ----------
CAM_SIZE = (640, 400)
K = np.array([[310.70, 0.0, 309.52],
              [0.0, 309.58, 222.31],
              [0.0, 0.0, 1.0]])
DIST = np.array([0.084568, -0.072728, -0.000606, 0.004212, 0.0])

# ---------- 외부 파라미터 (X_NEAR 0.365 로 계산한 결과) ----------
RVEC = np.array([1.203605, -1.24103, 1.213053])
TVEC = np.array([0.005633, 0.101028, -0.13409])



# solvePnP 할 때 쓴 X_NEAR 와 실제 X_NEAR 가 다를 때만 보정 (지금은 같으므로 보정 0)
# (카메라 좌표 = R * 세계좌표 + t 에서, 세계좌표를 d 만큼 옮기면 t 에 R*d 가 더해짐)
X_NEAR_USED, X_NEAR_TRUE = 0.365, 0.365
R, _ = cv2.Rodrigues(RVEC)
TVEC = TVEC + R @ np.array([X_NEAR_USED - X_NEAR_TRUE, 0.0, 0.0])

# ---------- BEV 범위/해상도 (설계값, 바꿔도 캘리브레이션 다시 할 필요 없음) ----------
BEV_RES = 0.0025                     # 1px = 2.5mm (가로세로 동일)
BEV_X_MIN, BEV_X_MAX = 0.33, 0.70    # 전방 범위(m, 뒷축 기준)
BEV_Y_MIN, BEV_Y_MAX = -0.40, 0.40   # 좌우 범위(m, +가 왼쪽)
BEV_W = int(round((BEV_Y_MAX - BEV_Y_MIN) / BEV_RES))
BEV_H = int(round((BEV_X_MAX - BEV_X_MIN) / BEV_RES))


# ---------- 1) 왜곡 보정 맵 ----------
NEW_K, _ = cv2.getOptimalNewCameraMatrix(K, DIST, CAM_SIZE, 0, CAM_SIZE)
MAP1, MAP2 = cv2.initUndistortRectifyMap(K, DIST, None, NEW_K, CAM_SIZE, cv2.CV_16SC2)

# ---------- 2) BEV 행렬: 보정된 영상 -> BEV ----------
# 바닥(z=0) 점 (x, y) -> 영상:  NEW_K [r1 r2 t]
H_img_from_ground = NEW_K @ np.column_stack([R[:, 0], R[:, 1], TVEC])
# BEV 픽셀 (u, v) -> 바닥 (x, y):  x = X_MAX - v*RES,  y = Y_MAX - u*RES
A = np.array([[0.0, -BEV_RES, BEV_X_MAX],
              [-BEV_RES, 0.0, BEV_Y_MAX],
              [0.0, 0.0, 1.0]])
M_BEV = np.linalg.inv(H_img_from_ground @ A)

# ---------- 3) 유효영역 마스크 (카메라에 안 찍히는 검은 영역 제거용) ----------
VALID = cv2.warpPerspective(np.full((CAM_SIZE[1], CAM_SIZE[0]), 255, np.uint8),
                            M_BEV, (BEV_W, BEV_H))
VALID = cv2.erode(VALID, np.ones((9, 9), np.uint8))


#주행세팅
MAX_SPEED = 1.53/3
MIN_SPEED = 1.53/6
MAX_LD = 0.5
MIN_LD = 0.38
K_LD = 0.06
ACC_UP = 0.6     # 가속 한계 (m/s²), 천천히
ACC_DN = 1.5     # 감속 한계 (m/s²), 빠르게
REVERSE_SPEED = -4        # 후진 속도값 (약 0.2 m/s), 음수 = 후진
REVERSE_TIME = 0.5        # 후진 시간 (초) → 약 10cm
MAX_REVERSE = 3           # 연속 후진 최대 횟수 (넘으면 그냥 정지해 있음)

# 실패 판단: 최근 WIN 프레임 중 실패가 FAIL_LIMIT 번 이상이면 정지 + 후진
WIN = 10
FAIL_LIMIT = 5             # 절반 이상 실패하면 (번갈아 실패해도 잡힘)
SLOW_LIMIT = 3            # 최근 실패가 이 이상이면 성공 프레임이어도 최저 속도로



#print("# ↓ 주행 코드에 복사")
#print("M_BEV = np.array(" + np.array2string(M_BEV, separator=", ") + ")")
#print(f"BEV_W, BEV_H = {BEV_W}, {BEV_H}   # 1px = {BEV_RES*1000:.1f} mm")
#print(f"BEV_RES, BEV_X_MAX, BEV_Y_MAX = {BEV_RES}, {BEV_X_MAX}, {BEV_Y_MAX}")


def to_bev(img):
    """주행 코드에서 매 프레임 쓰는 함수: 왜곡 보정 -> BEV"""
    und = cv2.remap(img, MAP1, MAP2, cv2.INTER_LINEAR)
    return cv2.warpPerspective(und, M_BEV, (BEV_W, BEV_H), flags=cv2.INTER_LINEAR)


def bev_px_to_m(u, v):
    """BEV 픽셀 -> 차량 좌표(m). x 전방, y 왼쪽"""
    return BEV_X_MAX - v * BEV_RES, BEV_Y_MAX - u * BEV_RES


# ---------- 4) 엣지 검출 설정 (교재 예시 값에서 시작) ----------
BLUR_K = (3, 3)        # 가우시안 커널 크기 (홀수). 교재: (3, 3). 노이즈 많으면 (5, 5)
CANNY_LOW = 100        # 캐니 낮은 임계값. 교재: 100
CANNY_HIGH = 300       # 캐니 높은 임계값. 교재: 300
SHOW_GRID = True       # BEV 위에 10cm 격자 표시


def lane_edges(bev):
    """BEV 컬러 이미지 -> 엣지 이미지(흑백, 엣지 = 255)"""
    gray = cv2.cvtColor(bev, cv2.COLOR_BGR2GRAY)          # 1. 흑백 변환
    blurred = cv2.GaussianBlur(gray, BLUR_K, 0)           # 2. 노이즈 제거 (교재와 같은 함수)
    edges = cv2.Canny(blurred, CANNY_LOW, CANNY_HIGH)     # 3. 윤곽선 검출 (교재와 같은 함수)
    edges[VALID == 0] = 0                                 # 4. 카메라 시야 밖 테두리에서 생긴 가짜 엣지 제거
    return edges

def findpath(edges):
    HALF_W = 0.181/2
    SAFETY_MARGIN = 0.015
    R_PX = int(round((HALF_W + SAFETY_MARGIN)/BEV_RES))

    obst = cv2.morphologyEx(edges, cv2.MORPH_CLOSE, np.ones((7, 7), np.uint8))
    obst[VALID == 0] = 255

    distt = cv2.distanceTransform(cv2.bitwise_not(obst), cv2.DIST_L2, 5)
    free = distt > R_PX
    clear_m = distt * BEV_RES

    # 덩어리 번호 매기기
    n, labels = cv2.connectedComponents(free.astype(np.uint8), connectivity=8)

    # 시작점 찾기
    u_car = int(round(BEV_Y_MAX / BEV_RES))
    u0 = None
    for v0 in range(BEV_H - 3, BEV_H - 40, -1):
        cols = np.nonzero(free[v0])[0]
        if len(cols) > 0:
            u0 = cols[np.argmin(np.abs(cols - u_car))]
            break

    if u0 is None:
        return None                      # 실패: 바깥에서 감속 + 이전 조향 유지

    # 차와 연결된 덩어리만 남기기
    free = labels == labels[v0, u0]
    score = np.where(free, distt, 0)    # 차와 연결된 갈 수 있는 곳만 거리값, 나머지는 0

    best_u = np.argmax(score, axis=1)        # 줄마다 최대값 위치 (길이 BEV_H)
    best_val = score.max(axis=1)             # 줄마다 최대값 (0이면 갈 곳 없는 줄)

    ok = best_val > 0
    end = v0
    while end - 1 >= 0 and ok[end - 1]:
        end -= 1
    vs = np.arange(end, v0 + 1)
    us = best_u[vs]

    if len(vs) < 20:
        return None
    return vs, us, free


#def bycyclemodel(steer):
def curvature(a, b, x):
    dy = 2 * a * x + b
    return abs(2 * a) / (1 + dy**2) ** 1.5


def reverse_once():
    """정지 -> 조향 0으로 똑바로 짧게 후진 -> 정지 (뒤가 안 보이므로 꺾지 않음)"""
    jchm.control.set_motor(0, 0, 0)
    time.sleep(0.2)
    jchm.control.set_motor(0, 0, REVERSE_SPEED)
    time.sleep(REVERSE_TIME)
    jchm.control.set_motor(0, 0, 0)
    time.sleep(0.2)                  # 차체 흔들림이 가라앉은 뒤 다시 보기

# ---------- 5) 실시간 확인: 왼쪽 = BEV, 오른쪽 = 엣지 ----------
n = 0
t_prev = time.perf_counter()
speed_cmd = 0.0
history = deque(maxlen=WIN)     # 최근 프레임 실패 기록: True = 실패, False = 성공
reverse_count = 0
while True:
    img = jchm.camera.get_image("center")
    if img is None:
        continue
    now = time.perf_counter()
    dt = now - t_prev             # 직전 프레임부터 지금까지 걸린 시간 (초)
    t_prev = now
    dt = min(dt, 0.2)
    bev = to_bev(img)
    edges = lane_edges(bev)
    result = findpath(edges)

    # ----- 실패 판단 (두 경우를 한 곳에서 처리) -----
    fail_reason = None
    if result is None:
        fail_reason = "경로 못 찾음"
    else:
        vs, us, free = result
        xs = BEV_X_MAX - vs * BEV_RES
        ys = BEV_Y_MAX - us * BEV_RES
        if xs.max() < MIN_LD:
            fail_reason = f"경로 짧음 {xs.max():.3f}m"

    if fail_reason is not None:
        history.append(True)
        n_fail = sum(history)
        print(f"실패: {fail_reason}  (최근 {len(history)}프레임 중 {n_fail}번)")
        if n_fail >= FAIL_LIMIT:
            if reverse_count < MAX_REVERSE:
                print(f"후진 {reverse_count + 1}회")
                reverse_once()
                reverse_count += 1
            else:
                print("후진 횟수 초과 -> 정지")
                jchm.control.set_motor(0, 0, 0)
            speed_cmd = 0.0
            history.clear()                  # 후진 후 처음부터 다시 세기
            t_prev = time.perf_counter()     # 후진에 쓴 시간이 dt에 안 들어가게
        continue

    history.append(False)
    if len(history) == WIN and sum(history) == 0:
        reverse_count = 0                    # 최근 10프레임 내내 정상이면 후진 횟수 초기화
    a, b, c = np.polyfit(xs, ys, 2)     # 루프에서 한 번

    k_max = max(curvature(a, b, xs.min()), curvature(a, b, xs.max()))

    Ld = MAX_LD - K_LD * k_max
    Ld = np.clip(Ld, MIN_LD, min(MAX_LD, xs.max()))
    
    speed = np.interp(Ld, [MIN_LD, MAX_LD], [MIN_SPEED, MAX_SPEED])
    if sum(history) >= SLOW_LIMIT:           # 최근 실패가 잦으면 불안정 구간 → 최저 속도
        speed = MIN_SPEED
    
    d = np.hypot(xs, ys)
    i = np.argmin(np.abs(d - Ld))
    alpha = math.atan2(ys[i], xs[i])
    delta = math.atan(2 * 0.183 * math.sin(alpha) / Ld)
    servo = int(np.clip(-round(math.degrees(delta) / 2), -10, 10))
    dv = speed - speed_cmd
    dv = np.clip(dv, -ACC_DN * dt, ACC_UP * dt)
    speed_cmd = speed_cmd + dv
    
    jchm.control.set_motor(servo, servo, int(round(speed_cmd / 0.0513)))


    left = bev.copy()
    left[VALID == 0] = 0             # 화면 표시용으로만 시야 밖을 검게

    right = cv2.cvtColor(edges, cv2.COLOR_GRAY2BGR)
        # 아래 왼쪽: 주행 가능 영역 (흰색) + 경로 (빨강)
    free_img = cv2.cvtColor(free.astype(np.uint8) * 255, cv2.COLOR_GRAY2BGR)
    free_img[vs, us] = (0, 0, 255)

    # 아래 오른쪽: BEV 위에 경로 (빨강) + 목표점 (분홍 원)
    path_img = left.copy()
    path_img[vs, us] = (0, 0, 255)
    cv2.circle(path_img, (int(us[i]), int(vs[i])), 5, (255, 0, 255), 2)

    top = np.hstack([left, right])
    bottom = np.hstack([free_img, path_img])
    if n % 8 == 0:
        jchm.camera.show_image(np.vstack([top, bottom]), "center", quality=80)

    

    n += 1
    if n % 30 == 0:   # 가끔 엣지 픽셀 비율 출력 (임계값 조정 참고용)
        print(f"엣지 픽셀 비율: {100 * (edges > 0).mean():.2f}%")

