local M = {}

local ESC = string.char(27)
local LABEL_COLORS = { running = "33", waiting = "31", done = "32" }

local function paint(text, code, ansi)
  if not ansi then
    return text
  end
  return ESC .. "[" .. code .. "m" .. text .. ESC .. "[0m"
end

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

local function group_by_workspace(sessions)
  local by_workspace = {}
  local names = {}
  for _, session in ipairs(sessions) do
    local workspace = session.workspace or "default"
    if not by_workspace[workspace] then
      by_workspace[workspace] = {}
      names[#names + 1] = workspace
    end
    table.insert(by_workspace[workspace], session)
  end
  table.sort(names)
  for _, sessions_in_ws in pairs(by_workspace) do
    table.sort(sessions_in_ws, function(a, b)
      if a.name ~= b.name then
        return (a.name or "") < (b.name or "")
      end
      return (a.pane_id or 0) < (b.pane_id or 0)
    end)
  end
  return names, by_workspace
end

local function max_label_width(cfg)
  local width = 0
  for _, label in pairs(cfg.labels) do
    width = math.max(width, M.display_width(label))
  end
  return width
end

local function session_lines(session, cfg, widths, out)
  local icon = cfg.icons[session.state] or "•"
  local label = cfg.labels[session.state] or session.state
  local name = M.truncate(session.name or "?", widths.name)
  out[#out + 1] = " "
    .. icon
    .. " "
    .. M.pad(name, widths.name)
    .. " "
    .. paint(label, LABEL_COLORS[session.state] or "0", cfg.ansi)
  if cfg.show_title and session.title and session.title ~= "" then
    local title = M.truncate(session.title, widths.name + widths.label + 1)
    out[#out + 1] = paint("    " .. title, "2", cfg.ansi)
  end
end

-- セッション一覧をサイドバー描画用の行配列に変換する (純粋関数)。
-- max_cols (サイドバーペインの桁数) を渡すと全行がその幅に収まる
function M.lines(sessions, cfg, max_cols)
  local label_width = max_label_width(cfg)
  local name_width = cfg.max_name_width
  if max_cols then
    -- 行構成: " " + icon(2) + " " + name + " " + label
    name_width = math.max(8, math.min(name_width, max_cols - label_width - 5))
  end
  local widths = { name = name_width, label = label_width }

  local out = {}
  out[#out + 1] = ""
  out[#out + 1] = paint(" " .. M.truncate(cfg.sidebar.title, name_width + label_width + 4), "1", cfg.ansi)
  out[#out + 1] = paint(" " .. string.rep("─", name_width + label_width + 4), "2", cfg.ansi)

  if #sessions == 0 then
    out[#out + 1] = ""
    out[#out + 1] = paint("  (no sessions)", "2", cfg.ansi)
    return out
  end

  local names, by_workspace = group_by_workspace(sessions)
  for _, workspace in ipairs(names) do
    out[#out + 1] = ""
    out[#out + 1] = paint(M.truncate(" [" .. workspace .. "]", name_width + label_width + 5), "36", cfg.ansi)
    for _, session in ipairs(by_workspace[workspace]) do
      session_lines(session, cfg, widths, out)
    end
  end

  local counts = M.counts(sessions)
  out[#out + 1] = ""
  out[#out + 1] = paint(
    string.format(" %d session%s", counts.total, counts.total == 1 and "" or "s"),
    "2",
    cfg.ansi
  )
  return out
end

return M
