local wezterm = require("wezterm")

-- wezterm.plugin.require で clone された自分の場所を探し、
-- サブモジュールを require できるよう package.path に追加する。
-- (ローカル開発で dofile する場合は先に package.path を通しておく)
local function find_plugin_dir()
  local ok, plugins = pcall(wezterm.plugin.list)
  if not ok then
    return nil
  end
  for _, plugin in ipairs(plugins) do
    if plugin.component:find("claude", 1, true) and plugin.component:find("session", 1, true) then
      return plugin.plugin_dir
    end
  end
  return nil
end

local plugin_dir = find_plugin_dir()
if plugin_dir then
  local sep = package.config:sub(1, 1)
  local path = plugin_dir .. sep .. "plugin" .. sep .. "?.lua"
  if not package.path:find(path, 1, true) then
    package.path = package.path .. ";" .. path
  end
end

local config_mod = require("claude_session_manager.config")
local discovery = require("claude_session_manager.discovery")
local render = require("claude_session_manager.render")
local picker = require("claude_session_manager.picker")

local M = {}

local current_config = config_mod.defaults

-- fzf ポップアップからの選択結果 (SetUserVar) を受け取ってジャンプする
wezterm.on("user-var-changed", function(window, pane, name, value)
  if name ~= picker.JUMP_USER_VAR then
    return
  end
  local pane_id = tonumber(value)
  if pane_id then
    picker.jump_to_pane(wezterm, window, pane, pane_id)
  end
end)

function M.apply_to_config(config, opts)
  current_config = config_mod.merge(config_mod.defaults, opts or {})

  -- 既定で CMD+s にモーダル表示を割り当てる (keybind = false で無効化)
  local keybind = current_config.keybind
  if config and keybind then
    config.keys = config.keys or {}
    table.insert(config.keys, {
      key = keybind.key,
      mods = keybind.mods,
      action = M.action.show_picker,
    })
  end
end

M.action = {
  show_picker = wezterm.action_callback(function(window, pane)
    picker.show(wezterm, current_config, window, pane)
  end),
}
-- 旧サイドバー時代の名前からの後方互換
M.action.toggle_sidebar = M.action.show_picker

-- カスタムステータスバー等で使える生データ
function M.sessions()
  return discovery.collect(wezterm, current_config)
end

function M.counts()
  return render.counts(M.sessions())
end

return M
