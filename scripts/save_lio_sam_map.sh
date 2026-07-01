#!/usr/bin/env bash
# Save the current LIO-SAM map through /lio_sam/save_map.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

RESOLUTION="${1:-0.2}"
DESTINATION="${2:-/maps/lio_sam/$(date +%Y%m%d_%H%M%S)}"

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export LD_LIBRARY_PATH="/usr/local/lib:${LD_LIBRARY_PATH:-}"

set +u
source /opt/ros/humble/setup.bash
if [[ -f "${WS_DIR}/install/setup.bash" ]]; then
  source "${WS_DIR}/install/setup.bash"
else
  echo "[save_lio_sam_map] 错误: 未找到 ${WS_DIR}/install/setup.bash，请先 colcon build" >&2
  exit 1
fi
set -u

if [[ "${DESTINATION}" == "${HOME}/"* ]]; then
  DESTINATION="/${DESTINATION#"${HOME}/"}"
fi

if [[ "${DESTINATION}" != /* ]]; then
  echo "[save_lio_sam_map] 错误: destination 必须以 / 开头，且表示相对 HOME 的路径" >&2
  echo "  示例: /maps/lio_sam/test_01 会保存到 ${HOME}/maps/lio_sam/test_01" >&2
  exit 1
fi

echo "=== LIO-SAM 保存地图 ==="
echo "服务: /lio_sam/save_map"
echo "分辨率: ${RESOLUTION}"
echo "目标: ${HOME}${DESTINATION}"

if ! timeout 5 ros2 service list 2>/dev/null | grep -qx '/lio_sam/save_map'; then
  echo "[save_lio_sam_map] 错误: 未检测到 /lio_sam/save_map" >&2
  echo "  请先启动建图，并等 /lio_sam/mapping/odometry 有数据后再保存。" >&2
  exit 1
fi

ros2 service call /lio_sam/save_map lio_sam/srv/SaveMap \
  "{resolution: ${RESOLUTION}, destination: '${DESTINATION}'}"

echo ""
echo "如果 success: true，PCD 文件已保存到: ${HOME}${DESTINATION}"
