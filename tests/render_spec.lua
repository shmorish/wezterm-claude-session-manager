package.path = "plugin/?.lua;tests/?.lua;" .. package.path

local t = require("helpers")
local render = require("claude_session_manager.render")
local config = require("claude_session_manager.config")

local cfg = config.merge(config.defaults, { ansi = false })

local sessions = {
  { pane_id = 1, workspace = "default", name = "dotfiles", state = "running", title = "✳ Karabinerの設定" },
  { pane_id = 2, workspace = "default", name = "my-app", state = "waiting", title = "✳ APIの実装" },
  { pane_id = 3, workspace = "work", name = "api-server", state = "done", title = "✳ バグ修正" },
}

local lines = render.lines(sessions, cfg)
local joined = table.concat(lines, "\n")

t.contains(joined, "Claude Code Sessions", "title rendered")
t.contains(joined, "[default]", "workspace group header")
t.contains(joined, "[work]", "second workspace group header")
t.contains(joined, "🟡", "running icon rendered")
t.contains(joined, "Running", "running label rendered")
t.contains(joined, "🔴", "waiting icon rendered")
t.contains(joined, "Waiting", "waiting label rendered")
t.contains(joined, "🟢", "done icon rendered")
t.contains(joined, "Done", "done label rendered")
t.contains(joined, "dotfiles", "project name rendered")
t.contains(joined, "3 sessions", "session count footer")
t.contains(joined, "Karabiner", "pane title shown under session")

-- show_title = false ならタイトル行は出ない
local no_title = table.concat(render.lines(sessions, config.merge(cfg, { show_title = false })), "\n")
t.eq(no_title:find("Karabiner", 1, true), nil, "title hidden when show_title=false")

-- セッションなし
local empty = table.concat(render.lines({}, cfg), "\n")
t.contains(empty, "no sessions", "empty state message")

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

-- ペイン幅 (max_cols) を渡すと全行がその幅に収まる
local narrow = render.lines(sessions, cfg, 22)
for i, line in ipairs(narrow) do
  t.ok(render.display_width(line) <= 22, "narrow line " .. i .. " fits in 22 cols")
end
t.contains(table.concat(narrow, "\n"), "Running", "labels survive narrow width")

-- ラベルは設定で日本語にも上書きできる
local jp = table.concat(
  render.lines(sessions, config.merge(cfg, { labels = { running = "実行中", waiting = "停止中", done = "完了" } })),
  "\n"
)
t.contains(jp, "実行中", "labels overridable to Japanese")

-- プロジェクト名の表示
t.eq(render.project_name("/Users/x/dev/my-app", "basename", "/Users/x"), "my-app", "basename mode")
t.eq(render.project_name("/Users/x/dev/my-app/", "basename", "/Users/x"), "my-app", "trailing slash tolerated")
t.eq(render.project_name("/Users/x/dev/my-app", "shortened", "/Users/x"), "~/dev/my-app", "shortened mode")
t.eq(render.project_name("/Users/x/dev/my-app", "full", "/Users/x"), "/Users/x/dev/my-app", "full mode")
t.eq(render.project_name(nil, "basename", "/Users/x"), nil, "nil cwd returns nil")

t.finish("render_spec")
