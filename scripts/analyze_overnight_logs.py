#!/usr/bin/env python3
"""分析通宵调试日志，输出假设判定报告。"""
import json
import sys
from collections import Counter
from pathlib import Path


def load_events(path: Path):
    if not path.is_file():
        return []
    events = []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return events


def main():
    log_path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".dbg/trae-debug-log-lio-sam-no-mapping-publish.ndjson")
    out_path = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(".dbg/overnight-analysis.md")

    events = load_events(log_path)
    by_hyp = Counter(e.get("hypothesisId", "?") for e in events)
    by_loc = Counter(e.get("location", "?") for e in events)

    lines = [
        "# Overnight 日志分析",
        "",
        f"- 日志文件: `{log_path}`",
        f"- 事件总数: **{len(events)}**",
        "",
        "## 假设计数",
        "",
        "| ID | 事件数 | 初步判定 |",
        "|----|--------|----------|",
    ]

    verdict = {
        "A": ("mapOptimization 节点已构造", "未看到节点构造日志"),
        "B": ("特征 cloud_info 有发布/建图有接收", "链路中断"),
        "C": ("mapping process tick 有触发", "处理门控未进入"),
        "D": ("scan2MapOptimization 有执行记录", "优化未执行"),
        "E": ("odometry/cloud_registered 有发布记录", "发布路径未走到"),
    }
    for hid in ["A", "B", "C", "D", "E"]:
        n = by_hyp.get(hid, 0)
        ok, fail = verdict[hid]
        status = ok if n > 0 else fail
        lines.append(f"| {hid} | {n} | {status} |")

    lines += ["", "## 热点位置", ""]
    for loc, n in by_loc.most_common(15):
        lines.append(f"- `{loc}`: {n}")

    if events:
        lines += ["", "## 最近 10 条事件", "", "```json"]
        for e in events[-10:]:
            lines.append(json.dumps(e, ensure_ascii=False))
        lines.append("```")

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(out_path.read_text(encoding="utf-8"))


if __name__ == "__main__":
    main()
