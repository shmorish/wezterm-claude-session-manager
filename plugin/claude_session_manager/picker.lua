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

-- ジャンプ処理の本体。mux の activate だけでは GUI のキーボードフォーカスが
-- 追従しないため、GUI アクション (ActivateTab) とウィンドウフォーカスまで行う
local function apply_focus(wezterm, window, pane, session)
  -- perform_action(SwitchToWorkspace) は既に閉じたポップアップペインを
  -- 参照して失敗することがあるため、mux レベル API で切り替える
  if session.workspace and session.workspace ~= wezterm.mux.get_active_workspace() then
    wezterm.mux.set_active_workspace(session.workspace)
  end

  local target = wezterm.mux.get_pane(session.pane_id)
  if not target then
    return
  end
  target:activate() -- mux 上でペインと、それを含むタブがアクティブになる

  local mux_window = session.mux_window_id and wezterm.mux.get_window(session.mux_window_id)
  if not mux_window then
    mux_window = target:tab():window()
  end
  local gui_window = mux_window and mux_window:gui_window()
  if not gui_window then
    -- workspace 切替直後などは gui_window が取れないことがある (再アサートで拾う)
    return
  end

  local target_tab_id = target:tab():tab_id()
  for index, tab in ipairs(mux_window:tabs()) do
    if tab:tab_id() == target_tab_id then
      gui_window:perform_action(wezterm.action.ActivateTab(index - 1), target)
      break
    end
  end
  gui_window:focus()
end

-- 選択されたセッションのペインへジャンプする。
-- 別 workspace なら切り替え、別 OS ウィンドウならフォーカスを移す。
-- ポップアップクローズ等との競合に備えて少し遅れてもう一度フォーカスを当て直す
function M.focus_session(wezterm, window, pane, session)
  local function attempt()
    local ok, err = pcall(apply_focus, wezterm, window, pane, session)
    if not ok then
      wezterm.log_error("claude-session-manager: failed to focus session: " .. tostring(err))
    end
  end
  attempt()
  wezterm.time.call_after(0.3, attempt)
end

-- pane_id だけからセッション相当の情報を組み立ててジャンプする (user-var 経由)。
-- 発行元がこのウィンドウのポップアップなら、ジャンプの前に必ず閉じる
function M.jump_to_pane(wezterm, window, pane, pane_id)
  M.close_popup_if_source(wezterm, window, pane)
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
-- 選択結果は SetUserVar エスケープシーケンスで Lua 側に渡す。
-- キャンセル時 (Esc) は呼び出し元ペインへ「戻る」ジャンプを発行する。
-- ペインを自分で閉じるとエスケープ列のパースやジャンプと競合するため、
-- user-var 発行後は待機し、クローズは常に Lua 側 (kill) が行う
local function build_script(fzf, wezterm_bin, list_file, binds, origin_pane_id, cfg)
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
  target=${selected%%%%$'\t'*}
else
  target=%d
fi
printf '\033]1337;SetUserVar=%s=%%s\007' "$(printf %%s "$target" | /usr/bin/base64)"
exec sleep 15
]],
    fzf,
    wezterm_bin,
    cfg.picker.preview_lines,
    cfg.picker.preview_window,
    bind_option,
    list_file,
    origin_pane_id,
    M.JUMP_USER_VAR
  )
end

-- window ごとに開いているポップアップの pane_id と呼び出し元の pane_id を
-- wezterm.GLOBAL のフラットなスカラーキーで追跡する (トグル用)。
-- GLOBAL にテーブルを入れると userdata プロキシ化して読み戻せないため
local function popup_key(window)
  return "claude_session_manager_popup_" .. tostring(window:mux_window():window_id())
end

local function origin_key(window)
  return "claude_session_manager_origin_" .. tostring(window:mux_window():window_id())
end

local function stored_pane_id(wezterm, key)
  local value = wezterm.GLOBAL[key]
  if value == nil or value == false then
    return nil
  end
  return tonumber(tostring(value))
end

