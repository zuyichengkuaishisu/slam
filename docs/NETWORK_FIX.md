# 双网卡网络配置（eth0 下位机 + wlan0 上网）

## 现象

| 现象 | 原因 |
|------|------|
| 能 ping 百度，但 **Livox/雷达起不来** | 雷达 IP 的包从 **wlan0** 发出，没走 eth0 |
| `ping -I eth0 192.168.123.20` 通，直接 `ping` 不通 | 同上 |
| 以前能上网，改完后狗连不上 | 只做了「wlan 优先」，没给雷达 IP 加 **eth0 主机路由** |

## 网段冲突（常见）

办公室 WiFi 与机器狗网段**都是** `192.168.123.0/24` 时：

- **eth0**：`192.168.123.18` → 狗 / Mid360（`MID360_config_test.json` 里 `host_net_info`）
- **wlan0**：`192.168.123.10` → 办公室路由器
- **雷达**：`192.168.123.20`（配置见 `go2_slam/.../MID360_config_test.json`）

系统对同一网段只选 **metric 最小** 的出口，wlan(100) 优于 eth0(20000)，所以访问 `.20` 会走错网卡。

## 一键修复

```bash
cd ~/lio_sam_ws
sudo ./scripts/fix_network_priority.sh
```

脚本会：

1. **wlan0**：默认路由，负责上网（metric 100）
2. **eth0**：`192.168.123.18`，不设默认网关
3. **主机路由**：`192.168.123.20/32`、`192.168.123.88/32` 等 **强制走 eth0**（metric 50）

## 自检

```bash
# 应显示 dev eth0
ip route get 192.168.123.20

ping -c 2 192.168.123.20
ping -c 2 baidu.com

# 查看 eth0 侧已发现的设备
ip neigh show dev eth0
```

## 下位机 IP 不是 .88 时

编辑 `scripts/fix_network_priority.sh` 中 `ROBOT_HOSTS` 数组，加入实际 IP，或根据 `ip neigh show dev eth0` 填写后重新运行脚本。

## Livox 配置核对

`go2_slam/src/livox_ros_driver2/config/MID360_config_test.json` 中：

- `host_net_info.*_ip` 必须为 **eth0 地址** `192.168.123.18`
- `lidar_configs[0].ip` 为雷达 IP（当前 `192.168.123.20`）

修改 JSON 后需重启 livox 驱动。
