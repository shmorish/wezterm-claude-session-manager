local M = {}

local function basename(path)
  if type(path) ~= "string" then
    return nil
  end
  return path:match("([^/\\]+)[/\\]*$")
end

local function candidate_strings(info)
  local candidates = {}
  local function add(value)
    if type(value) == "string" and value ~= "" then
      candidates[#candidates + 1] = value
    end
  end
  add(info.name)
  add(basename(info.executable))
  for _, arg in ipairs(info.argv or {}) do
    add(arg)
    add(basename(arg))
  end
  return candidates
end

local function matches(info, patterns)
  for _, candidate in ipairs(candidate_strings(info)) do
    for _, pattern in ipairs(patterns) do
      if candidate:match(pattern) then
        return true
      end
    end
  end
  return false
end

-- LocalProcessInfo (get_foreground_process_info の戻り値) が Claude Code か判定する。
-- ツール実行中はフォアグラウンドが子プロセスに移ることがあるため、
-- children ツリーも再帰的に走査する
function M.is_claude(info, patterns)
  if type(info) ~= "table" then
    return false
  end
  if matches(info, patterns or {}) then
    return true
  end
  for _, child in pairs(info.children or {}) do
    if M.is_claude(child, patterns) then
      return true
    end
  end
  return false
end

return M
