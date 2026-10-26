# Camera blackout investigation

The first explanation in `.cache/planning/fullcamera/RECONCILIATION.md`
attributed the dark frames to the road leaving the field of view. A controlled
reproduction contradicted that explanation.

At the saved checkpoint-07 pose (x=3.738 m, z=2.76651 m, yaw=-89.63914 deg),
a stationary capture showed a clear road. Moving the vehicle 55 mm forward
without updating the sensor camera produced the same large dark rectangle
seen during the failed run. Hiding the vehicle removed the rectangle while
leaving the camera and course unchanged. The paired images are preserved as
`.cache/planning/camera_diagnosis/lagging_camera.png` and
`lagging_camera_no_vehicle.png`.

The chassis meshes still used render layer 1 even though the sensor cameras
excluded layer 2. Physics collision layers do not configure mesh rendering
layers. Cameras below SubViewport nodes also needed explicit world transforms;
updating them only during 10 Hz sensor capture let the 40 Hz vehicle move
ahead between captures.

The correction assigns vehicle geometry to render layer 2, excludes that layer
from the sensor cameras, and synchronizes camera transforms after every
physics movement. The provisional body mesh therefore cannot obscure its own
simulated optical sensors.

The investigation also found that camera `h_offset` and `v_offset` were being
used as principal-point adjustments. Those properties translate the camera
in space ([Godot Camera3D documentation](https://docs.godotengine.org/en/stable/classes/class_camera3d.html)).
An off-axis frustum now supplies the optical-center shift, and a sensor-output
shader applies the supplied radial/tangential lens model. This lets the user's
OpenCV undistortion receive a simulated raw optical image.

Ramp lane panels are lifted by their 3 mm foamboard thickness above the
supporting wedge so coplanar surfaces cannot alternate in the depth buffer.

Continuous three-camera captures, commands, and trajectory data are saved
per attempt under `.cache/planning/fullcamera/run_<timestamp>/`. The lap
runner reports the actual result in `result.json` and requires the whole
ordered circuit before reporting success.
