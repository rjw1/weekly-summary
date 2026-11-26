#!/usr/bin/env bats
#
# timesheet does its arithmetic on what weekly-digest prints, so every test
# here stubs the digest with a canned digest output built by add_session, and
# stubs claude on PATH so no test can reach the real CLI. The digest's own
# extraction of ids and timestamps is tested in weekly-digest.bats.
#
# Times are local seconds-of-day throughout, so no test depends on TZ.

bats_require_minimum_version 1.5.0

setup() {
  TS="$BATS_TEST_DIRNAME/../bin/timesheet"
  STUB_BIN="$BATS_TEST_TMPDIR/stub-bin"
  SESSIONS="$BATS_TEST_TMPDIR/sessions"
  STAMPS="$BATS_TEST_TMPDIR/stamps"
  ARGV_LOG="$BATS_TEST_TMPDIR/digest-argv"
  CLAUDE_LOG="$BATS_TEST_TMPDIR/claude-argv"
  CLAUDE_STDIN="$BATS_TEST_TMPDIR/claude-stdin"
  CLAUDE_REPLY="$BATS_TEST_TMPDIR/claude-reply"
  DIGEST_STATUS=0
  TIMESHEET_DIGEST="$STUB_BIN/weekly-digest"
  # Never the developer's own config: every test sees the built-in defaults
  # unless it writes its own file here.
  TIMESHEET_CONFIG="$BATS_TEST_TMPDIR/no-such-config"
  export SESSIONS STAMPS ARGV_LOG CLAUDE_LOG CLAUDE_STDIN CLAUDE_REPLY
  export DIGEST_STATUS TIMESHEET_DIGEST TIMESHEET_CONFIG
  mkdir -p "$STUB_BIN"
  : > "$SESSIONS"
  : > "$STAMPS"

  cat > "$TIMESHEET_DIGEST" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$ARGV_LOG"
[ "$DIGEST_STATUS" -eq 0 ] || exit "$DIGEST_STATUS"
printf '## window\n\nfrom: x\nto: x\nbasis: explicit --from/--to\n\n'
printf '## stats\n\n## pull requests\n\n(unavailable: --no-gh)\n\n## sessions\n\n'
cat "$SESSIONS"
printf '## timestamps\n\n'
cat "$STAMPS"
printf '\n'
STUB
  chmod +x "$TIMESHEET_DIGEST"

  cat > "$STUB_BIN/claude" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$CLAUDE_LOG"
cat > "$CLAUDE_STDIN"
cat "$CLAUDE_REPLY"
STUB
  chmod +x "$STUB_BIN/claude"
  PATH="$STUB_BIN:$PATH"
  export PATH
}

# add_session <tool> <id> <repo> <title> <HH:MM:SS>... — one session block in
# the digest's format, plus one timestamp line per time given.
add_session() {
  local tool="$1" id="$2" repo="$3" title="$4" t
  shift 4
  {
    printf '### %s\n\ntool: %s\nid: %s\nrepo: %s\nstarted: 2026-08-18\n\n' \
      "$title" "$tool" "$id" "$repo"
    printf 'USER: prompt for %s\nFINAL: finished %s\n\n' "$title" "$title"
  } >> "$SESSIONS"
  for t in "$@"; do
    printf '%s\t%s\t%s\n' "$tool" "$id" "$t" >> "$STAMPS"
  done
}

# line <regex> — the output has a line matching the extended regex.
line() {
  grep -Eq -- "$1" <<<"$output"
}

assert_claude_not_ran() { [ ! -f "$CLAUDE_LOG" ]; }

@test "timesheet: --help shows usage" {
  run "$TS" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"usage: timesheet"* ]]
  [[ "$output" == *"--no-label"* ]]
}

@test "timesheet: two messages 10 minutes apart make one 15-minute block" {
  add_session claude-code s1 /work/tool "Hide columns" 10:00:00 10:10:00
  run "$TS" --date 2026-08-18 --no-label
  [ "$status" -eq 0 ]
  line '^  10:00-10:15 +0:15 +tool +Hide columns'
  line '^tool +0:15 +0:30$'
}

