package.path = "plugin/?.lua;tests/?.lua;" .. package.path

local t = require("helpers")
local transcript = require("claude_session_manager.transcript")

-- encode_cwd: 非英数字 (/ _ .) を - に置換し英数字と大小文字は保持する
t.eq(
  transcript.encode_cwd("/Users/x/Private/wezterm-claude-session-manager"),
  "-Users-x-Private-wezterm-claude-session-manager",
  "slashes to dashes, existing dashes kept"
)
t.eq(
  transcript.encode_cwd("/Users/x/Private/ft_minecraft"),
  "-Users-x-Private-ft-minecraft",
  "underscore to dash"
)
t.eq(transcript.encode_cwd("/a/b.c/d"), "-a-b-c-d", "dot to dash")
t.eq(
  transcript.encode_cwd("/Users/x/proj/"),
  "-Users-x-proj",
  "trailing slash stripped (get_current_working_dir 対策)"
)
t.eq(transcript.encode_cwd(nil), nil, "nil cwd returns nil")

-- parse_lines: json_parse を注入し、壊れた行やメタ行は無視して table だけ集める
local fake_records = {
  ["u1"] = { type = "user", message = { role = "user", content = "hello world" } },
  ["a1"] = {
    type = "assistant",
    message = {
      role = "assistant",
      content = {
        { type = "text", text = "sure thing" },
        { type = "tool_use", name = "Bash" },
      },
    },
  },
  ["meta"] = { type = "mode", mode = "x" },
  ["a2"] = {
    type = "assistant",
    message = { role = "assistant", content = { { type = "thinking", thinking = "hmm" } } },
  },
}

-- テスト用の極小パーサ: 事前に用意した表を line 文字列で引く (未知はエラー)
local function fake_parse(line)
  local rec = fake_records[line]
  if rec == nil then
    error("bad json")
  end
  return rec
end

local records = transcript.parse_lines({ "u1", "broken", "a1", "meta", "a2", "" }, fake_parse)
t.eq(#records, 4, "broken line dropped, empty line skipped, 4 records parsed")

-- render: user/assistant のみ、text と tool マーカーを出す。thinking のみは本文空で除外
local out = transcript.render(records, 60)
t.contains(out, "hello world", "user text rendered")
t.contains(out, "sure thing", "assistant text rendered")
t.contains(out, "[tool: Bash]", "tool_use marker rendered")
t.eq(out:find("hmm", 1, true), nil, "thinking content excluded")
t.contains(out, "You", "user header present")
t.contains(out, "Claude", "assistant header present")

-- render: max_messages で末尾のみに絞る
local many = {}
for i = 1, 10 do
  many[i] = { type = "user", message = { role = "user", content = "msg" .. i } }
end
local limited = transcript.render(many, 3)
t.contains(limited, "msg10", "keeps newest message")
t.contains(limited, "msg8", "keeps last 3 (msg8..10)")
t.eq(limited:find("msg7", 1, true), nil, "drops msg7 (beyond last 3)")

-- render: 空入力は空文字列
t.eq(transcript.render({}, 60), "", "empty records -> empty string")

t.finish("transcript_spec")
