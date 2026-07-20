local detect = require("claude_session_manager.detect")
local state = require("claude_session_manager.state")
local render = require("claude_session_manager.render")

local M = {}

local function pane_cwd(pane, info)
  local ok, url = pcall(function()
    return pane:get_current_working_dir()
  end)
  if ok and url then
    local ok_path, file_path = pcall(function()
      return url.file_path
    end)
    if ok_path and type(file_path) == "string" then
      return file_path
    end
    if type(url) == "string" then
      return (url:gsub("^file://[^/]*", ""))
    end
  end
  return info and info.cwd or nil
end

local function build_session(wezterm, cfg, workspace, pane)
  local info = pane:get_foreground_process_info()
  if not info or not detect.is_claude(info, cfg.patterns.process) then
    return nil
  end
  local text = pane:get_lines_as_text(cfg.scan_lines)
  local cwd = pane_cwd(pane, info)
  local title = pane:get_title()
  return {
    pane_id = pane:pane_id(),
    workspace = workspace,
    cwd = cwd,
    name = render.project_name(cwd, cfg.cwd_display, wezterm.home_dir) or title,
    state = state.classify(text, cfg.patterns),
    title = title,
  }
end

-- 全 workspace / window / tab を走査して Claude Code が動くペインを集める。
-- mux オブジェクトは列挙と参照の間に消えることがあるため pcall で守る
function M.collect(wezterm, cfg)
  local sessions = {}
  local ok_windows, windows = pcall(wezterm.mux.all_windows)
  if not ok_windows then
    return sessions
  end
  for _, mux_window in ipairs(windows) do
    pcall(function()
      local workspace = mux_window:get_workspace()
      for _, tab in ipairs(mux_window:tabs()) do
        for _, pane in ipairs(tab:panes()) do
          local ok, session = pcall(build_session, wezterm, cfg, workspace, pane)
          if ok and session then
            sessions[#sessions + 1] = session
          end
        end
      end
    end)
  end
  return sessions
end

return M