@test "timesheet: a gap over 15 minutes splits blocks" {
  add_session claude-code s1 /work/tool "Hide columns" 10:00:00 10:16:00
  run "$TS" --date 2026-08-18 --no-label
  [ "$status" -eq 0 ]
  line '^tool +0:10 +0:30$'
}

@test "timesheet: --gap 20 joins them" {
  add_session claude-code s1 /work/tool "Hide columns" 10:00:00 10:16:00
  run "$TS" --date 2026-08-18 --no-label --gap 20
  [ "$status" -eq 0 ]
  line '^tool +0:21 +0:30$'
}

@test "timesheet: a single message counts as the tail" {
  add_session claude-code s1 /work/tool "Hide columns" 10:00:00
  run "$TS" --date 2026-08-18 --no-label
  [ "$status" -eq 0 ]
  line '^tool +0:05 +0:30$'
}

@test "timesheet: rounding goes up to the next half hour and leaves exact ones alone" {
  add_session claude-code s1 /work/tool "Hide columns" 10:00:00
  run "$TS" --date 2026-08-18 --no-label --tail 30
  line '^tool +0:30 +0:30$'
  run "$TS" --date 2026-08-18 --no-label --tail 31
  line '^tool +0:31 +1:00$'
  run "$TS" --date 2026-08-18 --no-label --tail 67
  line '^tool +1:07 +1:30$'
}

@test "timesheet: overlapping sessions count once in the day total" {
  local ts=(10:00:00 10:10:00 10:20:00 10:30:00 10:40:00 10:50:00 11:00:00)
  add_session claude-code s1 /work/tool "One" "${ts[@]}"
  add_session opencode s2 /work/alpha "Two" "${ts[@]}"
  run "$TS" --date 2026-08-18 --no-label
  [ "$status" -eq 0 ]
  line '^tool +1:05 +1:30$'
  line '^alpha +1:05 +1:30$'
  line '^day total +1:05 +3:00'
}

@test "timesheet: a block straddling the default 17:30 end is split" {
  add_session claude-code s1 /work/tool "Late" 17:20:00 17:30:00 17:40:00 17:50:00
  run "$TS" --date 2026-08-18 --no-label
  [ "$status" -eq 0 ]
  line '^tool +0:35 +1:00$'
  line '^  outside 09:00-17:30 +0:25$'
}

@test "timesheet: a block straddling the default 09:00 start is split" {
  add_session claude-code s1 /work/tool "Early" 08:50:00 09:00:00
  run "$TS" --date 2026-08-18 --no-label
  [ "$status" -eq 0 ]
  line '^tool +0:15 +0:30$'
  line '^  outside 09:00-17:30 +0:10$'
}

@test "timesheet: no outside line when everything is in hours" {
  add_session claude-code s1 /work/tool "Mid" 11:00:00
  run "$TS" --date 2026-08-18 --no-label
  [ "$status" -eq 0 ]
  [[ "$output" != *"outside 09:00-17:30"* ]]
}

@test "timesheet: the contracted day and what was not seen" {
  add_session claude-code s1 /work/tool "Mid" 11:00:00
  run "$TS" --date 2026-08-18 --no-label
  [ "$status" -eq 0 ]
  line '^contracted day +7:30$'
  line '^not seen +7:25'
}

@test "timesheet: the header names the date and that the split is by repo" {
  add_session claude-code s1 /work/tool "Mid" 11:00:00
  run "$TS" --date 2026-08-18 --no-label
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "timesheet for 2026-08-18 (Tuesday)" ]
  [[ "$output" == *"grouped by repo"* ]]
}

@test "timesheet: a day with no sessions shows zeroes and the full day unseen" {
  run "$TS" --date 2026-08-18 --no-label
  [ "$status" -eq 0 ]
  line '^day total +0:00 +0:00'
  line '^not seen +7:30'
}

@test "timesheet: the tail stops at now when the date is today" {
  add_session claude-code s1 /work/tool "Now" 10:00:00
  TIMESHEET_NOW=10:02:00 run "$TS" --no-label
  [ "$status" -eq 0 ]
  line '^tool +0:02 +0:30$'
}

