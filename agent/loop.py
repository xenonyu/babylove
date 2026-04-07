#!/usr/bin/env python3
"""
BabyLove AI 功能迭代 Agent
每次从 ai_todo.json 取一个 pending 任务 → 实现 → 标记 done → 全部完成后退出
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
SIM_ID      = "8457B971-4286-457B-8AE0-8A6728C35CC5"   # iPhone 17 / iOS 26.2
BUNDLE_ID   = "com.babylove.app"
SCHEME      = "BabyLove"
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
    print("\n\n⚠️  收到停止信号，等待本次任务结束…（再按一次强制退出）", flush=True)

signal.signal(signal.SIGINT, _sigint)

# ─── Todo 管理 ────────────────────────────────────────────────────────────────
def load_todo() -> list[dict]:
    try:
        return json.loads(AI_TODO.read_text(encoding="utf-8"))
    except Exception:
        return []

def next_task() -> dict | None:
    """返回第一个 pending 任务，无则返回 None"""
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
    print(f"  📋 进度 [{bar}] {done}/{total}", flush=True)
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
SYSTEM_PROMPT = """你是一位有乔布斯式产品直觉的 iOS Swift 工程师，负责为 BabyLove 实现 AI 智能功能。

## 产品核心理念
BabyLove = 极简记录 × 深度洞察 × 永久珍藏
- 全球化：中/英/日/韩语言，公制/英制，WHO 生长曲线

## 架构
Bundle ID: com.babylove.app | iOS 26.0+ | SwiftUI + CoreData + MVVM | Swift 6
项目路径: /Users/yaxinli/xym/babylove

核心文件:
  BabyLove/Design/DesignSystem.swift       — 品牌色/组件
  BabyLove/ViewModels/TrackViewModel.swift  — 记录 CRUD
  BabyLove/Views/Home/HomeView.swift       — 今日仪表盘
  BabyLove/Views/Track/TrackView.swift     — 记录列表
  BabyLove/Views/ContentView.swift         — Tab 导航

CoreData entities (只读，不修改 xcdatamodeld):
  CDFeedingRecord / CDSleepRecord / CDDiaperRecord / CDGrowthRecord / CDMilestone

设计色系 (严禁修改): Primary #FF7B6B · Feeding #4BAEE8 · Sleep #9B8EC4 · Diaper #55C189 · Growth #F5A623 · BG #FFF9F5

## AI 功能实现原则
- 纯 Swift 统计算法，不引入 SPM 依赖，不调用外部 API
- 算法：均值/标准差预测、线性趋势、规则引擎
- UI 简洁：一个卡片 / 一个标签 / 一行文字，不堆砌
- 需要支持4种语言：en / zh-Hans / ja / ko（Localizable.strings）

## 迭代流程（严格执行）
1. `git log --oneline -10` — 确认最近提交，避免重复
2. 阅读涉及文件，理解现有代码结构
3. 完整实现功能，不留 TODO/占位代码
4. `xcodegen generate && xcodebuild build -project BabyLove.xcodeproj -scheme BabyLove -destination 'id=8457B971-4286-457B-8AE0-8A6728C35CC5' -configuration Debug ONLY_ACTIVE_ARCH=YES 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"` — 必须 BUILD SUCCEEDED
5. Simulator 测试：xcrun simctl boot → install → launch → screenshot → terminate（截图存 agent/screenshots/）
6. `git add -A && git commit -m "feat(ai): <英文简述>\\n\\nCo-Authored-By: Claude <noreply@anthropic.com>"`

## 硬性约束
- iOS 26+ Swift 6.0 兼容；不引入 SPM 依赖；不修改 xcdatamodeld；BUILD SUCCEEDED 后才能提交
"""

# ─── 任务 Prompt ─────────────────────────────────────────────────────────────
TASK_PROMPT = """实现以下 AI 功能（任务 #{task_id}/{total}）：

**功能名称**: {title}
**功能描述**: {desc}

请严格按系统提示的迭代流程执行：
1. git log 确认无重复
2. 阅读相关代码
3. 完整实现（含国际化 en/zh-Hans/ja/ko）
4. xcodebuild BUILD SUCCEEDED
5. Simulator 启动截图
6. git commit

聚焦原则：只实现上述这一个功能，做完做好。"""

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
async def run_task(task: dict, task_num: int, total: int, total_cost: float) -> float:
    ts = datetime.now().strftime("%H:%M:%S")
    prompt = TASK_PROMPT.format(
        task_id=task["id"],
        total=total,
        title=task["title"],
        desc=task["desc"],
    )

    print(f"\n{'─' * 66}")
    print(f"  [{ts}] 任务 #{task['id']}/{total}: {task['title']}")
    print(f"  {task['desc'][:80]}…")
    print(f"{'─' * 66}", flush=True)

    options = ClaudeAgentOptions(
        cwd=PROJECT_DIR,
        allowed_tools=["Read", "Write", "Edit", "Bash", "Glob", "Grep"],
        permission_mode="bypassPermissions",
        system_prompt=SYSTEM_PROMPT,
        max_turns=60,
        model="claude-opus-4-6",
    )

    cost = 0.0
    result_summary = ""

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
                            print(f"  💭 {text[:130]}", flush=True)
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
                    print(f"  {result_summary[:200]}", flush=True)

                    if result_summary:
                        save_skill(f"[AI#{task['id']}] {task['title']}: {result_summary[:50]}")

                    return cost

    except Exception as e:
        if not _shutdown:
            print(f"\n  ✗ 出错: {type(e).__name__}: {e}", flush=True)

    return cost

# ─── 主循环 ──────────────────────────────────────────────────────────────────
async def main():
    interval = 10
    if len(sys.argv) > 1:
        try:
            interval = int(sys.argv[1])
        except ValueError:
            pass

    all_tasks = load_todo()
    total     = len(all_tasks)

    print("🍼 BabyLove AI 功能 Agent  (Ctrl+C 停止)")
    print(f"   项目:      {PROJECT_DIR}")
    print(f"   Simulator: iPhone 17 / iOS 26.2 ({SIM_ID[:8]}…)")
    print(f"   模型:      claude-opus-4-6")
    print(f"   间隔:      {interval}s")
    print(f"   Todo:      {AI_TODO}\n")
    print_todo_status()

    total_cost = 0.0
    errors     = 0

    while not _shutdown:
        task = next_task()
        if task is None:
            print(f"\n🎉 所有 AI 功能已完成！总花费: ${total_cost:.4f}")
            print_todo_status()
            break

        try:
            cost = await run_task(task, task["id"], total, total_cost)
            total_cost += cost
            errors = 0
            if not _shutdown:
                mark_done(task["id"])
                print(f"\n  ✅ 已标记完成: #{task['id']} {task['title']}")
                print_todo_status()
        except Exception as e:
            errors += 1
            print(f"  ⚠️  未处理错误 ({errors}/3): {e}", flush=True)
            if errors >= 3:
                print("  连续3次错误，停止运行", flush=True)
                break

        if _shutdown:
            break

        next_t = next_task()
        if next_t is None:
            print(f"\n🎉 所有 AI 功能已完成！总花费: ${total_cost:.4f}")
            print_todo_status()
            break

        print(f"\n  ⏳ {interval}s 后开始下一任务: #{next_t['id']} {next_t['title']}  [累计: ${total_cost:.4f}]", flush=True)
        for _ in range(interval):
            if _shutdown:
                break
            await anyio.sleep(1)

    if _shutdown:
        print(f"\n👋 已停止  总花费: ${total_cost:.4f}")


if __name__ == "__main__":
    anyio.run(main)
