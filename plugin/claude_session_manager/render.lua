local M = {}

local function char_width(codepoint)
  if codepoint == 0x2026 then -- …
    return 1
  end
  -- CJK / かな / ハングル / 全角 / 絵文字を幅2として扱う簡易判定
  if
    (codepoint >= 0x1100 and codepoint <= 0x115F)
    or (codepoint >= 0x2E80 and codepoint <= 0xA4CF)
    or (codepoint >= 0xAC00 and codepoint <= 0xD7A3)
    or (codepoint >= 0xF900 and codepoint <= 0xFAFF)
    or (codepoint >= 0xFE30 and codepoint <= 0xFE6F)
    or (codepoint >= 0xFF00 and codepoint <= 0xFF60)
    or (codepoint >= 0xFFE0 and codepoint <= 0xFFE6)
    or codepoint >= 0x1F000
  then
    return 2
  end
  return 1
end

function M.display_width(text)
  local width = 0
  for _, codepoint in utf8.codes(text) do
    width = width + char_width(codepoint)
  end
  return width
end

-- 表示幅ベースで切り詰め、収まらない場合は … を付ける
function M.truncate(text, max_width)
  if M.display_width(text) <= max_width then
    return text
  end
  local width = 0
  local out = {}
  for _, codepoint in utf8.codes(text) do
    local w = char_width(codepoint)
    if width + w > max_width - 1 then
      break
    end
    width = width + w
    out[#out + 1] = utf8.char(codepoint)
  end
  return table.concat(out) .. "…"
end

function M.pad(text, width)
  local gap = width - M.display_width(text)
  if gap <= 0 then
    return text
  end
  return text .. string.rep(" ", gap)
end

-- cwd のパスを表示名に変換する
function M.project_name(path, mode, home_dir)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  if mode == "full" then
    return path
  end
  if mode == "shortened" then
    if home_dir and path:sub(1, #home_dir) == home_dir then
      return "~" .. path:sub(#home_dir + 1)
    end
    return path
  end
  return path:match("([^/\\]+)[/\\]*$") or path
end

function M.counts(sessions)
  local counts = { running = 0, waiting = 0, done = 0, total = #sessions }
  for _, session in ipairs(sessions) do
    counts[session.state] = (counts[session.state] or 0) + 1
  end
  return counts
end

local function sorted_copy(sessions)
  local copy = {}
  for i, session in ipairs(sessions) do
    copy[i] = session
  end
  table.sort(copy, function(a, b)
    if (a.workspace or "") ~= (b.workspace or "") then
      return (a.workspace or "") < (b.workspace or "")
    end
    if (a.name or "") ~= (b.name or "") then
      return (a.name or "") < (b.name or "")
    end
    return (a.pane_id or 0) < (b.pane_id or 0)
  end)
  return copy
end

local function workspace_count(sessions)
  local seen = {}
  local count = 0
  for _, session in ipairs(sessions) do
    local workspace = session.workspace or "default"
    if not seen[workspace] then
      seen[workspace] = true
      count = count + 1
    end
  end
  return count
end

local function max_label_width(cfg)
  local width = 0
  for _, label in pairs(cfg.labels) do
    width = math.max(width, M.display_width(label))
  end
  return width
end

-- 全 choices のラベル先頭に空白を足して横中央寄せする。
-- InputSelector に位置指定オプションがないための擬似センタリング
local function center_choices(choices, cols)
  local max_width = 0
  for _, choice in ipairs(choices) do
    max_width = math.max(max_width, M.display_width(choice.label))
  end
  local pad = math.floor((cols - max_width) / 2)
  if pad <= 0 then
    return choices
  end
  local padding = string.rep(" ", pad)
  local centered = {}
  for i, choice in ipairs(choices) do
    centered[i] = { id = choice.id, label = padding .. choice.label }
  end
  return centered
end

-- InputSelector 用の選択肢を生成する (純粋関数)。
-- label 例: "🟡 dotfiles           Running  ✳ 作業タイトル [work]"
-- cols (表示先ペインの桁数) を渡すと picker.center に従い横中央寄せする
function M.choices(sessions, cfg, cols)
  if #sessions == 0 then
    return { { id = "", label = "  (no sessions)" } }
  end

  local label_width = max_label_width(cfg)
  local multi_workspace = workspace_count(sessions) > 1
  local choices = {}
  for _, session in ipairs(sorted_copy(sessions)) do
    local icon = cfg.icons[session.state] or "•"
    local state_label = cfg.labels[session.state] or session.state
    local name = M.truncate(session.name or "?", cfg.max_name_width)
    local parts = {
      icon,
      " ",
      M.pad(name, cfg.max_name_width),
      " ",
      M.pad(state_label, label_width),
    }
    if cfg.show_title and session.title and session.title ~= "" then
      parts[#parts + 1] = "  " .. M.truncate(session.title, 48)
    end
    if multi_workspace then
      parts[#parts + 1] = " [" .. (session.workspace or "default") .. "]"
    end
    choices[#choices + 1] = {
      id = tostring(session.pane_id),
      label = table.concat(parts),
    }
  end
  if cols and cfg.picker.center then
    return center_choices(choices, cols)
  end
  return choices
end

return M
