# wezterm-claude-session-manager

A wezterm plugin that shows all running [Claude Code](https://claude.com/claude-code) sessions in a toggleable sidebar with live status.

wezterm 上で並行して動いている Claude Code のセッションを、左サイドバーで一覧・状態監視できる wezterm プラグインです。

```
 Claude Code Sessions
 ────────────────────────────
 [default]
 🟡 dotfiles           Running
    ✳ Karabinerの設定を修正
 🔴 my-app             Waiting
    ✳ APIエンドポイントの実装
 🟢 api-server         Done
    ✳ バグ修正

 3 sessions
```

- **Running** 🟡 — Claude が生成・ツール実行中
- **Waiting** 🔴 — 権限確認などでユーザーの応答待ち(要対応)
- **Done** 🟢 — 応答が終わり、次の入力を待っているだけ

サイドバーはキーバインドで開閉でき、開いている間は約1秒ごとに自動更新されます(表示専用)。外部依存はありません(fzf 等は不要)。

## 必要環境

- wezterm 20240127 以降(`Url` オブジェクト対応版)
- ローカルペインのみ対応(SSH / mux リモートのペインはプロセス情報が取れないため一覧に出ません)

## インストール

`~/.config/wezterm/wezterm.lua` に追加:

```lua
local wezterm = require("wezterm")
local config = wezterm.config_builder()

local csm = wezterm.plugin.require("https://github.com/shmorish/wezterm-claude-session-manager")
csm.apply_to_config(config, {})

config.keys = config.keys or {}
table.insert(config.keys, {
  key = "b",
  mods = "CTRL|SHIFT",
  action = csm.action.toggle_sidebar,
})

return config
```

キーを押すたびにサイドバーが開く / 閉じるを切り替えます。

## 設定

`apply_to_config` の第2引数で上書きできます(すべて省略可):

```lua
csm.apply_to_config(config, {
  sidebar = {
    position = "Left",   -- "Left" | "Right"
    width = 0.18,        -- ウィンドウ幅に対する割合
    title = "Claude Code Sessions",
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
  scan_lines = 40,            -- 状態判定に読むペイン末尾の行数
  cwd_display = "basename",   -- "basename" | "shortened" | "full"
  max_name_width = 18,        -- プロジェクト名の表示幅
  show_title = true,          -- ペインタイトル (作業内容) を2行目に表示
})
```

更新間隔は wezterm 本体の `config.status_update_interval`(既定 1000ms)に従います。

ラベルを日本語にしたい場合:

```lua
csm.apply_to_config(config, {
  labels = { running = "実行中", waiting = "停止中", done = "完了" },
})
```

### カスタム利用

サイドバーを使わず自分のステータスバーに組み込むこともできます:

```lua
local counts = csm.counts()    -- { running = 1, waiting = 0, done = 2, total = 3 }
local sessions = csm.sessions() -- { { pane_id, workspace, cwd, name, state, title }, ... }
```

## 状態判定の仕組み

各ペインの `get_foreground_process_info()` から Claude Code のプロセス(ネイティブ版 `claude`、npm 版 `node .../claude-code/cli.js`、子プロセスツリー内も含む)を検出し、ペイン末尾のテキストをパターンマッチして状態を決めます:

1. `esc to interrupt` を含む → **実行中**
2. `do you want` / `❯ 1.` を含む(権限プロンプト) → **停止中**
3. どちらもなし → **完了**

Claude Code のアップデートで TUI の文言が変わった場合は `patterns` を上書きしてください。

## 制限事項

- サイドバーはトグルしたタブ内のペインとして開きます。別のタブに移動すると見えなくなります(トグルで閉じて開き直してください)
- 描画には experimental な `pane:inject_output()` を使用しています
- サイドバー自体は表示専用です(選択してジャンプする機能はありません)

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
