package.path = "plugin/?.lua;tests/?.lua;" .. package.path

local t = require("helpers")
local config = require("claude_session_manager.config")
local picker = require("claude_session_manager.picker")

local sock = "/tmp/claude-session-fzf-1.sock"

-- preview_refresh 有効時: --listen とソケット、refresher ループ、teardown が生成される
local cfg = config.defaults
local setup, listen, teardown = picker._refresh_shell(cfg, sock)
t.contains(setup, "sock='" .. sock .. "'", "refresher references the socket path")
t.contains(setup, "curl -fs", "refresher POSTs via curl")
t.contains(setup, "refresh-preview", "refresher sends refresh-preview action")
t.contains(setup, "sleep 1", "refresher uses the configured interval (1s)")
t.contains(setup, "connected=1", "refresher self-terminates after connect (leak-safe)")
t.contains(setup, "misses", "refresher gives up if it never connects (no infinite orphan)")
t.contains(listen, "--listen='" .. sock .. "'", "fzf gets --listen with the socket")
t.contains(teardown, "kill", "teardown kills the refresher on fzf exit")

-- 間隔は設定で変更できる
local slow = config.merge(config.defaults, { picker = { preview_refresh_interval = 3 } })
local slow_setup = picker._refresh_shell(slow, sock)
t.contains(slow_setup, "sleep 3", "interval override is reflected in the refresher")

-- preview_refresh 無効時: 何も生成しない
local off = config.merge(config.defaults, { picker = { preview_refresh = false } })
local off_setup, off_listen, off_teardown = picker._refresh_shell(off, sock)
t.eq(off_setup, "", "no refresher setup when auto-refresh disabled")
t.eq(off_listen, "", "no --listen when auto-refresh disabled")
t.eq(off_teardown, "", "no teardown when auto-refresh disabled")

-- ソケット未指定なら何も生成しない (フォールバック安全)
local nosock = picker._refresh_shell(cfg, nil)
t.eq(nosock, "", "no refresher without a socket path")

-- build_script: refresh 有効なスクリプトは --listen とプレビューコマンドを含む
local script = picker._build_script(
  "/usr/bin/fzf",
  "/usr/bin/wezterm",
  "/tmp/list",
  "",
  42,
  cfg,
  "/tmp/preview-",
  sock
)
t.contains(script, "--listen='" .. sock .. "'", "generated script enables fzf --listen")
t.contains(script, "cli get-text", "generated script keeps the get-text fallback")
t.contains(script, "SetUserVar", "generated script emits the selection user-var")

-- build_script: refresh 無効なスクリプトには --listen が入らない
local off_script = picker._build_script(
  "/usr/bin/fzf",
  "/usr/bin/wezterm",
  "/tmp/list",
  "",
  42,
  off,
  "/tmp/preview-",
  sock
)
t.ok(not off_script:find("--listen", 1, true), "no --listen when auto-refresh disabled")

t.finish("picker_spec")
