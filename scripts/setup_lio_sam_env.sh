#!/usr/bin/env bash
# LIO-SAM 运行环境（GTSAM 在 /usr/local/lib）
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export LD_LIBRARY_PATH="/usr/local/lib:${LD_LIBRARY_PATH:-}"
