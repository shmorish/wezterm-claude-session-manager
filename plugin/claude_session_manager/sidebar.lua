local discovery = require("claude_session_manager.discovery")
local render = require("claude_session_manager.render")

local M = {}

local CLEAR = string.char(27) .. "[2J" .. string.char(27) .. "[H" .. string.char(27) .. "[?25l"

-- 直近の描画内容 (window key -> body)。ちらつき防止用のキャッシュで、
-- 設定リロードで消えても一度余分に描画されるだけなのでモジュールローカルで持つ
local last_rendered = {}

local function window_key(window)
  return tostring(window:mux_window():window_id())
end

-- サイドバーの pane_id は設定リロードを跨いで追跡したいので wezterm.GLOBAL に置く。
-- ネストしたテーブルは読み戻しが userdata プロキシになり扱いづらいため、
-- window ごとのフラットなスカラーキーに数値だけを保存する
local function global_key(key)
  return "claude_session_manager_sidebar_" .. key
end

local function stored_pane_id(wezterm, key)
  local value = wezterm.GLOBAL[global_key(key)]
  if value == nil or value == false then
    return nil
  end
  return tonumber(tostring(value))
end

local function store_pane_id(wezterm, key, pane_id)
  wezterm.GLOBAL[global_key(key)] = pane_id or false
end

local function live_pane(wezterm, pane_id)
  if not pane_id then
    return nil
  end
  local ok, pane = pcall(wezterm.mux.get_pane, pane_id)
  if ok then
    return pane
  end
  return nil
end

-- CloseCurrentPane は渡した pane ではなくアクティブペインに作用するため、
-- サイドバーを一度アクティブ化してから閉じ、フォーカスを元のペインに戻す
local function close_pane(wezterm, window, sidebar_pane, return_pane)
  local ok, err = pcall(function()
    sidebar_pane:activate()
    window:perform_action(wezterm.action.CloseCurrentPane({ confirm = false }), sidebar_pane)
  end)
  if not ok then
    wezterm.log_error("claude-session-manager: failed to close sidebar: " .. tostring(err))
  end
  if return_pane then
    pcall(function()
      return_pane:activate()
    end)
  end
end

local function open_sidebar(wezterm, cfg, pane)
  local ok, sidebar_pane = pcall(function()
    -- pane:split は SplitPane アクションと異なり args をトップレベルに取る
    return pane:split({
      direction = cfg.sidebar.position,
      size = cfg.sidebar.width,
      top_level = true,
      args = cfg.sidebar.command,
    })
  end)
  if not ok or not sidebar_pane then
    wezterm.log_error("claude-session-manager: failed to open sidebar: " .. tostring(sidebar_pane))
    return nil
  end
  -- フォーカスは元のペインに戻す
  pcall(function()
    pane:activate()
  end)
  return sidebar_pane:pane_id()
end

-- キーバインドから呼ばれる開閉トグル
function M.toggle(wezterm, cfg, window, pane)
  local key = window_key(window)
  local existing = live_pane(wezterm, stored_pane_id(wezterm, key))

  if existing then
    close_pane(wezterm, window, existing, pane)
    store_pane_id(wezterm, key, nil)
    last_rendered[key] = nil
    return
  end

  local pane_id = open_sidebar(wezterm, cfg, pane)
  if pane_id then
    store_pane_id(wezterm, key, pane_id)
    last_rendered[key] = nil
  end
end

local function refresh(wezterm, cfg, window)
  local key = window_key(window)
  local pane_id = stored_pane_id(wezterm, key)
  if not pane_id then
    return
  end

  local sidebar_pane = live_pane(wezterm, pane_id)
  if not sidebar_pane then
    -- ユーザーが手動で閉じた等。次のトグルで再度開けるよう掃除する
    store_pane_id(wezterm, key, nil)
    return
  end

  local sessions = discovery.collect(wezterm, cfg)
  local cols
  pcall(function()
    cols = sidebar_pane:get_dimensions().cols
  end)
  local body = table.concat(render.lines(sessions, cfg, cols), "\r\n")

  -- 内容が変わった時だけ描き直してちらつきを防ぐ
  if last_rendered[key] == body then
    return
  end
  last_rendered[key] = body
  pcall(function()
    sidebar_pane:inject_output(CLEAR .. body)
  end)
end

-- update-status (既定 1 秒間隔) で開いているサイドバーを再描画する
function M.attach(wezterm, get_cfg)
  wezterm.on("update-status", function(window, _pane)
    pcall(refresh, wezterm, get_cfg(), window)
  end)
end

return M
