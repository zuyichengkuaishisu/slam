# Debug: LIO-SAM IMU Indeterminate

Status: [OPEN]

## Symptom

`lio_sam_imuPreintegration` aborts with `gtsam::IndeterminantLinearSystemException`
near `Symbol: x5` after repeated low-feature map optimization warnings.
After adding IMU exception guards, `lio_sam_mapOptimization` later exited with
`exit code -11` after the same low-feature warnings.

## Hypotheses

- H1: Low feature counts produce weak/degenerate lidar odometry constraints, making the IMU graph underconstrained.
- H2: A bad or discontinuous correction timestamp is entering `odometryHandler` after bag loop/restart recovery.
- H3: IMU preintegration receives non-positive or abnormal `dt` after queue reset, corrupting the optimization factor.
- H4: The GTSAM optimizer throws on an ill-posed update, but the node has no exception boundary and exits instead of resetting.
- H5: Low-feature frames are still being inserted into mapOptimization keyframe/ISAM flow, corrupting or destabilizing the backend.

## Evidence

- Runtime log shows `Not enough features!` before crash.
- Runtime log shows `IndeterminantLinearSystemException` near pose variable `x5`.
- Runtime log shows `mapOptimization` segfault after repeated `Not enough features!` warnings and IMU large-velocity resets.

## Change

- Added exception boundaries around IMU graph initialization, fixed-lag graph reset, and normal graph update.
- On GTSAM optimization failure, clear IMU queues, clear graph values/factors, reset preintegrators, reset ISAM2, and wait for the next valid lidar correction.
- Changed `scan2MapOptimization()` to return success/failure. Once the map has initialized, low-feature frames are skipped before `saveKeyFramesAndFactor()`.
- Added exception boundaries around mapOptimization ISAM update, estimate calculation, and covariance calculation.

## Verification

- `colcon build --packages-select lio_sam --cmake-args -DCMAKE_BUILD_TYPE=Release` passed.
- Awaiting runtime verification: IMU and mapOptimization should warn/skip/reset instead of exiting.
