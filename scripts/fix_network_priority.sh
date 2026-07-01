#!/bin/bash
# 双网卡场景：eth0 连机器狗/雷达，wlan0 上网；且两者可能在同一网段 192.168.123.0/24
# 用法: sudo ./scripts/fix_network_priority.sh
#
# 问题1：eth0 抢默认路由 → 无法上网
# 问题2：wlan metric 更低 → 访问雷达/下位机走错网卡 → livox 无法启动

set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "请使用 root 权限运行: sudo $0"
  exit 1
fi

# 经 eth0 访问的设备（与 go2_slam MID360_config_test.json 一致，可按现场修改）
# 192.168.123.20 = Mid360  192.168.123.88 = 常见下位机/狗网口（以 arp 为准）
ROBOT_HOSTS=(
  "192.168.123.20"
  "192.168.123.88"
  "192.168.123.161"
)

ETH_CONN="Wired connection 1"
ROUTE_METRIC=50

echo "==> 当前路由（修改前）"
ip route show | grep -E '^default|192.168.123' || true
echo ""
for ip in "${ROBOT_HOSTS[@]}"; do
  echo "  route get ${ip}: $(ip route get "${ip}" 2>/dev/null | head -1 || echo 'N/A')"
done

# ---------- eth0：内网静态 IP，不设默认网关 ----------
for conn in "Wired connection 1" "Wired connection 2"; do
  if nmcli -t -f NAME connection show | grep -qxF "$conn"; then
    echo ""
    echo "==> 配置有线: $conn"
    nmcli connection modify "$conn" \
      ipv4.method manual \
      ipv4.addresses "192.168.123.18/24" \
      ipv4.never-default yes \
      ipv4.gateway "" \
      ipv4.route-metric 20000 \
      connection.autoconnect-priority 100 \
      connection.autoconnect yes
  fi
done

# 持久化：机器人/雷达 IP 强制走 eth0（/32 主机路由优先于 wlan 的 /24）
ROUTE_STR=""
for ip in "${ROBOT_HOSTS[@]}"; do
  if [[ -z "${ROUTE_STR}" ]]; then
    ROUTE_STR="${ip}/32 0.0.0.0 ${ROUTE_METRIC}"
  else
    ROUTE_STR+=", ${ip}/32 0.0.0.0 ${ROUTE_METRIC}"
  fi
done
echo ""
echo "==> eth0 主机路由: ${ROUTE_STR}"
nmcli connection modify "${ETH_CONN}" ipv4.routes "${ROUTE_STR}"

# ---------- wlan0：仅负责默认路由（上网）----------
WIFI_CONN=$(nmcli -g GENERAL.CONNECTION device show wlan0 2>/dev/null | head -1)
if [[ -n "${WIFI_CONN}" && "${WIFI_CONN}" != "--" ]]; then
  echo "==> 配置无线: ${WIFI_CONN}"
  nmcli connection modify "${WIFI_CONN}" \
    ipv4.never-default no \
    ipv4.route-metric 100 \
    connection.autoconnect-priority 50 \
    connection.autoconnect yes
fi

# 重新应用
nmcli device reapply eth0 2>/dev/null || {
  nmcli connection down "${ETH_CONN}" 2>/dev/null || true
  sleep 1
  nmcli connection up "${ETH_CONN}" || true
}
if [[ -n "${WIFI_CONN:-}" && "${WIFI_CONN}" != "--" ]]; then
  nmcli connection up "${WIFI_CONN}" 2>/dev/null || true
fi

ip route del default via 192.168.123.1 dev eth0 2>/dev/null || true

# 立即添加主机路由（NM 重连后有时需补一遍）
for ip in "${ROBOT_HOSTS[@]}"; do
  ip route replace "${ip}/32" dev eth0 metric "${ROUTE_METRIC}" 2>/dev/null || true
done

sleep 2
echo ""
echo "==> 当前路由（修改后）"
ip route show | grep -E '^default|192.168.123' || true
echo ""
echo "==> 下位机/雷达连通性"
OK=0
for ip in "${ROBOT_HOSTS[@]}"; do
  if ping -c 1 -W 2 "${ip}" >/dev/null 2>&1; then
    via=$(ip route get "${ip}" 2>/dev/null | sed -n 's/.*dev \([^ ]*\).*/\1/p' | head -1)
    echo "  OK  ${ip}  (dev ${via:-?})"
    OK=1
  else
    echo "  --  ${ip}  无响应（若未接设备可忽略）"
  fi
done

echo ""
if ping -c 1 -W 3 baidu.com >/dev/null 2>&1; then
  echo "OK: 外网可达 (baidu.com)"
else
  echo "WARN: 外网不可达，请检查 WiFi"
fi

if [[ "${OK}" -eq 0 ]]; then
  echo ""
  echo "提示: 请确认 eth0 已接狗/雷达，且本机 IP 为 192.168.123.18"
  echo "      查看 eth0 侧设备: ip neigh show dev eth0"
  exit 1
fi
