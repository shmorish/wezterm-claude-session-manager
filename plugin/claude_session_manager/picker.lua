local discovery = require("claude_session_manager.discovery")
local render = require("claude_session_manager.render")

local M = {}

M.JUMP_USER_VAR = "claude_session_jump"

-- fzf の実行パス。false = 探したが見つからなかった
local fzf_path_cache = nil

-- ログインシェル経由で fzf を探す (シェルプラグイン管理下の PATH にも対応)
local function find_fzf(wezterm)
  if fzf_path_cache ~= nil then
    return fzf_path_cache or nil
  end
  for _, argv in ipairs({
    { "/bin/zsh", "-lic", "command -v fzf" },
    { "/bin/bash", "-lc", "command -v fzf" },
  }) do
    local ok, _, stdout = pcall(wezterm.run_child_process, argv)
    if ok and stdout then
      for line in stdout:gmatch("[^\r\n]+") do
        if line:match("/fzf$") then
          fzf_path_cache = line
          return line
        end
      end
    end
  end
  fzf_path_cache = false
  return nil
end

local function temp_dir()
  return os.getenv("TMPDIR") or "/tmp"
end

local function write_file(path, content)
  local file, err = io.open(path, "w")
  if not file then
    return false, err
  end
  file:write(content)
  file:close()
  return true
end

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

-- pane_id だけからセッション相当の情報を組み立ててジャンプする (user-var 経由)
function M.jump_to_pane(wezterm, window, pane, pane_id)
  local target = wezterm.mux.get_pane(pane_id)
  if not target then
    return
  end
  local session = { pane_id = pane_id }
  pcall(function()
    local mux_window = target:tab():window()
    session.workspace = mux_window:get_workspace()
    session.mux_window_id = mux_window:window_id()
  end)
  M.focus_session(wezterm, window, pane, session)
end

-- fzf を動かす一時スクリプトを生成する。
-- 選択結果は SetUserVar エスケープシーケンスで Lua 側に渡す
local function build_script(fzf, wezterm_bin, list_file, binds, cfg)
  local bind_option = binds ~= "" and ("--bind='" .. binds .. "' ") or ""
  return string.format(
    [[#!/bin/bash
set -u
selected=$("%s" --ansi --delimiter='\t' --with-nth=2.. --layout=reverse --no-info \
  --prompt='Claude Sessions > ' \
  --preview='"%s" cli get-text --pane-id {1} | tail -n %d' \
  --preview-window='%s' \
  %s< "%s")
if [ -n "$selected" ]; then
  pane_id=${selected%%%%$'\t'*}
  printf '\033]1337;SetUserVar=%s=%%s\007' "$(printf %%s "$pane_id" | /usr/bin/base64)"
  sleep 0.2
fi
]],
    fzf,
    wezterm_bin,
    cfg.picker.preview_lines,
    cfg.picker.preview_window,
    bind_option,
    list_file,
    M.JUMP_USER_VAR
  )
end

-- プレビュー付きポップアップペイン (fzf) を開く。失敗したら false を返す
local function show_fzf_popup(wezterm, cfg, window, pane, sessions)
  local fzf = find_fzf(wezterm)
  if not fzf then
    return false
  end

  local choices = render.choices(sessions, cfg)
  local key = tostring(window:mux_window():window_id())
  local list_file = temp_dir() .. "/claude-session-manager-" .. key .. ".list"
  local script_file = temp_dir() .. "/claude-session-manager-" .. key .. ".sh"

  local lines = render.fzf_lines(choices)
  if not write_file(list_file, table.concat(lines, "\n") .. "\n") then
    return false
  end
  local wezterm_bin = (wezterm.executable_dir or "") .. "/wezterm"
  local script = build_script(fzf, wezterm_bin, list_file, render.fzf_binds(#choices), cfg)
  if not write_file(script_file, script) then
    return false
  end

  local ok, popup = pcall(function()
    return pane:split({
      direction = "Bottom",
      size = cfg.picker.popup_size,
      top_level = true,
      args = { "/bin/bash", script_file },
    })
  end)
  if not ok or not popup then
    wezterm.log_error("claude-session-manager: failed to open popup: " .. tostring(popup))
    return false
  end
  return true
end

-- InputSelector モーダル (fzf が無い環境向けフォールバック)
local function show_selector(wezterm, cfg, window, pane, sessions)
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

-- セッション一覧を表示する (fzf ポップアップ、なければ InputSelector)
function M.show(wezterm, cfg, window, pane)
  local sessions = discovery.collect(wezterm, cfg)
  if cfg.picker.preview and #sessions > 0 then
    if show_fzf_popup(wezterm, cfg, window, pane, sessions) then
      return
    end
  end
  show_selector(wezterm, cfg, window, pane, sessions)
end

return M