@test "timesheet: TIMESHEET_NOW is ignored for a past date" {
  add_session claude-code s1 /work/tool "Then" 10:00:00
  TIMESHEET_NOW=10:02:00 run "$TS" --date 2020-01-01 --no-label
  [ "$status" -eq 0 ]
  line '^tool +0:05 +0:30$'
}

@test "timesheet: the tail stops at midnight" {
  add_session claude-code s1 /work/tool "Late night" 23:58:00
  run "$TS" --date 2026-08-18 --no-label
  [ "$status" -eq 0 ]
  line '^tool +0:02 +0:30$'
}

@test "timesheet: --date defaults to today" {
  run "$TS" --no-label
  [ "$status" -eq 0 ]
  local today
  today="$(sqlite3 :memory: "SELECT date('now','localtime');")"
  run cat "$ARGV_LOG"
  [[ "$output" == *$'--from\n'"$today"$'\n--to\n'"$today"* ]]
  [[ "$output" == *"--timestamps"* ]]
}

@test "timesheet: an impossible --date is rejected" {
  run "$TS" --date 2026-02-30 --no-label
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a real date"* ]]
  [ ! -f "$ARGV_LOG" ]
}

@test "timesheet: a malformed --date is rejected" {
  run "$TS" --date "2026-08-18'; x" --no-label
  [ "$status" -ne 0 ]
  [[ "$output" == *"YYYY-MM-DD"* ]]
}

@test "timesheet: a non-numeric --gap is rejected" {
  run "$TS" --gap soon --no-label
  [ "$status" -ne 0 ]
  [[ "$output" == *"--gap"* ]]
}

@test "timesheet: a digest failure is fatal and prints no timesheet" {
  add_session claude-code s1 /work/tool "Mid" 11:00:00
  DIGEST_STATUS=3 run --separate-stderr "$TS" --date 2026-08-18 --no-label
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  [[ "$stderr" == *"weekly-digest failed"* ]]
}

@test "timesheet: a long name widens the column rather than pushing figures out of line" {
  add_session claude-code s1 /work/a-long-client-application-repository-name "Long" 11:00:00
  add_session claude-code s2 /work/bin "Short" 12:00:00
  run "$TS" --date 2026-08-18 --no-label
  [ "$status" -eq 0 ]
  local a b c suffix="  (rounded = sum of lines)"
  a="$(grep '^a-long-client' <<<"$output")"
  b="$(grep '^bin ' <<<"$output")"
  [ "${#a}" -eq "${#b}" ]
  c="$(grep '^day total' <<<"$output")"
  c="${c%"$suffix"}"
  [ "${#c}" -eq "${#a}" ]
}

# --- labelling ----------------------------------------------------------------

# reply <json> — what the stub claude prints.
reply() {
  printf '%s\n' "$1" > "$CLAUDE_REPLY"
}

two_sessions() {
  add_session claude-code s1 /work/client-app "Fix a failing spec" 10:00:00 10:10:00
  add_session claude-code s2 /work/tool "Hide columns" 11:00:00 11:10:00
}

@test "label: sessions are grouped by the client claude names" {
  two_sessions
  reply '[{"id":"s1","category":"client","client":"ACME","description":"Fixed the deletion spec"},
          {"id":"s2","category":"internal","client":null,"description":"Column hiding in tool"}]'
  run "$TS" --date 2026-08-18
  [ "$status" -eq 0 ]
  line '^ACME +0:15 +0:30$'
  line '^internal +0:15 +0:30$'
  line '^  10:00-10:15 +0:15 +ACME +Fixed the deletion spec +\[client-app\]$'
  [[ "$output" != *"grouped by repo"* ]]
}

@test "label: internal sorts after every client line" {
  two_sessions
  add_session claude-code s3 /work/x "More internal" 12:00:00 12:30:00
  reply '[{"id":"s1","category":"client","client":"ACME","description":"a"},
          {"id":"s2","category":"internal","client":null,"description":"b"},
          {"id":"s3","category":"internal","client":null,"description":"c"}]'
  run "$TS" --date 2026-08-18
  [ "$status" -eq 0 ]
  [ "$(grep -oE '^(ACME|internal) ' <<<"$output" | tr -d ' ' | paste -sd, -)" = "ACME,internal" ]
}

