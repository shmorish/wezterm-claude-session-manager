local discovery = require("claude_session_manager.discovery")
local render = require("claude_session_manager.render")

local M = {}

-- 選択されたセッションのペインへジャンプする。
-- 別 workspace なら切り替え、別 OS ウィンドウならフォーカスを移す
function M.focus_session(wezterm, window, pane, session)
  local ok, err = pcall(function()
    if session.workspace and session.workspace ~= wezterm.mux.get_active_workspace() then
      window:perform_action(
        wezterm.action.SwitchToWorkspace({ name = session.workspace }),
        pane
      )
    end

    local target = wezterm.mux.get_pane(session.pane_id)
    if target then
      target:activate() -- ペインと、それを含むタブがアクティブになる
    end

    local mux_window = session.mux_window_id and wezterm.mux.get_window(session.mux_window_id)
    if mux_window then
      local gui_window = mux_window:gui_window()
      if gui_window then
        gui_window:focus()
      else
        -- workspace 切替直後は gui_window が取れないことがあるので一度だけ遅延リトライ
        wezterm.time.call_after(0.2, function()
          local retried = mux_window:gui_window()
          if retried then
            retried:focus()
          end
        end)
      end
    end
  end)
  if not ok then
    wezterm.log_error("claude-session-manager: failed to focus session: " .. tostring(err))
  end
end

-- セッション一覧モーダル (InputSelector) を表示する
function M.show(wezterm, cfg, window, pane)
  local sessions = discovery.collect(wezterm, cfg)
  local by_id = {}
  for _, session in ipairs(sessions) do
    by_id[tostring(session.pane_id)] = session
  end

  local cols
  pcall(function()
    cols = pane:get_dimensions().cols
  end)

  window:perform_action(
    wezterm.action.InputSelector({
      title = cfg.picker.title,
      fuzzy = cfg.picker.fuzzy,
      alphabet = cfg.picker.alphabet,
      choices = render.choices(sessions, cfg, cols),
      action = wezterm.action_callback(function(cb_window, cb_pane, id, _label)
        -- id が nil (Esc) や空 (プレースホルダ) なら何もしない
        local session = id and by_id[id]
        if session then
          M.focus_session(wezterm, cb_window, cb_pane, session)
        end
      end),
    }),
    pane
  )
end

return M
