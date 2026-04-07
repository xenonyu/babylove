#!/usr/bin/env python3
"""
BabyLove 精品功能 Agent
从 ai_todo.json 逐一实现任务，全部完成后自动退出。
每个任务要求：精致设计 × 真实可用 × 完整测试。
"""

import anyio
import sys
import signal
import json
from datetime import datetime
from pathlib import Path

from claude_agent_sdk import (
    AssistantMessage,
    ClaudeAgentOptions,
    ClaudeSDKClient,
    ResultMessage,
    SystemMessage,
    TextBlock,
    ToolUseBlock,
)

# ─── 项目配置 ────────────────────────────────────────────────────────────────
PROJECT_DIR = "/Users/yaxinli/xym/babylove"
SIM_ID      = "8457B971-4286-457B-8AE0-8A6728C35CC5"
BUNDLE_ID   = "com.babylove.app"
AI_TODO     = Path(PROJECT_DIR) / "agent" / "ai_todo.json"
SKILL_LOG   = Path(PROJECT_DIR) / "agent" / "skill_log.json"

# ─── 优雅退出 ─────────────────────────────────────────────────────────────────
_shutdown = False

def _sigint(sig, frame):
    global _shutdown
    if _shutdown:
        print("\n\n💀 强制退出", flush=True)
        sys.exit(1)
    _shutdown = True
    print("\n\n⚠️  停止信号，等待本次任务结束…（再按一次强制退出）", flush=True)

signal.signal(signal.SIGINT, _sigint)

# ─── Todo 管理 ────────────────────────────────────────────────────────────────
def load_todo() -> list[dict]:
    try:
        return json.loads(AI_TODO.read_text(encoding="utf-8"))
    except Exception:
        return []

def next_task() -> dict | None:
    for t in load_todo():
        if t.get("status") == "pending":
            return t
    return None

def mark_done(task_id: int):
    tasks = load_todo()
    for t in tasks:
        if t["id"] == task_id:
            t["status"] = "done"
            t["done_at"] = datetime.now().strftime("%m/%d %H:%M")
    AI_TODO.write_text(json.dumps(tasks, ensure_ascii=False, indent=2), encoding="utf-8")

def print_todo_status():
    tasks = load_todo()
    done  = sum(1 for t in tasks if t["status"] == "done")
    total = len(tasks)
    bar   = "".join("█" if t["status"] == "done" else "░" for t in tasks)
    print(f"\n  📋 进度 [{bar}] {done}/{total}", flush=True)
    for t in tasks:
        icon = "✅" if t["status"] == "done" else "⬜"
        at   = f"  ({t.get('done_at','')})" if t["status"] == "done" else ""
        print(f"     {icon} #{t['id']} {t['title']}{at}", flush=True)

# ─── Skill 日志 ───────────────────────────────────────────────────────────────
def save_skill(description: str):
    skills: list[str] = []
    if SKILL_LOG.exists():
        try:
            skills = json.loads(SKILL_LOG.read_text())
        except Exception:
            pass
    entry = f"[{datetime.now().strftime('%m/%d %H:%M')}] {description}"
    skills = (skills + [entry])[-30:]
    SKILL_LOG.write_text(json.dumps(skills, ensure_ascii=False, indent=2))

# ─── 系统 Prompt ─────────────────────────────────────────────────────────────
SYSTEM_PROMPT = """你是一位有乔布斯式产品直觉的 iOS Swift 工程师，正在打磨 BabyLove 的两个精品功能。

## 黄金标准
- 精致 > 数量：宁可一个功能做到极致，也不做多个粗糙的功能
- 每一个 UI 细节都有存在理由
- 代码质量：Swift 6 并发安全、无强制解包、无 TODO

## 项目架构
Bundle ID: com.babylove.app | iOS 26.0+ | SwiftUI + CoreData + MVVM | Swift 6
路径: /Users/yaxinli/xym/babylove

关键文件:
  BabyLove/Design/DesignSystem.swift       — 品牌色/组件库（必须复用）
  BabyLove/ViewModels/TrackViewModel.swift  — 记录 CRUD
  BabyLove/Views/Home/HomeView.swift       — 今日仪表盘（主要修改位置）
  BabyLove/Views/Settings/SettingsView.swift
  BabyLove/Views/ContentView.swift

CoreData entities（只读，不修改 xcdatamodeld）:
  CDFeedingRecord: date(Date), duration(Double), amount(Double), note(String)
  CDSleepRecord:   startTime(Date), endTime(Date?), duration(Double), note(String)
  CDDiaperRecord:  date(Date), type(String "wet"/"dirty"/"both"), note(String)
  CDGrowthRecord:  date(Date), weight(Double), height(Double), headCircumference(Double)
  CDMilestone:     date(Date), title(String), note(String), emoji(String)

设计色系（严禁修改）:
  Primary  #FF7B6B  Background #FFF9F5
  Feeding  #4BAEE8  Sleep #9B8EC4  Diaper #55C189  Growth #F5A623

## 实现流程（每次严格执行）
1. git log --oneline -10  确认历史，避免重复
2. 仔细阅读所有涉及文件，理解现有代码风格
3. 完整实现，不留 TODO，复用 DesignSystem 组件
4. Localizable.strings 四语言同步（en / zh-Hans / ja / ko）
5. xcodegen generate && xcodebuild build ... 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
   必须 BUILD SUCCEEDED
6. Simulator 测试：boot → install → launch → screenshot → terminate
   截图存 agent/screenshots/，命名含功能名
7. git add -A && git commit

## 硬性约束
- 不引入 SPM 依赖
- 不修改 xcdatamodeld
- BUILD SUCCEEDED 才能提交
- 每次只做一个任务
"""

