package.path = "plugin/?.lua;tests/?.lua;" .. package.path

local t = require("helpers")
local detect = require("claude_session_manager.detect")
local config = require("claude_session_manager.config")

local patterns = config.defaults.patterns.process

-- ネイティブバイナリ版 (homebrew / native installer)
t.ok(
  detect.is_claude({
    name = "claude",
    executable = "/opt/homebrew/bin/claude",
    argv = { "claude" },
    children = {},
  }, patterns),
  "native claude binary"
)

-- npm 版 (node + cli.js)
t.ok(
  detect.is_claude({
    name = "node",
    executable = "/usr/local/bin/node",
    argv = { "node", "/Users/x/.nvm/versions/node/v20/lib/node_modules/@anthropic-ai/claude-code/cli.js" },
    children = {},
  }, patterns),
  "npm claude-code under node"
)

-- フォアグラウンドが shell で、子プロセスツリーの中に claude がいるケース
t.ok(
  detect.is_claude({
    name = "zsh",
    executable = "/bin/zsh",
    argv = { "-zsh" },
    children = {
      [4321] = {
        name = "claude",
        executable = "/Users/x/.local/bin/claude",
        argv = { "claude", "--resume" },
        children = {},
      },
    },
  }, patterns),
  "claude nested in children tree"
)

-- claude ではないプロセス
t.eq(
  detect.is_claude({ name = "zsh", executable = "/bin/zsh", argv = { "-zsh" }, children = {} }, patterns),
  false,
  "plain zsh is not claude"
)

-- ファイル名に claude を含むだけの別プロセス (誤検出しない)
t.eq(
  detect.is_claude({
    name = "nvim",
    executable = "/opt/homebrew/bin/nvim",
    argv = { "nvim", "claude-notes.md" },
    children = {},
  }, patterns),
  false,
  "nvim editing claude-notes.md is not claude"
)

-- 異常系
t.eq(detect.is_claude(nil, patterns), false, "nil info is not claude")
t.eq(detect.is_claude({}, patterns), false, "empty info is not claude")
t.eq(
  detect.is_claude({ name = "claude" }, patterns),
  true,
  "missing argv/children tolerated"
)

t.finish("detect_spec")