@test "label: two sessions for one client share a line" {
  add_session claude-code s1 /work/a "One" 10:00:00 10:10:00
  add_session opencode s2 /work/b "Two" 10:05:00 10:20:00
  reply '[{"id":"s1","category":"client","client":"Globex","description":"a"},
          {"id":"s2","category":"client","client":"Globex","description":"b"}]'
  run "$TS" --date 2026-08-18
  [ "$status" -eq 0 ]
  line '^Globex +0:25 +0:30$'
  [ "$(grep -c '^Globex' <<<"$output")" -eq 1 ]
}

@test "label: personal sessions are listed but not counted" {
  two_sessions
  add_session claude-code s3 /home/admin "Household admin" 13:00:00 13:10:00 13:20:00 13:25:00
  reply '[{"id":"s1","category":"client","client":"ACME","description":"a"},
          {"id":"s2","category":"internal","client":null,"description":"b"},
          {"id":"s3","category":"personal","client":null,"description":"Household admin"}]'
  run "$TS" --date 2026-08-18
  [ "$status" -eq 0 ]
  line '^personal \(not counted\) +0:30$'
  line '^day total +0:30 +1:00'
  line '^  13:00-13:30 +0:30 +personal +Household admin'
  [[ "$output" != *$'\npersonal  '* ]]
}