# ─── 任务 Prompt ─────────────────────────────────────────────────────────────
TASK_PROMPT = """实现以下功能（任务 #{task_id}/{total}）：

## {title}

{desc}

---

严格按系统提示的「实现流程」执行，重点：
- 先读 HomeView.swift、DesignSystem.swift、TrackViewModel.swift，理解现有代码风格后再动手
- UI 要与现有设计语言完全一致（字体/圆角/阴影/色系），像是原本就有的功能
- 四语言本地化不能省略
- Simulator 截图必须包含新功能可见的画面
- commit message 格式：feat: <英文简述>
"""

# ─── 格式化工具调用 ──────────────────────────────────────────────────────────
def fmt_tool(block: ToolUseBlock) -> str:
    name = block.name
    inp  = block.input or {}
    if name == "Bash":
        cmd = str(inp.get("command", "")).strip().replace("\n", " ")[:120]
        return f"🔧 Bash   │ {cmd}"
    elif name == "Read":
        return f"📖 Read   │ {inp.get('file_path', '')}"
    elif name == "Edit":
        return f"✏️  Edit   │ {inp.get('file_path', '')}"
    elif name == "Write":
        return f"📝 Write  │ {inp.get('file_path', '')}"
    elif name == "Glob":
        return f"🔍 Glob   │ {inp.get('pattern', '')}"
    elif name == "Grep":
        return f"🔍 Grep   │ {inp.get('pattern', '')}"
    return f"🛠  {name}"

# ─── 单次任务执行 ─────────────────────────────────────────────────────────────
async def run_task(task: dict, total: int, total_cost: float) -> float:
    ts = datetime.now().strftime("%H:%M:%S")

    # desc 里换行需要保留，不做 replace
    prompt = TASK_PROMPT.format(
        task_id=task["id"],
        total=total,
        title=task["title"],
        desc=task["desc"],
    )

    print(f"\n{'═' * 66}")
    print(f"  [{ts}] 任务 #{task['id']}/{total}: {task['title']}")
    print(f"{'═' * 66}", flush=True)

    options = ClaudeAgentOptions(
        cwd=PROJECT_DIR,
        allowed_tools=["Read", "Write", "Edit", "Bash", "Glob", "Grep"],
        permission_mode="bypassPermissions",
        system_prompt=SYSTEM_PROMPT,
        max_turns=80,
        model="claude-opus-4-6",
    )

    cost = 0.0

    try:
        async with ClaudeSDKClient(options=options) as client:
            await client.query(prompt)

            async for message in client.receive_response():
                if _shutdown:
                    break

                if isinstance(message, SystemMessage) and message.subtype == "init":
                    sid = message.data.get("session_id", "")[:8]
                    print(f"  Session: {sid}…", flush=True)

                elif isinstance(message, AssistantMessage):
                    for block in message.content:
                        if isinstance(block, TextBlock) and block.text.strip():
                            text = block.text.strip().replace("\n", " ")
                            print(f"  💭 {text[:140]}", flush=True)
                        elif isinstance(block, ToolUseBlock):
                            print(f"  {fmt_tool(block)}", flush=True)

                elif isinstance(message, ResultMessage):
                    cost           = message.total_cost_usd or 0.0
                    turns          = message.num_turns
                    usage          = message.usage or {}
                    inp_tok        = usage.get("input_tokens", 0)
                    out_tok        = usage.get("output_tokens", 0)
                    result_summary = (message.result or "").strip()

                    print(f"\n  ✓ 完成  💰 ${cost:.4f}  🔄 {turns}轮  📊 {inp_tok:,}in/{out_tok:,}out", flush=True)
                    if result_summary:
                        print(f"  {result_summary[:300]}", flush=True)
                        save_skill(f"[#{task['id']}] {task['title']}: {result_summary[:60]}")

                    return cost

    except Exception as e:
        if not _shutdown:
            print(f"\n  ✗ 出错: {type(e).__name__}: {e}", flush=True)

    return cost

# ─── 主循环 ──────────────────────────────────────────────────────────────────
async def main():
    interval = 5
    if len(sys.argv) > 1:
        try:
            interval = int(sys.argv[1])
        except ValueError:
            pass

    all_tasks = load_todo()
    total     = len(all_tasks)

    print("🍼 BabyLove 精品功能 Agent  (Ctrl+C 停止)")
    print(f"   项目:  {PROJECT_DIR}")
    print(f"   模型:  claude-opus-4-6")
    print(f"   任务:  {total} 个，全部完成后自动退出\n")
    print_todo_status()

    total_cost = 0.0
    errors     = 0

    while not _shutdown:
        task = next_task()
        if task is None:
            print(f"\n🎉 全部任务完成！总花费: ${total_cost:.4f}")
            print_todo_status()
            break

        try:
            cost = await run_task(task, total, total_cost)
            total_cost += cost
            errors = 0

            if not _shutdown:
                mark_done(task["id"])
                print(f"\n  ✅ #{task['id']} {task['title']} 已完成")
                print_todo_status()

        except Exception as e:
            errors += 1
            print(f"  ⚠️  错误 ({errors}/3): {e}", flush=True)
            if errors >= 3:
                print("  连续 3 次错误，停止", flush=True)
                break

        if _shutdown:
            break

        next_t = next_task()
        if next_t is None:
            print(f"\n🎉 全部任务完成！总花费: ${total_cost:.4f}")
            print_todo_status()
            break

        print(f"\n  ⏳ {interval}s 后开始: #{next_t['id']} {next_t['title']}  [累计: ${total_cost:.4f}]", flush=True)
        for _ in range(interval):
            if _shutdown:
                break
            await anyio.sleep(1)

    if _shutdown:
        print(f"\n👋 已停止  总花费: ${total_cost:.4f}")


if __name__ == "__main__":
    anyio.run(main)
