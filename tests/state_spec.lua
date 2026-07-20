package.path = "plugin/?.lua;tests/?.lua;" .. package.path

local t = require("helpers")
local state = require("claude_session_manager.state")
local config = require("claude_session_manager.config")

local patterns = config.defaults.patterns

-- 実機の Claude Code (2026-07) から採取した画面テキスト fixture

local RUNNING_SCREEN = [[
✻ Architecting… (12m 13s · ↓ 33.3k tokens)

──────────────────────────────────────── wezterm-claude-sidebar-plugin ──
❯
──────────────────────────────────────────────────────────────────────────
  ⏵⏵ auto mode on (shift+tab to cycle) · esc to interrupt · ← for agents
]]

local WAITING_SCREEN = [[
 13 +karabiner/.config/karabiner/automatic_backups/
 14   No newline at end of file
╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
 Do you want to make this edit to .gitignore?
 ❯ 1. Yes
   2. Yes, allow all edits during this session (shift+tab)
   3. No

 Esc to cancel · Tab to amend
]]

local DONE_SCREEN = [[
  まとめると、構成変更のコストをかけてまで dotfiles/.config/
  直下方式に寄せる理由は薄い、というのが私の見立てです。

✻ Baked for 47s

──────────────────────────────────────────────────────────────────────────
❯
──────────────────────────────────────────────────────────────────────────
  ⏸ manual mode on · ? for shortcuts · ← for agents
]]

t.eq(state.classify(RUNNING_SCREEN, patterns), "running", "generating screen is running")
t.eq(state.classify(WAITING_SCREEN, patterns), "waiting", "permission prompt is waiting")
t.eq(state.classify(DONE_SCREEN, patterns), "done", "idle prompt box is done")

-- 生成中の画面の本文に「do you want」が含まれていても running が優先される
t.eq(
  state.classify("...do you want me to continue?...\n esc to interrupt", patterns),
  "running",
  "running marker wins over waiting text in transcript"
)

-- 大文字小文字は区別しない
t.eq(state.classify("ESC TO INTERRUPT", patterns), "running", "case-insensitive running")
t.eq(state.classify("DO YOU WANT to proceed?", patterns), "waiting", "case-insensitive waiting")

-- 異常系
t.eq(state.classify("", patterns), "done", "empty text falls back to done")
t.eq(state.classify(nil, patterns), "done", "nil text falls back to done")
t.eq(state.classify("plain shell output", { running = {}, waiting = {} }), "done", "no patterns means done")

t.finish("state_spec")