@test "label: a reply wrapped in a code fence is accepted" {
  two_sessions
  reply '```json
[{"id":"s1","category":"client","client":"ACME","description":"a"},
 {"id":"s2","category":"internal","client":null,"description":"b"}]
```'
  run "$TS" --date 2026-08-18
  [ "$status" -eq 0 ]
  line '^ACME +0:15'
}

@test "label: a session missing from the reply fails loudly" {
  two_sessions
  reply '[{"id":"s1","category":"client","client":"ACME","description":"a"}]'
  run --separate-stderr "$TS" --date 2026-08-18
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  [[ "$stderr" == *"s2"* ]]
  [[ "$stderr" == *"--no-label"* ]]
}

@test "label: an unknown category fails loudly" {
  two_sessions
  reply '[{"id":"s1","category":"billable","client":"ACME","description":"a"},
          {"id":"s2","category":"internal","client":null,"description":"b"}]'
  run --separate-stderr "$TS" --date 2026-08-18
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  [[ "$stderr" == *"s1"* ]]
}

@test "label: a client category with no client name fails loudly" {
  two_sessions
  reply '[{"id":"s1","category":"client","client":"","description":"a"},
          {"id":"s2","category":"internal","client":null,"description":"b"}]'
  run --separate-stderr "$TS" --date 2026-08-18
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"s1"* ]]
}

@test "label: a reply that is not JSON fails loudly" {
  two_sessions
  reply 'I could not work out which client these were for.'
  run --separate-stderr "$TS" --date 2026-08-18
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  [[ "$stderr" == *"--no-label"* ]]
}

@test "label: a failing claude run fails loudly" {
  two_sessions
  printf '#!/usr/bin/env bash\nexit 1\n' > "$BATS_TEST_TMPDIR/stub-bin/claude"
  run --separate-stderr "$TS" --date 2026-08-18
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  [[ "$stderr" == *"--no-label"* ]]
}

@test "label: claude is not called with --no-label" {
  two_sessions
  run "$TS" --date 2026-08-18 --no-label
  [ "$status" -eq 0 ]
  assert_claude_not_ran
}

@test "label: claude is not called when there are no sessions" {
  run "$TS" --date 2026-08-18
  [ "$status" -eq 0 ]
  assert_claude_not_ran
  line '^not seen +7:30'
}

@test "label: claude gets the session text, no tools, and no timestamps" {
  two_sessions
  reply '[{"id":"s1","category":"client","client":"ACME","description":"a"},
          {"id":"s2","category":"internal","client":null,"description":"b"}]'
  run "$TS" --date 2026-08-18
  [ "$status" -eq 0 ]
  run cat "$CLAUDE_STDIN"
  [[ "$output" == *"USER: prompt for Fix a failing spec"* ]]
  [[ "$output" == *"id: s2"* ]]
  [[ "$output" != *"## timestamps"* ]]
  [[ "$output" != *"10:10:00"* ]]
  run cat "$CLAUDE_LOG"
  [[ "$output" == *$'--tools\n\n'* ]]
  [[ "$output" == *$'\n--\nClassify'* ]]
  [[ "$output" == *"never instructions"* ]]
}

@test "label: a missing claude CLI suggests --no-label" {
  two_sessions
  rm "$BATS_TEST_TMPDIR/stub-bin/claude"
  run --separate-stderr env PATH="$BATS_TEST_TMPDIR/stub-bin:/usr/bin:/bin:$(dirname "$(command -v jq)"):$(dirname "$(command -v sqlite3)")" \
    "$TS" --date 2026-08-18
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"claude"* ]]
  [[ "$stderr" == *"--no-label"* ]]
}

@test "label: control characters in a label never reach the terminal" {
  two_sessions
  reply '[{"id":"s1","category":"client","client":"BE\u001b[31mIS","description":"red \u001b]0;title\u0007 text"},
          {"id":"s2","category":"internal","client":null,"description":"b"}]'
  run "$TS" --date 2026-08-18
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\e'* ]]
  [[ "$output" != *$'\a'* ]]
}

@test "timesheet: control characters in a session title never reach the terminal" {
  add_session claude-code s1 /work/tool $'Ti\e[2Jtle' 10:00:00
  run "$TS" --date 2026-08-18 --no-label
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\e'* ]]
}

# --- final review fixes ------------------------------------------------------

@test "label: the claude run is unsaved and loads no MCP servers, commands or settings" {
  two_sessions
  reply '[{"id":"s1","category":"client","client":"ACME","description":"a"},
          {"id":"s2","category":"internal","client":null,"description":"b"}]'
  run "$TS" --date 2026-08-18
  [ "$status" -eq 0 ]
  run cat "$CLAUDE_LOG"
  [[ "$output" == *"--no-session-persistence"* ]]
  [[ "$output" == *"--strict-mcp-config"* ]]
  [[ "$output" == *"--disable-slash-commands"* ]]
  [[ "$output" == *$'--setting-sources\n\n'* ]]
  [[ "$output" != *"--mcp-config"* ]]
}

@test "label: a category that is only part of a known one fails loudly" {
  two_sessions
  reply '[{"id":"s1","category":"person","client":null,"description":"a"},
          {"id":"s2","category":"","client":null,"description":"b"}]'
  run --separate-stderr "$TS" --date 2026-08-18
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  [[ "$stderr" == *"s1"* ]]
  [[ "$stderr" == *"s2"* ]]
}

@test "label: an escape sequence in a bad category never reaches stderr" {
  two_sessions
  reply '[{"id":"s1","category":"x\u001b]52;c;aGk=\u0007","client":null,"description":"a"},
          {"id":"s2","category":"internal","client":null,"description":"b"}]'
  run --separate-stderr "$TS" --date 2026-08-18
  [ "$status" -ne 0 ]
  [[ "$stderr" != *$'\e'* ]]
  [[ "$stderr" != *$'\a'* ]]
}

@test "label: time shared by two lines is shown as overlap" {
  add_session claude-code s1 /work/a "One" 10:00:00 10:10:00
  add_session claude-code s2 /work/b "Two" 10:00:00 10:10:00
  reply '[{"id":"s1","category":"client","client":"ACME","description":"a"},
          {"id":"s2","category":"internal","client":null,"description":"b"}]'
  run "$TS" --date 2026-08-18
  [ "$status" -eq 0 ]
  line '^day total +0:15 +1:00'
  line '^  in more than one line +0:15$'
}

@test "timesheet: no overlap line when lines do not share time" {
  add_session claude-code s1 /work/a "One" 10:00:00
  add_session claude-code s2 /work/b "Two" 11:00:00
  run "$TS" --date 2026-08-18 --no-label
  [ "$status" -eq 0 ]
  [[ "$output" != *"in more than one line"* ]]
}

@test "timesheet: a tail longer than the gap never counts the same minute twice" {
  add_session claude-code s1 /work/tool "Hide columns" 10:00:00 10:16:00
  run "$TS" --date 2026-08-18 --no-label --tail 30
  [ "$status" -eq 0 ]
  line '^  10:00-10:46 +0:46 +tool'
  line '^tool +0:46 +1:00$'
}

# --- working hours ------------------------------------------------------------

@test "hours: with no config the defaults are used and the header says so" {
  add_session claude-code s1 /work/client-app "Mid" 11:00:00
  run "$TS" --date 2026-08-18 --no-label
  [ "$status" -eq 0 ]
  [[ "$output" == *"working hours 09:00-17:30, 7:30 day (defaults"* ]]
  line '^contracted day +7:30$'
}

@test "hours: a config file sets the working hours and the contracted day" {
  printf '# mine\nhours = 08:00-16:00\nday=8:00\n' > "$BATS_TEST_TMPDIR/config"
  add_session claude-code s1 /work/client-app "Late" 15:50:00 16:00:00
  TIMESHEET_CONFIG="$BATS_TEST_TMPDIR/config" run "$TS" --date 2026-08-18 --no-label
  [ "$status" -eq 0 ]
  line '^  outside 08:00-16:00 +0:05$'
  line '^contracted day +8:00$'
  line '^not seen +7:45'
  [[ "$output" != *"(defaults"* ]]
}

@test "hours: a config file may set only one of the two" {
  printf 'day=6:00\n' > "$BATS_TEST_TMPDIR/config"
  add_session claude-code s1 /work/client-app "Late" 17:20:00 17:30:00
  TIMESHEET_CONFIG="$BATS_TEST_TMPDIR/config" run "$TS" --date 2026-08-18 --no-label
  [ "$status" -eq 0 ]
  line '^  outside 09:00-17:30 +0:05$'
  line '^contracted day +6:00$'
}

@test "hours: a malformed hours value is rejected naming the file" {
  printf 'hours=9-5\n' > "$BATS_TEST_TMPDIR/config"
  TIMESHEET_CONFIG="$BATS_TEST_TMPDIR/config" run "$TS" --date 2026-08-18 --no-label
  [ "$status" -ne 0 ]
  [[ "$output" == *"$BATS_TEST_TMPDIR/config"* ]]
  [[ "$output" == *"HH:MM-HH:MM"* ]]
}

@test "hours: an end before the start is rejected" {
  printf 'hours=17:00-09:00\n' > "$BATS_TEST_TMPDIR/config"
  TIMESHEET_CONFIG="$BATS_TEST_TMPDIR/config" run "$TS" --date 2026-08-18 --no-label
  [ "$status" -ne 0 ]
  [[ "$output" == *"hours"* ]]
}

@test "hours: a malformed day value is rejected" {
  printf 'day=seven\n' > "$BATS_TEST_TMPDIR/config"
  TIMESHEET_CONFIG="$BATS_TEST_TMPDIR/config" run "$TS" --date 2026-08-18 --no-label
  [ "$status" -ne 0 ]
  [[ "$output" == *"H:MM"* ]]
}

@test "hours: an unknown setting is rejected rather than ignored" {
  printf 'hour=09:00-17:00\n' > "$BATS_TEST_TMPDIR/config"
  TIMESHEET_CONFIG="$BATS_TEST_TMPDIR/config" run "$TS" --date 2026-08-18 --no-label
  [ "$status" -ne 0 ]
  [[ "$output" == *"hour"* ]]
}

@test "hours: the config is read, never executed" {
  # The $(...) is meant literally: it is the payload that must not run.
  # shellcheck disable=SC2016
  printf 'hours=$(touch %s/pwned)\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/config"
  TIMESHEET_CONFIG="$BATS_TEST_TMPDIR/config" run "$TS" --date 2026-08-18 --no-label
  [ "$status" -ne 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/pwned" ]
}