local function clear_popup_state(wezterm, window)
  wezterm.GLOBAL[popup_key(window)] = false
  wezterm.GLOBAL[origin_key(window)] = false
end

-- ポップアップペインのプロセスツリー全体 (スクリプト・サブシェル・fzf) を kill する。
-- ルートの bash が死ぬとペインが閉じる。fzf はペインが閉じても生き残ることが
-- あるため、ツリーの葉から順に全 pid を明示的に kill する
local function kill_popup_processes(wezterm, popup_pane)
  local ok, info = pcall(function()
    return popup_pane:get_foreground_process_info()
  end)
  if not ok or type(info) ~= "table" then
    return
  end
  local pids = {}
  local function walk(node)
    if type(node) ~= "table" then
      return
    end
    for _, child in pairs(node.children or {}) do
      walk(child)
    end
    if node.pid then
      pids[#pids + 1] = node.pid
    end
  end
  walk(info)
  for _, pid in ipairs(pids) do
    pcall(wezterm.run_child_process, { "/bin/kill", tostring(pid) })
  end
end

-- pane がこのウィンドウで開いているポップアップ本体なら閉じて追跡情報をクリアする。
-- user-var の発行元ペイン (=ポップアップ) をジャンプ前に確実に始末するために使う
function M.close_popup_if_source(wezterm, window, pane)
  local stored = stored_pane_id(wezterm, popup_key(window))
  if not stored or stored ~= pane:pane_id() then
    return
  end
  clear_popup_state(wezterm, window)
  kill_popup_processes(wezterm, pane)
end

-- ポップアップ用ペインを開く。popup_mode = "tab" なら一時的な新規タブで
-- 全画面表示し、"split" なら従来どおり下部分割ペインを使う。
-- どちらも選択/キャンセル時に kill されてペインごと消える
local function spawn_popup(cfg, window, pane, script_file)
  local args = { "/bin/bash", script_file }
  if cfg.picker.popup_mode == "split" then
    return pane:split({
      direction = "Bottom",
      size = cfg.picker.popup_size,
      top_level = true,
      args = args,
    })
  end
  local tab, popup = window:mux_window():spawn_tab({ args = args })
  pcall(function()
    tab:set_title(cfg.picker.title)
  end)
  popup:activate()
  return popup
end

-- プレビュー付きポップアップ (fzf) を開く。失敗したら false を返す
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
  local script =
    build_script(fzf, wezterm_bin, list_file, render.fzf_binds(#choices), pane:pane_id(), cfg)
  if not write_file(script_file, script) then
    return false
  end

  local ok, popup = pcall(spawn_popup, cfg, window, pane, script_file)
  if not ok or not popup then
    wezterm.log_error("claude-session-manager: failed to open popup: " .. tostring(popup))
    return false
  end
  wezterm.GLOBAL[popup_key(window)] = popup:pane_id()
  wezterm.GLOBAL[origin_key(window)] = pane:pane_id()
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

-- セッション一覧を表示する (fzf ポップアップ、なければ InputSelector)。
-- ポップアップが既に開いていればトグルとして閉じ、呼び出し元へフォーカスを戻す。
-- スクリプトの user-var 発行には依存せず、Lua 側で kill とフォーカスを完結させる
function M.show(wezterm, cfg, window, pane)
  local existing_id = stored_pane_id(wezterm, popup_key(window))
  if existing_id then
    local origin_id = stored_pane_id(wezterm, origin_key(window))
    clear_popup_state(wezterm, window)
    local ok, popup_pane = pcall(wezterm.mux.get_pane, existing_id)
    if ok and popup_pane then
      kill_popup_processes(wezterm, popup_pane)
      if origin_id then
        M.jump_to_pane(wezterm, window, pane, origin_id)
      end
      return
    end
  end

  local sessions = discovery.collect(wezterm, cfg)
  if cfg.picker.preview and #sessions > 0 then
    if show_fzf_popup(wezterm, cfg, window, pane, sessions) then
      return
    end
  end
  show_selector(wezterm, cfg, window, pane, sessions)
end

return M
