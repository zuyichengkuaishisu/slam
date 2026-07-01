#!/usr/bin/env bash
# Jetson / 低内存机器编译 LIO-SAM（避免 OOM / cc1plus killed）
set -e
cd "$(dirname "$0")/.."

source /opt/ros/foxy/setup.bash

export MAKEFLAGS="-j1"
export CMAKE_BUILD_PARALLEL_LEVEL=1
export NINJAFLAGS="-j1"

echo "=== [1/2] lio_sam (最吃内存，单线程 Release) ==="
colcon build \
  --packages-select lio_sam \
  --parallel-workers 1 \
  --executor sequential \
  --cmake-args -DCMAKE_BUILD_TYPE=Release

echo "=== [2/2] go2_lio_sam ==="
colcon build \
  --packages-select go2_lio_sam \
  --parallel-workers 1 \
  --executor sequential

echo "=== 完成 ==="
echo "source $(pwd)/install/setup.bash"
