#!/usr/bin/env bash
# 等待通宵任务结束后自动关机（用于已启动、未含关机逻辑的旧任务）
set -euo pipefail
WS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$WS/.dbg/shutdown-watcher.log"
TARGET_PID="${1:-}"

log() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG"; }

if [[ -z "$TARGET_PID" ]]; then
  TARGET_PID=$(pgrep -f "bash scripts/overnight_lio_sam_debug.sh" | head -1 || true)
fi

if [[ -z "$TARGET_PID" ]]; then
  log "未找到通宵任务 PID，退出"
  exit 1
fi

log "监视通宵任务 PID=$TARGET_PID，结束后将关机"
while kill -0 "$TARGET_PID" 2>/dev/null; do
  sleep 60
done

log "通宵任务已结束，10 秒后关机"
sleep 10
echo '203812' | sudo -S shutdown -h now "overnight LIO-SAM debug finished (watcher)" \
  || log "WARN: 关机失败"
