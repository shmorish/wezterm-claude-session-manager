local M = { failures = 0, total = 0 }

local function fmt(value)
  if type(value) == "string" then
    return string.format("%q", value)
  end
  return tostring(value)
end

function M.eq(actual, expected, label)
  M.total = M.total + 1
  if actual ~= expected then
    M.failures = M.failures + 1
    io.write(string.format("  FAIL %s: expected %s, got %s\n", label, fmt(expected), fmt(actual)))
  end
end

function M.ok(condition, label)
  M.eq(not not condition, true, label)
end

function M.contains(haystack, needle, label)
  M.total = M.total + 1
  if type(haystack) ~= "string" or not haystack:find(needle, 1, true) then
    M.failures = M.failures + 1
    io.write(string.format("  FAIL %s: %s not found in %s\n", label, fmt(needle), fmt(haystack)))
  end
end

function M.finish(name)
  io.write(string.format("%s: %d/%d passed\n", name, M.total - M.failures, M.total))
  os.exit(M.failures == 0 and 0 or 1)
end

return M
