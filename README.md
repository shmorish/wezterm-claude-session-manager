# wezterm-claude-session-manager

A wezterm plugin that lists all running [Claude Code](https://claude.com/claude-code) sessions in a popup with **live preview** — see each session's status and screen at a glance, then jump to it with a single keystroke.

wezterm 上で並行して動いている Claude Code のセッションを、**ライブプレビュー付きのポップアップ**で一覧表示する wezterm プラグインです。↑↓で選択中のセッションの画面がリアルタイムで右側に表示され、数字キー一発でそのペインへジャンプできます。

```
├─────────────────────────────────┬──────────────────────────────────┤
│ Claude Sessions >               │ ✻ Architecting… (12s · ↓ 3.1k)   │
│ ▌1. 🟡 dotfiles      Running    │                                  │
│  2. 🔴 my-app        Waiting    │ ❯ Do you want to make this edit? │
│  3. 🟢 api-server    Done       │   ← 選択中セッションの実画面     │
╰─────────────────────────────────┴──────────────────────────────────╯
```

- **Running** 🟡 — Claude が生成・ツール実行中
- **Waiting** 🔴 — 権限確認などでユーザーの応答待ち(要対応)
- **Done** 🟢 — 応答が終わり、次の入力を待っているだけ

**`CMD+s`** でポップアップを開き:

- **数字キー (1〜9)** — 押した瞬間にそのセッションのペインへジャンプ(別 workspace は workspace ごと切り替え)
- **↑↓** — カーソル移動。右側のプレビューが追従する。**Enter** で選択
- **文字入力** — ファジー検索で絞り込み
- **Esc** または **もう一度 `CMD+s`** — 閉じて元のペインにフォーカスが戻る(ポップアップペインは自動で消える)

プレビュー付きポップアップには [fzf](https://github.com/junegunn/fzf) を使います(ログインシェルの PATH から自動検出)。fzf が無い環境では wezterm 組み込みの InputSelector モーダルに自動フォールバックします。

## 必要環境

- wezterm 20240127 以降
- fzf 0.25 以降(プレビュー付きポップアップに使用。無ければ InputSelector にフォールバック)
- ローカルペインのみ対応(SSH / mux リモートのペインはプロセス情報が取れないため一覧に出ません)

## インストール

`~/.config/wezterm/wezterm.lua` に追加:

```lua
local wezterm = require("wezterm")
local config = wezterm.config_builder()

local csm = wezterm.plugin.require("https://github.com/shmorish/wezterm-claude-session-manager")
csm.apply_to_config(config, {})

return config
```

これだけで **`CMD+s`** にセッション一覧モーダルが割り当てられます。

キーを変えたい / 自動割り当てを止めたい場合:

```lua
-- キーを変更
csm.apply_to_config(config, { keybind = { key = "b", mods = "CTRL|SHIFT" } })

-- 自動割り当てを無効化して手動で設定
csm.apply_to_config(config, { keybind = false })
table.insert(config.keys, { key = "b", mods = "LEADER", action = csm.action.show_picker })
```

## 設定

`apply_to_config` の第2引数で上書きできます(すべて省略可):

```lua
csm.apply_to_config(config, {
  picker = {
    preview = true,           -- fzf ポップアップを使う (false で常に InputSelector)
    popup_size = 0.45,        -- ポップアップペインの高さ (割合)
    preview_window = "right,60%",  -- fzf の --preview-window
    preview_lines = 40,       -- プレビューに表示する行数
    -- 以下は InputSelector フォールバック時の設定
    title = "Claude Code Sessions",
    fuzzy = false,            -- true にすると最初からファジー検索で開く
    alphabet = "123456789",   -- 行に割り当てる選択キー
    center = true,            -- 一覧をペイン幅に対して横中央寄せ
  },
  icons  = { running = "🟡", waiting = "🔴", done = "🟢" },
  labels = { running = "Running", waiting = "Waiting", done = "Done" },
  patterns = {
    -- ペイン末尾テキストに対する部分一致 (小文字扱い)
    running = { "esc to interrupt" },
    waiting = { "do you want", "❯ 1." },
    -- プロセス名 / argv に対する Lua パターン
    process = { "^claude$", "claude%-code" },
  },
  keybind = { key = "s", mods = "CMD" },  -- モーダル表示キー (false で自動割り当てなし)
  scan_lines = 40,            -- 状態判定に読むペイン末尾の行数
  cwd_display = "basename",   -- "basename" | "shortened" | "full"
  max_name_width = 18,        -- プロジェクト名の表示幅
  show_title = true,          -- ペインタイトル (作業内容) を一覧に表示
})
```

ラベルを日本語にしたい場合:

```lua
csm.apply_to_config(config, {
  labels = { running = "実行中", waiting = "停止中", done = "完了" },
})
```

### カスタム利用

自分のステータスバー等に組み込むこともできます:

```lua
local counts = csm.counts()     -- { running = 1, waiting = 0, done = 2, total = 3 }
local sessions = csm.sessions() -- { { pane_id, workspace, cwd, name, state, title }, ... }
```

## 状態判定の仕組み

各ペインの `get_foreground_process_info()` から Claude Code のプロセス(ネイティブ版 `claude`、npm 版 `node .../claude-code/cli.js`、子プロセスツリー内も含む)を検出し、ペイン末尾のテキストをパターンマッチして状態を決めます:

1. `esc to interrupt` を含む → **Running**
2. `do you want` / `❯ 1.` を含む(権限プロンプト) → **Waiting**
3. どちらもなし → **Done**

Claude Code のアップデートで TUI の文言が変わった場合は `patterns` を上書きしてください。

## 開発

```sh
# ユニットテスト (wezterm 不要 / lua 5.3+)
bash tests/run.sh
```

ローカルの作業コピーをプラグインとして読み込むには:

```lua
local csm = wezterm.plugin.require("file:///path/to/wezterm-claude-session-manager")
```

`plugin.require` は git clone するため **コミット済みの内容だけ** が反映されます。
未コミットの変更を試すときは直接読み込みます:

```lua
package.path = "/path/to/wezterm-claude-session-manager/plugin/?.lua;" .. package.path
local csm = dofile("/path/to/wezterm-claude-session-manager/plugin/init.lua")
```

wezterm はプラグインを自動更新しません。取り込み直すには wezterm 内で
`wezterm.plugin.update_all()` を実行(またはデバッグオーバーレイ Ctrl+Shift+L から)して設定をリロードしてください。
