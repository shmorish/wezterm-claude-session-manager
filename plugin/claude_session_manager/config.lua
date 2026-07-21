local M = {}

M.defaults = {
  picker = {
    title = "Claude Code Sessions",
    -- 既定は番号キー選択モード (数字キーで即ジャンプ、/ で検索に切替)。
    -- true にすると最初からファジー検索で開く
    fuzzy = false,
    -- 各行に割り当てる選択キー。10件以上は ↑↓ + Enter で選択
    alphabet = "123456789",
    -- ペイン幅に合わせて一覧を横中央寄せする (縦は wezterm の制約で不可)
    center = true,
    -- fzf が見つかればプレビュー付きポップアップペインで表示する。
    -- false で常に InputSelector モーダルを使う
    preview = true,
    popup_size = 0.45, -- ポップアップペインの高さ (ウィンドウに対する割合)
    preview_window = "right,60%", -- fzf の --preview-window
    preview_lines = 40, -- プレビューに表示するペイン末尾の行数
  },
  -- 停止中はユーザーの対応が必要なので赤で目立たせる
  icons = { running = "🟡", waiting = "🔴", done = "🟢" },
  labels = { running = "Running", waiting = "Waiting", done = "Done" },
  patterns = {
    -- ペイン末尾テキストの状態判定パターン (小文字・部分一致)。
    -- Claude Code の TUI 文言が変わったら上書きする
    running = { "esc to interrupt" },
    waiting = { "do you want", "❯ 1." },
    -- プロセス名/argv に対する Lua パターン
    process = { "^claude$", "claude%-code" },
  },
  -- apply_to_config で自動登録されるモーダル表示キー。false で無効化
  keybind = { key = "s", mods = "CMD" },
  scan_lines = 40,
  cwd_display = "basename", -- "basename" | "shortened" | "full"
  max_name_width = 18,
  show_title = true,
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
