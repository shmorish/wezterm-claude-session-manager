-- Claude Code の会話ログ (~/.claude/projects/<encoded-cwd>/<sessionId>.jsonl) から
-- プレビュー用テキストを組み立てる。ペイン画面 (get-text) と違い履歴が全部あるので
-- 代替スクリーンの空白パディング問題が起きない。
--
-- JSON パースは wezterm 組み込みの wezterm.json_parse を使う (python3/jq 不要)。
-- render/parse_lines は json_parse を注入可能にして wezterm 無しでもテストできる。
local M = {}

local RESET = "\027[0m"
-- ロール別の色 (fzf preview が ANSI を描画する)
local COLORS = {
  user = "\027[36m", -- シアン
  assistant = "\027[0m", -- 既定色
  tool = "\027[90m", -- グレー
}
local HEADERS = { user = "❯ You", assistant = "● Claude" }

-- cwd を Claude の projects ディレクトリ名にエンコードする。
-- Claude は非英数字 (/ _ . など) をすべて "-" に置換し、英数字と大小文字は保持する。
-- 実測: /Users/x/Private/ft_minecraft -> -Users-x-Private-ft-minecraft
function M.encode_cwd(cwd)
  if type(cwd) ~= "string" then
    return nil
  end
  return (cwd:gsub("[^%w]", "-"))
end

-- 1 メッセージの content から表示テキストを取り出す。
-- content は文字列、または {type=text|tool_use|tool_result|thinking, ...} の配列。
-- thinking は冗長なので除外し、tool 系は短いマーカーに畳む。
local function extract_text(message)
  if type(message) ~= "table" then
    return nil
  end
  local content = message.content
  if type(content) == "string" then
    return content
  end
  if type(content) ~= "table" then
    return nil
  end
  local parts = {}
  for _, block in ipairs(content) do
    if type(block) == "table" then
      local t = block.type
      if t == "text" and type(block.text) == "string" then
        parts[#parts + 1] = block.text
      elseif t == "tool_use" then
        parts[#parts + 1] = "[tool: " .. tostring(block.name or "?") .. "]"
      elseif t == "tool_result" then
        parts[#parts + 1] = "[tool_result]"
      end
    end
  end
  if #parts == 0 then
    return nil
  end
  return table.concat(parts, " ")
end

-- jsonl の行文字列配列を、パース済みレコード配列に変換する。
-- json_parse を注入可能にしてテスト時は素の Lua パーサを渡せるようにする。
function M.parse_lines(lines, json_parse)
  json_parse = json_parse or (rawget(_G, "wezterm") and _G.wezterm.json_parse)
  local records = {}
  if type(json_parse) ~= "function" then
    return records
  end
  for _, line in ipairs(lines) do
    if line ~= "" then
      local ok, rec = pcall(json_parse, line)
      if ok and type(rec) == "table" then
        records[#records + 1] = rec
      end
    end
  end
  return records
end

-- パース済みレコード配列 → ANSI 付きプレビュー文字列。
-- user/assistant のメッセージのみ採用し、末尾 max_messages 件を整形する。
function M.render(records, max_messages)
  max_messages = max_messages or 60
  -- 表示対象だけを抽出
  local msgs = {}
  for _, rec in ipairs(records) do
    if type(rec) == "table" and (rec.type == "user" or rec.type == "assistant") then
      local role = rec.type
      local text = extract_text(rec.message)
      if text and text:match("%S") then
        msgs[#msgs + 1] = { role = role, text = text }
      end
    end
  end
  -- 末尾 max_messages 件に絞る
  local first = #msgs > max_messages and (#msgs - max_messages + 1) or 1
  local out = {}
  for i = first, #msgs do
    local msg = msgs[i]
    local color = COLORS[msg.role] or RESET
    out[#out + 1] = color .. (HEADERS[msg.role] or msg.role) .. RESET
    for line in (msg.text .. "\n"):gmatch("(.-)\n") do
      out[#out + 1] = color .. line .. RESET
    end
    out[#out + 1] = "" -- メッセージ間の区切り
  end
  return table.concat(out, "\n")
end

-- ファイル末尾 max_bytes だけを読む (巨大 jsonl 対策)。
-- 途中から読んだ場合は先頭の欠けた行を捨てる。
function M.read_tail(path, max_bytes)
  local file = io.open(path, "rb")
  if not file then
    return nil
  end
  local size = file:seek("end")
  local start = (size > max_bytes) and (size - max_bytes) or 0
  file:seek("set", start)
  local data = file:read("*a")
  file:close()
  if not data then
    return nil
  end
  local lines = {}
  for line in (data .. "\n"):gmatch("(.-)\n") do
    lines[#lines + 1] = line
  end
  if start > 0 and #lines > 0 then
    table.remove(lines, 1) -- 部分行を除去
  end
  return lines
end

-- cwd から最新の transcript jsonl パスを解決する。無ければ nil。
function M.resolve(wezterm, cwd, home_dir)
  local encoded = M.encode_cwd(cwd)
  if not encoded or not home_dir then
    return nil
  end
  local dir = home_dir .. "/.claude/projects/" .. encoded
  local ok, _, stdout = pcall(wezterm.run_child_process, {
    "/bin/sh",
    "-c",
    "ls -t " .. string.format("%q", dir) .. "/*.jsonl 2>/dev/null | head -1",
  })
  if ok and type(stdout) == "string" then
    local path = stdout:gsub("%s+$", "")
    if path ~= "" then
      return path
    end
  end
  return nil
end

-- cwd の最新 transcript を整形したプレビュー文字列を返す。取れなければ nil。
function M.preview_text(wezterm, cwd, home_dir, opts)
  opts = opts or {}
  local path = M.resolve(wezterm, cwd, home_dir)
  if not path then
    return nil
  end
  local lines = M.read_tail(path, opts.max_bytes or 262144)
  if not lines then
    return nil
  end
  local records = M.parse_lines(lines, wezterm.json_parse)
  local text = M.render(records, opts.max_messages or 60)
  if text == "" then
    return nil
  end
  return text
end

return M
