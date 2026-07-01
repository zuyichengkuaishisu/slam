# LIO-SAM Mid360 长走廊建图（ROS2 Foxy）

基于 [UV-Lab/LIO-SAM_MID360_ROS2](https://github.com/UV-Lab/LIO-SAM_MID360_ROS2)，适配 Unitree Go2 + Livox Mid360，与 `~/go2_slam` 雷达启动方式一致。

## 依赖

- ROS2 Foxy
- GTSAM 4（已安装在 `/usr/local`）
- `livox_ros_driver2`：通过符号链接使用 `~/go2_slam` 中已编译驱动

## 编译

```bash
source /opt/ros/foxy/setup.bash
source ~/go2_slam/install/setup.bash   # livox 消息与驱动

cd ~/lio_sam_ws
# Jetson 内存有限：勿并行编译 lio_sam，用脚本或下面分步命令
./scripts/build_lowmem.sh

source install/setup.bash
```

分步编译（若仍被 `Killed` / OOM，先 `sudo swapon` 加大 swap 或关闭 RViz/浏览器）：

```bash
export MAKEFLAGS="-j1" CMAKE_BUILD_PARALLEL_LEVEL=1
colcon build --packages-select lio_sam --parallel-workers 1 --executor sequential \
  --cmake-args -DCMAKE_BUILD_TYPE=Release
colcon build --packages-select go2_lio_sam --parallel-workers 1
```

## 启动建图

**一键（雷达 + LIO-SAM + RViz）：**

```bash
source /opt/ros/foxy/setup.bash
source ~/go2_slam/install/setup.bash
source ~/lio_sam_ws/install/setup.bash

ros2 launch go2_lio_sam mid360_corridor_mapping.launch.py
```

**分步启动（与 go2_slam 共用同一套雷达）：**

go2_slam 的 `msg_MID360_launch.py` 使用 **PointCloud2**（`xfer_format=0`），话题 `/livox/lidar`。本仓库已对齐该格式。

**QoS**：Livox 驱动与 LIO-SAM 均使用 `SensorDataQoS`（BEST_EFFORT）。若改过 `go2_slam` 里的 `livox_ros_driver2`，需重新编译驱动：

```bash
cd ~/go2_slam && colcon build --packages-select livox_ros_driver2 --parallel-workers 1
```

```bash
# 终端1：go2_slam 雷达（或本仓库等效 launch）
source ~/go2_slam/install/setup.bash
ros2 launch livox_ros_driver2 msg_MID360_launch.py

# 终端2：仅 LIO-SAM（不重复起雷达）
source ~/lio_sam_ws/install/setup.bash
ros2 launch go2_lio_sam mid360_corridor_mapping.launch.py start_livox:=false
```

## 保存地图

```bash
ros2 service call /lio_sam/save_map lio_sam/srv/SaveMap "{resolution: 0.2, destination: /home/unitree/maps/lio_sam/}"
```

PCD 默认目录：`/home/unitree/maps/lio_sam/`

## 长走廊参数说明

`go2_lio_sam/config/params_mid360_corridor.yaml` 已启用：

- **回环检测** `loopClosureEnableFlag: true`（往返走廊可抑制漂移）
- 更密关键帧、略小体素，适合室内走廊
- Mid360 内置 IMU 外参为单位阵（与 FAST-LIO `mid360_test_go2.yaml` 一致）
- **机体安装角（方案 A）**  
  - **URDF**：`robot_mid360.urdf` → `lidar_joint` 俯仰 30°（`base_link`→`livox_frame`，TF/RViz）  
  - **驱动**：`~/go2_slam/.../MID360_config_test.json` → `extrinsic_parameter.pitch: 30.0`（点云在驱动内补偿，度）  
  - **LIO-SAM**：`lidarMountPitch: 0`，`extrinsicRot/RPY` 单位阵（机内 IMU↔雷达，不重复补偿）  
  - 改驱动配置后需：`cd ~/go2_slam && colcon build --packages-select livox_ros_driver2`，再 `source install/setup.bash`

RViz 使用 `go2_lio_sam/config/lio_sam_corridor.rviz`，已预配置：

| 显示项 | 话题 | 说明 |
|--------|------|------|
| **Map_Global** | `/lio_sam/mapping/map_global` | 回环校正后的全局地图（走廊建图主视图） |
| **Current_Scan** | `/lio_sam/mapping/cloud_registered` | 当前帧配准点云 |
| **Trajectory** | `/lio_sam/mapping/path` | 行驶轨迹 |
| **Loop_Closure** | `/lio_sam/mapping/loop_closure_constraints` | 回环约束连线 |
| **Odometry** | `/lio_sam/mapping/odometry` | 当前位姿 |

单独打开 RViz：`rviz2 -d $(ros2 pkg prefix go2_lio_sam)/share/go2_lio_sam/config/lio_sam_corridor.rviz`

## 网络

多网卡时请先执行：

```bash
sudo ~/lio_sam_ws/scripts/fix_network_priority.sh
```

详见 `docs/NETWORK_FIX.md`。
