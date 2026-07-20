local M = {}

M.defaults = {
  sidebar = {
    position = "Left",
    width = 0.28,
    title = "Claude Code Sessions",
    -- サイドバーペインで動かす表示用のダミープロセス
    command = { "tail", "-f", "/dev/null" },
  },
  icons = { running = "🔴", waiting = "🟡", done = "🟢" },
  labels = { running = "実行中", waiting = "停止中", done = "完了" },
  patterns = {
    -- ペイン末尾テキストの状態判定パターン (小文字・部分一致)。
    -- Claude Code の TUI 文言が変わったら上書きする
    running = { "esc to interrupt" },
    waiting = { "do you want", "❯ 1." },
    -- プロセス名/argv に対する Lua パターン
    process = { "^claude$", "claude%-code" },
  },
  scan_lines = 40,
  cwd_display = "basename", -- "basename" | "shortened" | "full"
  max_name_width = 18,
  show_title = true,
  ansi = true,
}

local function is_list(value)
  return #value > 0
end

local function deep_merge(base, override)
  if override == nil then
    return base
  end
  if type(base) ~= "table" or type(override) ~= "table" or is_list(base) or is_list(override) then
    return override
  end
  local merged = {}
  for key, value in pairs(base) do
    merged[key] = value
  end
  for key, value in pairs(override) do
    merged[key] = deep_merge(base[key], value)
  end
  return merged
end

-- defaults を変異させず、新しい設定テーブルを返す
function M.merge(base, override)
  return deep_merge(base, override or {})
end

return M
