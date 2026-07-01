#!/usr/bin/env bash
# 一键启动 RViz2 查看 LIO-SAM 建图（全局地图 / 当前帧 / 轨迹 / 回环）
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# 避免 conda Python 干扰 ROS
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# ROS setup.bash 会引用未预先定义的变量，source 期间关闭 nounset
set +u
source /opt/ros/humble/setup.bash
if [[ -f "${WS_DIR}/install/setup.bash" ]]; then
  source "${WS_DIR}/install/setup.bash"
else
  echo "[view_mapping_rviz] 警告: 未找到 install/setup.bash，请先 colcon build" >&2
fi
set -u

PKG_SHARE="$(ros2 pkg prefix go2_lio_sam)/share/go2_lio_sam"
RVIZ_CONFIG="${PKG_SHARE}/config/lio_sam_mapping.rviz"

if [[ ! -f "${RVIZ_CONFIG}" ]]; then
  echo "[view_mapping_rviz] 错误: 找不到配置 ${RVIZ_CONFIG}" >&2
  echo "  请执行: cd ${WS_DIR} && colcon build --packages-select go2_lio_sam" >&2
  exit 1
fi

echo "=== LIO-SAM 建图可视化 ==="
echo "配置文件: ${RVIZ_CONFIG}"
echo "Fixed Frame: map"
echo ""
echo "主要话题:"
echo "  全局地图   /lio_sam/mapping/map_global"
echo "  当前配准帧 /lio_sam/mapping/cloud_registered"
echo "  轨迹       /lio_sam/mapping/path"
echo "  里程计     /lio_sam/mapping/odometry"
echo "  回环约束   /lio_sam/mapping/loop_closure_constraints"
echo "  雷达输入   /livox/lidar_pc2 (桥接后)"
echo ""

# 可选：检查 SLAM 是否在跑
if command -v timeout >/dev/null 2>&1; then
  if timeout 2 ros2 topic list 2>/dev/null | grep -q '/lio_sam/mapping/map_global'; then
    echo "[状态] 检测到 LIO-SAM 建图话题，可正常显示"
  else
    echo "[状态] 尚未检测到 LIO-SAM 话题，请先启动建图或播 bag"
    echo "  建图: ros2 launch go2_lio_sam mid360_corridor_mapping.launch.py start_livox:=false"
    echo "  播包: ros2 bag play <bag_dir> --clock"
  fi
  echo ""
fi

exec rviz2 -d "${RVIZ_CONFIG}" "$@"
