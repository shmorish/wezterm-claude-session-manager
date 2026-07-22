# wezterm-claude-session-manager

A [WezTerm](https://wezterm.org/) plugin that lists every running [Claude Code](https://claude.com/claude-code) session in a popup with **live preview** — see each session's status and screen at a glance, then jump to it with a single keystroke.

```
├─────────────────────────────────┬──────────────────────────────────┤
│ Claude Sessions >               │ ✻ Architecting… (12s · ↓ 3.1k)   │
│ ▌1. 🟡 dotfiles      Running    │                                  │
│  2. 🔴 my-app        Waiting    │ ❯ Do you want to make this edit? │
│  3. 🟢 api-server    Done       │   ← live screen of the selection │
╰─────────────────────────────────┴──────────────────────────────────╯
```

Move the cursor with `↑`/`↓` and the preview on the right follows in real time, so you can watch what any session is doing before you switch to it.

## Status

Each session is classified into one of three states:

- **Running** 🟡 — Claude is generating output or running a tool.
- **Waiting** 🔴 — Claude is waiting for you (e.g. a permission prompt). Needs your attention.
- **Done** 🟢 — Claude has finished responding and is idle, waiting for your next input.

## Usage

Press **`CMD+s`** to open the popup, then:

- **Number keys (`1`–`9`)** — jump straight to that session's pane the moment you press it (switches workspace too if the session lives in another one).
- **`↑`/`↓`** — move the cursor; the preview follows. Press **Enter** to select.
- **Type any text** — fuzzy-filter the list.
- **Esc** or **`CMD+s`** again — close and return focus to your original pane (the popup tab disappears automatically).

By default the popup opens full-screen as a **temporary new tab**, so it never disturbs your existing pane layout. Set `picker.popup_mode = "split"` to use the classic bottom split pane instead.

The preview popup is powered by [fzf](https://github.com/junegunn/fzf) (auto-detected from your login shell's `PATH`). On systems without fzf it falls back automatically to WezTerm's built-in `InputSelector` modal.

By default the preview shows a formatted view of **Claude's conversation log** (the tail of `~/.claude/projects/<cwd>/*.jsonl`). Claude Code's TUI runs in the alternate screen and has no scrollback, so reading the pane text (`get-text`) yields no history and leaves large blank areas when a session is idle — the conversation log avoids that. If no log is found, it falls back to the pane screen. Set `picker.preview_source = "pane"` to always use the pane screen.

## Requirements

- WezTerm 20240127 or later
- [Claude Code](https://claude.com/claude-code) — the sessions this plugin discovers (native binary or the npm build)
- [fzf](https://github.com/junegunn/fzf) 0.25 or later — **optional**, used only for the preview popup. Without it, the plugin falls back to WezTerm's built-in `InputSelector` modal (list only, no preview).
- Local panes only — SSH / mux remote panes expose no process info, so they never appear in the list.

### Platform support

This plugin is developed and tested on **macOS**.

- **macOS** — fully supported out of the box.
- **Linux** — the preview popup works (it shells out to `/bin/bash` / `/bin/zsh`), but the default `CMD+s` keybind does not exist; set your own key with `keybind = { key = "s", mods = "SUPER" }` (or `CTRL`).
- **Windows** — the fzf preview popup is **not supported** (it relies on a POSIX shell and `/tmp`); the plugin automatically falls back to the `InputSelector` modal. You must also change the default `CMD+s` keybind.

If `CMD` is not a modifier on your platform, either change `keybind` or disable it and bind the action manually (see [Installation](#installation)).

## Installation

Add the following to `~/.config/wezterm/wezterm.lua`:

```lua
local wezterm = require("wezterm")
local config = wezterm.config_builder()

local csm = wezterm.plugin.require("https://github.com/shmorish/wezterm-claude-session-manager")
csm.apply_to_config(config, {})

return config
```

That alone binds the session list modal to **`CMD+s`**.

To change the key, or to disable the automatic binding:

```lua
-- Change the key
csm.apply_to_config(config, { keybind = { key = "b", mods = "CTRL|SHIFT" } })

-- Disable the automatic binding and wire it up manually
csm.apply_to_config(config, { keybind = false })
table.insert(config.keys, { key = "b", mods = "LEADER", action = csm.action.show_picker })
```

## Configuration

Override the defaults via the second argument to `apply_to_config` (everything is optional):

```lua
csm.apply_to_config(config, {
  picker = {
    preview = true,           -- use the fzf popup (false = always InputSelector)
    popup_mode = "tab",       -- "tab" = full-screen temporary tab / "split" = bottom split pane
    popup_size = 0.45,        -- pane height (fraction) when popup_mode = "split"
    preview_window = "right,60%",  -- fzf's --preview-window
    preview_lines = 40,       -- number of trailing lines to show in the preview
    preview_source = "transcript", -- "transcript" = Claude conversation log / "pane" = pane screen (get-text)
    preview_messages = 60,    -- number of recent messages to pull from the transcript
    preview_colors = true,    -- keep pane text colors/styles (get-text --escapes)
    -- The following apply to the InputSelector fallback
    title = "Claude Code Sessions",
    fuzzy = false,            -- true to open in fuzzy-search mode from the start
    alphabet = "123456789",   -- selection keys assigned to each row
    center = true,            -- horizontally center the list within the pane width
  },
  icons  = { running = "🟡", waiting = "🔴", done = "🟢" },
  labels = { running = "Running", waiting = "Waiting", done = "Done" },
  patterns = {
    -- Substring match against the pane's trailing text (case-insensitive)
    running = { "esc to interrupt" },
    waiting = { "do you want", "❯ 1." },
    -- Lua patterns matched against process name / argv
    process = { "^claude$", "claude%-code" },
  },
  keybind = { key = "s", mods = "CMD" },  -- key to show the modal (false = no automatic binding)
  scan_lines = 40,            -- trailing lines of pane text read for state detection
  cwd_display = "basename",   -- "basename" | "shortened" | "full"
  max_name_width = 18,        -- display width of the project name
  show_title = true,          -- show the pane title (current task) in the list
})
```

To localize the labels (e.g. Japanese):

```lua
csm.apply_to_config(config, {
  labels = { running = "実行中", waiting = "停止中", done = "完了" },
})
```

### Custom use

You can pull the raw data into your own status bar or elsewhere:

```lua
local counts = csm.counts()     -- { running = 1, waiting = 0, done = 2, total = 3 }
local sessions = csm.sessions() -- { { pane_id, workspace, cwd, name, state, title }, ... }
```

## How state detection works

For each pane, the plugin inspects `get_foreground_process_info()` to detect a Claude Code process (the native `claude` binary, the npm build `node .../claude-code/cli.js`, and matches anywhere in the child process tree), then pattern-matches the pane's trailing text to determine the state:

1. Contains `esc to interrupt` → **Running**
2. Contains `do you want` / `❯ 1.` (permission prompt) → **Waiting**
3. Neither → **Done**

If a Claude Code update changes the TUI wording, override `patterns` to match.

## Development

```sh
# Unit tests (no wezterm required / lua 5.3+)
bash tests/run.sh
```

To load a local working copy as a plugin:

```lua
local csm = wezterm.plugin.require("file:///path/to/wezterm-claude-session-manager")
```

`plugin.require` performs a git clone, so **only committed content** is reflected.
To try uncommitted changes, load it directly:

```lua
package.path = "/path/to/wezterm-claude-session-manager/plugin/?.lua;" .. package.path
local csm = dofile("/path/to/wezterm-claude-session-manager/plugin/init.lua")
```

WezTerm does not auto-update plugins. To pull in new changes, run
`wezterm.plugin.update_all()` inside WezTerm (or from the debug overlay, Ctrl+Shift+L) and reload your config.
