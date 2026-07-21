package.path = "plugin/?.lua;tests/?.lua;" .. package.path

local t = require("helpers")
local render = require("claude_session_manager.render")
local config = require("claude_session_manager.config")

local cfg = config.merge(config.defaults, {})

local sessions = {
  { pane_id = 1, workspace = "default", name = "dotfiles", state = "running", title = "✳ Karabinerの設定" },
  { pane_id = 2, workspace = "default", name = "my-app", state = "waiting", title = "✳ APIの実装" },
  { pane_id = 3, workspace = "default", name = "api-server", state = "done", title = "✳ バグ修正" },
}

-- InputSelector 用の choices 生成
local choices = render.choices(sessions, cfg)
t.eq(#choices, 3, "one choice per session")
t.eq(choices[1].id, "3", "sorted by name, id is pane_id string") -- api-server
t.eq(choices[2].id, "1", "dotfiles second")
t.eq(choices[3].id, "2", "my-app last")

local labels = {}
for _, choice in ipairs(choices) do
  labels[#labels + 1] = choice.label
end
local joined = table.concat(labels, "\n")
t.contains(joined, "🟡", "running icon in label")
t.contains(joined, "Running", "running state in label")
t.contains(joined, "🔴", "waiting icon in label")
t.contains(joined, "Waiting", "waiting state in label")
t.contains(joined, "🟢", "done icon in label")
t.contains(joined, "Done", "done state in label")
t.contains(joined, "dotfiles", "project name in label")
t.contains(joined, "Karabiner", "pane title in label")
t.eq(joined:find("[default]", 1, true), nil, "single workspace omits workspace tag")

-- workspace が複数あるときだけ [ws] を付ける
local multi_ws = render.choices({
  { pane_id = 1, workspace = "default", name = "a", state = "done", title = "" },
  { pane_id = 9, workspace = "work", name = "b", state = "done", title = "" },
}, cfg)
t.contains(multi_ws[1].label .. multi_ws[2].label, "[work]", "workspace tag when multiple workspaces")

-- show_title = false ならタイトルは含めない
local no_title = render.choices(sessions, config.merge(cfg, { show_title = false }))
t.eq(no_title[2].label:find("Karabiner", 1, true), nil, "title hidden when show_title=false")

-- cols を渡すと横中央寄せ (先頭に空白パディング)
local centered = render.choices(sessions, cfg, 100)
local pad_len = centered[1].label:match("^( *)"):len()
t.ok(pad_len > 0, "centered labels have leading padding")
for i, choice in ipairs(centered) do
  t.eq(choice.label:match("^( *)"):len(), pad_len, "uniform padding for row " .. i)
end
t.ok(render.display_width(centered[1].label) <= 100, "centered label fits in cols")

-- center = false なら cols を渡してもパディングしない
local no_center = render.choices(sessions, config.merge(cfg, { picker = { center = false } }), 100)
t.eq(no_center[1].label:match("^( *)"):len(), 0, "no padding when center=false")

-- cols が狭い時はパディングなしで従来どおり
local narrow = render.choices(sessions, cfg, 20)
t.eq(narrow[1].label:match("^( *)"):len(), 0, "no padding when pane too narrow")

-- セッション0件はプレースホルダ1件
local empty = render.choices({}, cfg)
t.eq(#empty, 1, "placeholder for empty list")
t.eq(empty[1].id, "", "placeholder has empty id")
t.contains(empty[1].label, "no sessions", "placeholder label")

-- fzf 用の入力行 (id TAB 番号付きラベル)
local fzf_lines = render.fzf_lines(render.choices(sessions, cfg))
t.eq(#fzf_lines, 3, "one fzf line per choice")
t.contains(fzf_lines[1], "3\t1. ", "line = id TAB number prefix") -- api-server (pane 3) が先頭
t.contains(fzf_lines[2], "1\t2. ", "second line numbered 2")
t.contains(fzf_lines[1], "api-server", "label preserved in fzf line")

-- 10件目以降は番号なし
local many = {}
for i = 1, 11 do
  many[i] = { id = tostring(i), label = "item" .. i }
end
local many_lines = render.fzf_lines(many)
t.contains(many_lines[9], "\t9. ", "9th line numbered")
t.eq(many_lines[10]:find("10%."), nil, "10th line has no number prefix")

-- 数字キーバインド生成
t.eq(render.fzf_binds(3), "1:pos(1)+accept,2:pos(2)+accept,3:pos(3)+accept", "binds for 3 items")
t.eq(render.fzf_binds(0), "", "no binds for empty list")
t.ok(not render.fzf_binds(12):find("10:"), "binds capped at 9")

-- counts
local counts = render.counts(sessions)
t.eq(counts.running, 1, "counts running")
t.eq(counts.waiting, 1, "counts waiting")
t.eq(counts.done, 1, "counts done")
t.eq(counts.total, 3, "counts total")

-- 表示幅ユーティリティ (CJK/絵文字は幅2)
t.eq(render.display_width("abc"), 3, "ascii width")
t.eq(render.display_width("実行中"), 6, "cjk width")
t.eq(render.display_width("🔴"), 2, "emoji width")

-- 切り詰め (長い名前は … 付きで max 幅以内)
local truncated = render.truncate("wezterm-claude-session-manager", 18)
t.ok(render.display_width(truncated) <= 18, "truncated within width")
t.contains(truncated, "…", "ellipsis appended")
t.eq(render.truncate("short", 18), "short", "short name untouched")

-- パディング (表示幅ベースで右詰め)
t.eq(render.pad("ab", 5), "ab   ", "ascii padding")
t.eq(render.display_width(render.pad("実行", 6)), 6, "cjk padding by display width")

-- プロジェクト名の表示
t.eq(render.project_name("/Users/x/dev/my-app", "basename", "/Users/x"), "my-app", "basename mode")
t.eq(render.project_name("/Users/x/dev/my-app/", "basename", "/Users/x"), "my-app", "trailing slash tolerated")
t.eq(render.project_name("/Users/x/dev/my-app", "shortened", "/Users/x"), "~/dev/my-app", "shortened mode")
t.eq(render.project_name("/Users/x/dev/my-app", "full", "/Users/x"), "/Users/x/dev/my-app", "full mode")
t.eq(render.project_name(nil, "basename", "/Users/x"), nil, "nil cwd returns nil")

t.finish("render_spec")
