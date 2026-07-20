local M = {}

M.STATES = { "running", "waiting", "done" }

local function matches_any(lower_text, patterns)
  for _, pattern in ipairs(patterns or {}) do
    if lower_text:find(pattern:lower(), 1, true) then
      return true
    end
  end
  return false
end

-- ペイン末尾のテキストからセッション状態を判定する。
-- running を waiting より先に見るのは、生成中の本文に "do you want" が
-- 含まれることはあっても、ステータス行の "esc to interrupt" が
-- 本文に現れることはほぼないため。
function M.classify(text, patterns)
  if type(text) ~= "string" or text == "" then
    return "done"
  end
  local lower_text = text:lower()
  if matches_any(lower_text, patterns.running) then
    return "running"
  end
  if matches_any(lower_text, patterns.waiting) then
    return "waiting"
  end
  return "done"
end

return M
