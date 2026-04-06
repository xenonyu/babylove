#!/usr/bin/env python3
"""
BabyLove 自主迭代 Agent
设计哲学：乔布斯式精简 × 功能完整 × 国际化 × 企业级测试
持续循环：分析 → 改进 → Build验证 → Simulator测试 → Commit → 重复
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
    ToolResultBlock,
    ToolUseBlock,
    query,
)

# ─── 项目配置 ────────────────────────────────────────────────────────────────
PROJECT_DIR = "/Users/yaxinli/xym/babylove"
SIM_ID      = "8457B971-4286-457B-8AE0-8A6728C35CC5"   # iPhone 17 / iOS 26.2
BUNDLE_ID   = "com.babylove.app"
SCHEME      = "BabyLove"
SKILL_LOG   = Path(PROJECT_DIR) / "agent" / "skill_log.json"

# ─── 优雅退出信号处理 ─────────────────────────────────────────────────────────
_shutdown = False
_session_id: str | None = None
SESSION_RESET_EVERY = 8          # fresh session every N iterations

def _sigint(sig, frame):
    global _shutdown
    if _shutdown:
        # 第二次 Ctrl+C → 立即强制退出
        print("\n\n💀 强制退出", flush=True)
        sys.exit(1)
    _shutdown = True
    print("\n\n⚠️  收到停止信号，等待本次迭代结束…（再按一次强制退出）", flush=True)

signal.signal(signal.SIGINT, _sigint)

# ─── 系统 Prompt ─────────────────────────────────────────────────────────────
SYSTEM_PROMPT = """你是一位有乔布斯式产品直觉的 iOS Swift 工程师，负责打磨 BabyLove——一款让每位家长优雅记录宝宝成长的应用。

## 产品核心理念
BabyLove = 极简记录 × 深度洞察 × 永久珍藏
- 乔布斯原则：每个 UI 元素都必须存在理由；单手操作，2次点击内完成记录
- 全球化：中/英/日/韩语言，公制/英制，WHO 生长曲线
- 差异化特色：Lightning Quick Log / Smart Summaries / WHO Chart / Memory Timeline / Zero-sync Privacy

## 架构
Bundle ID: com.babylove.app | iOS 26.0+ | SwiftUI + CoreData + MVVM | Swift 6
项目路径: /Users/yaxinli/xym/babylove

核心文件（高频修改）:
  BabyLove/Design/DesignSystem.swift      — 品牌色/组件
  BabyLove/ViewModels/TrackViewModel.swift — 记录 CRUD
  BabyLove/Views/Home/HomeView.swift      — 今日仪表盘
  BabyLove/Views/Track/TrackView.swift    — 记录列表
  BabyLove/Views/ContentView.swift        — Tab 导航

CoreData entities (只读，不修改 xcdatamodeld): CDFeedingRecord / CDSleepRecord / CDDiaperRecord / CDGrowthRecord / CDMilestone

设计色系 (严禁修改): Primary #FF7B6B · Feeding #4BAEE8 · Sleep #9B8EC4 · Diaper #55C189 · Growth #F5A623 · BG #FFF9F5

## 迭代流程（每次严格执行）
1. `git log --oneline -15` — 避免重复已有改进
2. 阅读相关代码，找高价值改进点（优先级：编译错误 > 核心功能缺失 > UI/UX > 数据准确性 > 国际化 > 辅助功能）
3. 完整实现，不留 TODO/占位代码
4. `xcodegen generate && xcodebuild build -project BabyLove.xcodeproj -scheme BabyLove -destination 'id=8457B971-4286-457B-8AE0-8A6728C35CC5' -configuration Debug ONLY_ACTIVE_ARCH=YES 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"` — 必须 BUILD SUCCEEDED
5. Simulator 测试：boot → install → launch → screenshot → check crash → terminate（截图存 agent/screenshots/）
6. `git add -A && git commit -m "fix/feat/ui: <英文描述>\n\nCo-Authored-By: Claude <noreply@anthropic.com>"`

## 硬性约束
- iOS 26+ Swift 6.0 兼容；不引入 SPM 依赖；不修改 xcdatamodeld；每次只做一个聚焦改进；BUILD SUCCEEDED 后才能提交
"""

# ─── 迭代 Prompt ─────────────────────────────────────────────────────────────
ITERATION_PROMPT = """分析 BabyLove iOS 项目（{project_dir}）。

当前迭代 #{iteration}，累计花费 ${total_cost:.4f}

已完成改进（避免重复）:
{completed_skills}

**任务**：
1. 运行 `git log --oneline -15` 了解最近改动
2. 深入阅读相关代码，找到一个高价值改进点
3. 完整实现
4. xcodebuild BUILD SUCCEEDED（必须）
5. Simulator 启动测试（必须）
6. 提交

