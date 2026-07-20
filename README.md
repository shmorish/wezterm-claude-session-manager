# wezterm-claude-session-manager

A wezterm plugin that lists all running [Claude Code](https://claude.com/claude-code) sessions in a modal picker — see each session's status at a glance and jump to it.

wezterm 上で並行して動いている Claude Code のセッションを、モーダル(オーバーレイ)で一覧表示する wezterm プラグインです。各セッションの状態が一目でわかり、選択するとそのペインへジャンプできます。

```
┌─ Claude Code Sessions ───────────────────────────────┐
│ > 検索…                                              │
│                                                      │
│  🟡 dotfiles           Running  ✳ Karabinerの設定    │
│  🔴 my-app             Waiting  ✳ APIの実装          │
│  🟢 api-server         Done     ✳ バグ修正           │
└──────────────────────────────────────────────────────┘
```

- **Running** 🟡 — Claude が生成・ツール実行中
- **Waiting** 🔴 — 権限確認などでユーザーの応答待ち(要対応)
- **Done** 🟢 — 応答が終わり、次の入力を待っているだけ

**`CMD+s`** でモーダルを開き、**Esc** で閉じる / **Enter** で選択したセッションのペインへジャンプします(別 workspace のセッションは workspace ごと切り替え)。ファジー検索対応。外部依存はありません。

## 必要環境

- wezterm 20240127 以降
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
    title = "Claude Code Sessions",
    fuzzy = true,             -- ファジー検索
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
