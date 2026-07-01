#!/usr/bin/env bash
# 通宵自动复现 LIO-SAM 建图发布问题，循环播 bag + 定时采样 + TRAE 日志分析
set -euo pipefail

WS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SESSION_ID="lio-sam-no-mapping-publish"
BAG_DIR="${BAG_DIR:-$WS/rosbag/fastlio_no_loop_vm_02}"
DURATION_HOURS="${DURATION_HOURS:-8}"
MONITOR_INTERVAL="${MONITOR_INTERVAL:-300}"
BAG_LOOP_PAUSE="${BAG_LOOP_PAUSE:-3}"

RUN_ID="$(date +%Y%m%d_%H%M%S)"
LOG_DIR="$WS/logs/overnight-$RUN_ID"
PID_DIR="$WS/.dbg/overnight-$RUN_ID"
mkdir -p "$LOG_DIR" "$PID_DIR" "$WS/.dbg"

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export LD_LIBRARY_PATH="/usr/local/lib:${LD_LIBRARY_PATH:-}"

log() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG_DIR/overnight.log"; }

cleanup() {
  log "=== 清理进程 ==="
  [[ -f "$PID_DIR/launch.pid" ]] && kill "$(cat "$PID_DIR/launch.pid")" 2>/dev/null || true
  [[ -f "$PID_DIR/bag.pid" ]] && kill "$(cat "$PID_DIR/bag.pid")" 2>/dev/null || true
  pkill -f "ros2 bag play.*fastlio_no_loop_vm_02" 2>/dev/null || true
  pkill -f "mid360_corridor_mapping.launch.py" 2>/dev/null || true
  sleep 2
}
trap cleanup EXIT

log "=== Overnight 计划开始 ==="
log "工作区: $WS"
log "时长: ${DURATION_HOURS}h | 监测间隔: ${MONITOR_INTERVAL}s | bag: $BAG_DIR"
log "日志目录: $LOG_DIR"

# Debug Server
if ! curl -sf "http://127.0.0.1:7777/health" >/dev/null 2>&1; then
  log "启动 Debug Server..."
  python3 /home/wzy/.codex/skills/TRAE-debugger/tools/debug-server/python/debug-server.py \
    --session "$SESSION_ID" --outdir "$WS/.dbg" --idle 0 \
    >>"$LOG_DIR/debug-server.log" 2>&1 &
  echo $! >"$PID_DIR/debug-server.pid"
  sleep 2
fi

set +u
source /opt/ros/humble/setup.bash
source "$WS/install/setup.bash"
set -u

# 启动 LIO-SAM
log "启动 LIO-SAM launch..."
ros2 launch go2_lio_sam mid360_corridor_mapping.launch.py \
  start_livox:=false use_sim_time:=true use_livox_bridge:=true rviz:=false \
  >>"$LOG_DIR/launch.log" 2>&1 &
echo $! >"$PID_DIR/launch.pid"

log "等待节点就绪 (最多 60s)..."
for i in $(seq 1 60); do
  if ros2 node list 2>/dev/null | grep -q mapOptimization; then
    log "mapOptimization 节点已上线 (${i}s)"
    break
  fi
  sleep 1
done

if ! ros2 node list 2>/dev/null | grep -q mapOptimization; then
  log "ERROR: mapOptimization 未启动，见 $LOG_DIR/launch.log"
fi

END_TS=$(( $(date +%s) + DURATION_HOURS * 3600 ))
CYCLE=0