聚焦原则：一次只做一件事，做完做好。"""

# ─── Skill 日志（减少重复改进，节省 token） ──────────────────────────────────
def load_skill_log() -> list[str]:
    if SKILL_LOG.exists():
        try:
            return json.loads(SKILL_LOG.read_text())
        except Exception:
            return []
    return []

def save_skill(description: str):
    skills = load_skill_log()
    entry = f"[{datetime.now().strftime('%m/%d %H:%M')}] {description}"
    skills.append(entry)
    # 只保留最近 30 条
    skills = skills[-30:]
    SKILL_LOG.write_text(json.dumps(skills, ensure_ascii=False, indent=2))

# ─── 格式化工具调用 ──────────────────────────────────────────────────────────
def fmt_tool(block: ToolUseBlock) -> str:
    name = block.name
    inp  = block.input or {}
    if name == "Bash":
        cmd = str(inp.get("command", "")).strip().replace("\n", " ")[:100]
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

# ─── 单次迭代 ────────────────────────────────────────────────────────────────
async def run_iteration(iteration: int, total_cost: float) -> tuple[float, str]:
    global _session_id
    ts = datetime.now().strftime("%H:%M:%S")
    skills = load_skill_log()
    skills_text = "\n".join(f"  • {s}" for s in skills[-5:]) if skills else "  （无）"

    prompt = ITERATION_PROMPT.format(
        project_dir=PROJECT_DIR,
        iteration=iteration,
        total_cost=total_cost,
        completed_skills=skills_text,
    )

    print(f"\n{'─' * 66}")
    print(f"  [{ts}] 迭代 #{iteration}  累计: ${total_cost:.4f}  模型: claude-opus-4-6")
    print(f"{'─' * 66}", flush=True)

    options = ClaudeAgentOptions(
        cwd=PROJECT_DIR,
        allowed_tools=["Read", "Write", "Edit", "Bash", "Glob", "Grep"],
        permission_mode="bypassPermissions",
        system_prompt=SYSTEM_PROMPT,
        max_turns=50,
        model="claude-opus-4-6",
        resume=_session_id,
    )

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
                    cost  = message.total_cost_usd or 0.0
                    turns = message.num_turns
                    usage = message.usage or {}
                    inp   = usage.get("input_tokens", 0)
                    out   = usage.get("output_tokens", 0)
                    result_summary = (message.result or "").strip()
                    preview = result_summary[:200]

                    # Session continuation: carry forward session_id, reset every N iters
                    _session_id = getattr(message, "session_id", None)
                    if iteration % SESSION_RESET_EVERY == 0:
                        _session_id = None
                        print(f"  🔄 Session reset (iter {iteration})", flush=True)

                    print(f"\n  ✓ 完成  💰 ${cost:.4f}  🔄 {turns}轮  📊 {inp:,}in/{out:,}out", flush=True)
                    print(f"  {preview}", flush=True)

                    if result_summary:
                        save_skill(result_summary[:60])

                    return cost, result_summary

    except Exception as e:
        if not _shutdown:
            print(f"\n  ✗ 出错: {type(e).__name__}: {e}", flush=True)
        return 0.0, ""

    return 0.0, ""

# ─── 主循环 ──────────────────────────────────────────────────────────────────
async def main():
    interval = 10
    if len(sys.argv) > 1:
        try:
            interval = int(sys.argv[1])
        except ValueError:
            pass

    print("🍼 BabyLove 自主迭代 Agent  (Ctrl+C 停止)")
    print(f"   项目:      {PROJECT_DIR}")
    print(f"   Simulator: iPhone 17 / iOS 26.2 ({SIM_ID[:8]}…)")
    print(f"   模型:      claude-opus-4-6 (1M context)")
    print(f"   间隔:      {interval}s")
    print(f"   Skill Log: {SKILL_LOG}\n")

    # 确保 skill log 目录存在
    SKILL_LOG.parent.mkdir(parents=True, exist_ok=True)

    iteration  = 1
    total_cost = 0.0
    errors     = 0

    while not _shutdown:
        try:
            cost, _ = await run_iteration(iteration, total_cost)
            total_cost += cost
            errors = 0
        except Exception as e:
            errors += 1
            print(f"  ⚠️  未处理错误 ({errors}/3): {e}", flush=True)
            if errors >= 3:
                print("  连续3次错误，停止运行", flush=True)
                break

        if _shutdown:
            break

        iteration += 1
        print(f"\n  ⏳ {interval}s 后开始迭代 #{iteration}…  [累计: ${total_cost:.4f}]", flush=True)

        # 分段 sleep，每秒检查一次 _shutdown flag
        for _ in range(interval):
            if _shutdown:
                break
            await anyio.sleep(1)

    print(f"\n👋 已停止  迭代: {iteration - 1}次  总花费: ${total_cost:.4f}")


if __name__ == "__main__":
    anyio.run(main)
