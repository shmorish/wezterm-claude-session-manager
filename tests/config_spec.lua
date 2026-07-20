package.path = "plugin/?.lua;tests/?.lua;" .. package.path

local t = require("helpers")
local config = require("claude_session_manager.config")

-- opts なしなら defaults がそのまま返る内容になる
local merged_empty = config.merge(config.defaults, nil)
t.eq(merged_empty.scan_lines, config.defaults.scan_lines, "nil opts keeps defaults")

-- ネストしたテーブルは部分上書きできる
local merged = config.merge(config.defaults, {
  icons = { running = ">>" },
  scan_lines = 10,
})
t.eq(merged.icons.running, ">>", "override nested value")
t.eq(merged.icons.done, config.defaults.icons.done, "sibling nested values survive")
t.eq(merged.scan_lines, 10, "override scalar")
t.eq(merged.sidebar.width, config.defaults.sidebar.width, "untouched branch survives")

-- 配列 (パターンリスト) は丸ごと置き換え
local merged_list = config.merge(config.defaults, {
  patterns = { waiting = { "custom prompt" } },
})
t.eq(#merged_list.patterns.waiting, 1, "list is replaced, not merged")
t.eq(merged_list.patterns.waiting[1], "custom prompt", "replaced list content")
t.eq(merged_list.patterns.running[1], "esc to interrupt", "sibling list survives")

-- 既定アイコン: 対応が必要な停止中が赤、実行中は黄、完了は緑
t.eq(config.defaults.icons.waiting, "🔴", "waiting icon is red")
t.eq(config.defaults.icons.running, "🟡", "running icon is yellow")
t.eq(config.defaults.icons.done, "🟢", "done icon is green")

-- 既定は英語ラベル・幅は 0.18
t.eq(config.defaults.labels.running, "Running", "default labels are English")
t.eq(config.defaults.sidebar.width, 0.18, "default sidebar width")

-- 既定キーバインドは CMD+s、false で無効化できる
t.eq(config.defaults.keybind.key, "s", "default keybind key")
t.eq(config.defaults.keybind.mods, "CMD", "default keybind mods")
t.eq(config.merge(config.defaults, { keybind = false }).keybind, false, "keybind can be disabled")
local custom_key = config.merge(config.defaults, { keybind = { key = "b", mods = "CTRL|SHIFT" } })
t.eq(custom_key.keybind.key, "b", "keybind key overridable")
t.eq(custom_key.keybind.mods, "CTRL|SHIFT", "keybind mods overridable")

-- defaults は変異しない (イミュータブル)
t.eq(config.defaults.icons.running, "🟡", "defaults not mutated by merge")
t.eq(config.defaults.scan_lines, 40, "defaults scalar not mutated")

t.finish("config_spec")
