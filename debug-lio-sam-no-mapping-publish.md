# Debug Session: lio-sam-no-mapping-publish
- **Status**: [OPEN]
- **Issue**: `/lio_sam/mapping/cloud_registered` 与 `/lio_sam/mapping/odometry` 无发布；`ros2 topic hz` 提示 not published yet
- **Debug Server**: http://127.0.0.1:7777/event
- **Log File**: .dbg/trae-debug-log-lio-sam-no-mapping-publish.ndjson

## Reproduction Steps
1. `source ~/slam/lio_sam_ws/install/setup.bash`
2. `ros2 launch go2_lio_sam mid360_corridor_mapping.launch.py start_livox:=false use_sim_time:=true`
3. `ros2 bag play ~/slam/lio_sam_ws/rosbag/fastlio_no_loop_vm_02 --clock`
4. `ros2 topic hz /lio_sam/mapping/cloud_registered` → WARNING: not published yet

## Hypotheses & Verification
| ID | Hypothesis | Likelihood | Effort | Evidence |
|----|------------|------------|--------|----------|
| A | `lio_sam_mapOptimization` 节点未启动或已崩溃，发布者不存在 | High | Low | Pending |
| B | `laserCloudInfoHandler` 未收到 `/lio_sam/feature/cloud_info`（QoS/链路中断） | High | Low | Pending |
| C | 收到 cloud_info 但 `mappingProcessInterval` 门控导致长期不处理 | Med | Low | Pending |
| D | 进入处理流程但 `scan2MapOptimization` 失败（特征点<50等），未执行 publish | High | Med | Pending |
| E | `publishOdometry`/`publishFrames` 被调用但发布失败或帧为空提前返回 | Med | Med | Pending |

## Log Evidence
**2026-06-30 首轮快照（修复前）**
- `launch.log`: `lio_sam_mapOptimization` / `lio_sam_imuPreintegration` exit 127
- 原因: `libgtsam.so.4: cannot open shared object file`（未设置 `LD_LIBRARY_PATH=/usr/local/lib`）
- TRAE 日志仅有 hypothesis **B**（feature 发布），无 A/C/D/E → 建图节点未存活
- 快照节点列表无 `mapOptimization`

## Verification Conclusion
- **A: Confirmed** — 建图/IMU 节点因 GTSAM 动态库路径缺失而崩溃
- 通宵脚本已加入 `LD_LIBRARY_PATH=/usr/local/lib` 后重启

## Overnight 自动执行计划
- **脚本**: `scripts/overnight_lio_sam_debug.sh`
- **时长**: 默认 8h（`DURATION_HOURS=8`）
- **监测**: 每 300s 快照节点/话题/hz + 分析 TRAE 日志
- **输出**:
  - 运行日志: `logs/overnight-<timestamp>/overnight.log`
  - 最终报告: `.dbg/overnight-report-<timestamp>.md`
  - 分析: `logs/overnight-<timestamp>/analysis_final.md`