snapshot() {
  local tag="$1"
  local f="$LOG_DIR/snapshot_${tag}.txt"
  {
    echo "=== $tag $(date -Iseconds) ==="
    echo "--- nodes ---"
    ros2 node list 2>/dev/null || true
    echo "--- mapping topics ---"
    ros2 topic list 2>/dev/null | grep lio_sam/mapping || true
    echo "--- publisher count ---"
    ros2 topic info /lio_sam/mapping/cloud_registered -v 2>/dev/null | grep -E "Publisher count|Node name" || true
    ros2 topic info /lio_sam/mapping/odometry -v 2>/dev/null | grep -E "Publisher count|Node name" || true
    echo "--- hz sample (5s) ---"
    timeout 5 ros2 topic hz /lio_sam/mapping/cloud_registered 2>&1 || echo "no cloud_registered hz"
    timeout 5 ros2 topic hz /lio_sam/mapping/odometry 2>&1 || echo "no odometry hz"
    echo "--- debug server health ---"
    curl -sf "http://127.0.0.1:7777/health" 2>/dev/null || echo "debug server unreachable"
    echo "--- debug log tail ---"
    curl -sf "http://127.0.0.1:7777/logs?last=5" 2>/dev/null || true
  } >"$f" 2>&1
  log "快照已写: $f"
}

snapshot "start"

LAST_MONITOR=$(date +%s)

while [[ $(date +%s) -lt $END_TS ]]; do
  CYCLE=$((CYCLE + 1))
  log "--- Bag 循环 #$CYCLE 开始 ---"
  ros2 bag play "$BAG_DIR" --clock --rate 1.0 \
    >>"$LOG_DIR/bag_cycle_${CYCLE}.log" 2>&1 &
  echo $! >"$PID_DIR/bag.pid"
  wait "$(cat "$PID_DIR/bag.pid")" || log "WARN: bag 循环 #$CYCLE 异常退出"
  rm -f "$PID_DIR/bag.pid"
  sleep "$BAG_LOOP_PAUSE"

  NOW=$(date +%s)
  if (( NOW - LAST_MONITOR >= MONITOR_INTERVAL )); then
    snapshot "cycle_${CYCLE}"
    LAST_MONITOR=$NOW
    python3 "$WS/scripts/analyze_overnight_logs.py" \
      "$WS/.dbg/trae-debug-log-${SESSION_ID}.ndjson" \
      "$LOG_DIR/analysis_latest.md" >>"$LOG_DIR/overnight.log" 2>&1 || true
  fi

  if (( CYCLE % 20 == 0 )); then
    log "进度: 已完成 $CYCLE 轮 bag，剩余约 $(( (END_TS - NOW) / 3600 ))h"
  fi
done

log "=== 通宵运行结束，生成最终报告 ==="
snapshot "final"
python3 "$WS/scripts/analyze_overnight_logs.py" \
  "$WS/.dbg/trae-debug-log-${SESSION_ID}.ndjson" \
  "$LOG_DIR/analysis_final.md" | tee -a "$LOG_DIR/overnight.log"

{
  echo "# Overnight 执行报告"
  echo ""
  echo "- 开始: $RUN_ID"
  echo "- 结束: $(date -Iseconds)"
  echo "- Bag 循环次数: $CYCLE"
  echo "- 日志目录: \`$LOG_DIR\`"
  echo "- TRAE 日志: \`.dbg/trae-debug-log-${SESSION_ID}.ndjson\`"
  echo ""
  echo "## 最终分析"
  echo ""
  cat "$LOG_DIR/analysis_final.md" 2>/dev/null || echo "(无分析输出)"
  echo ""
  echo "## 最终快照"
  echo ""
  echo '```'
  tail -40 "$LOG_DIR/snapshot_final.txt" 2>/dev/null || true
  echo '```'
} >"$WS/.dbg/overnight-report-${RUN_ID}.md"

log "报告: $WS/.dbg/overnight-report-${RUN_ID}.md"
log "=== 全部完成 ==="

log "=== 10 秒后关机 ==="
sleep 10
if command -v shutdown >/dev/null 2>&1; then
  log "执行: sudo shutdown -h now"
  echo '203812' | sudo -S shutdown -h now "overnight LIO-SAM debug finished" || log "WARN: 关机命令失败，请手动关机"
else
  log "WARN: 未找到 shutdown 命令，请手动关机"
fi
