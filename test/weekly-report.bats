#!/usr/bin/env bats
#
# weekly-report never writes a report itself: it decides whether one is due and
# hands the week to the Claude Code CLI. So every test below stubs claude on
# PATH and reads back the arguments it was called with -- or asserts it was not
# called at all, which is the whole point of --auto.
#
# 2026-08-31 is a Monday, so the dates pinned with --today throughout are:
#   Mon 2026-08-31  today, on the Monday
#   Tue 2026-09-01  today, later in the same week
# and the week they report on is Mon 2026-08-24 to Sun 2026-08-30.

setup() {
  WR="$BATS_TEST_DIRNAME/../bin/weekly-report"
  ARGV_LOG="$BATS_TEST_TMPDIR/argv"
  STUB_BIN="$BATS_TEST_TMPDIR/stub-bin"
  WEEKLY_REPORT_DIR="$BATS_TEST_TMPDIR/weekly-summaries"
  export ARGV_LOG WEEKLY_REPORT_DIR
  mkdir -p "$STUB_BIN" "$WEEKLY_REPORT_DIR"
  # One argument per line, so a phrasing containing spaces is distinguishable
  # from several separate arguments. The log is absent when claude never ran,
  # which is what the --auto skip tests assert.
  cat > "$STUB_BIN/claude" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$ARGV_LOG"
STUB
  chmod +x "$STUB_BIN/claude"
  PATH="$STUB_BIN:$PATH"
  export PATH
}

# report_for <monday> [mtime] — an existing report file, optionally backdated.
report_for() {
  local f="$WEEKLY_REPORT_DIR/week-of-$1.md"
  printf 'an earlier report\n' > "$f"
  [ -z "${2:-}" ] || touch -t "$2" "$f"
}

# Negation gets its own helper rather than being written as a negated call:
# inside a bats test a negated command does not fail the test, so the negated
# form would have asserted nothing at all.
assert_ran()     { [ -f "$ARGV_LOG" ]; }
assert_not_ran() { [ ! -f "$ARGV_LOG" ]; }

@test "weekly-report: --help explains --auto and where reports are written" {
  run "$WR" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"usage: weekly-report"* ]]
  [[ "$output" == *"--auto"* ]]
  [[ "$output" == *"week-of-<monday>.md"* ]]
}

@test "weekly-report: the default week is the last complete one, named by date" {
  run "$WR" --today 2026-08-31
  [ "$status" -eq 0 ]
  run cat "$ARGV_LOG"
  [ "${lines[0]}" = "-p" ]
  [ "${lines[1]}" = "/weekly-summary week of 2026-08-24" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "weekly-report: --weeks-ago counts whole weeks back" {
  run "$WR" --today 2026-08-31 --weeks-ago 3
  [ "$status" -eq 0 ]
  run cat "$ARGV_LOG"
  [ "${lines[1]}" = "/weekly-summary week of 2026-08-10" ]
}

@test "weekly-report: --week resolves any day to that week's Monday" {
  run "$WR" --week 2026-08-13
  [ "$status" -eq 0 ]
  run cat "$ARGV_LOG"
  [ "${lines[1]}" = "/weekly-summary week of 2026-08-10" ]
}

@test "weekly-report: a Sunday resolves back to the Monday six days earlier" {
  run "$WR" --week 2026-08-16
  [ "$status" -eq 0 ]
  run cat "$ARGV_LOG"
  [ "${lines[1]}" = "/weekly-summary week of 2026-08-10" ]
}

@test "weekly-report: --auto writes on a Monday when no report exists yet" {
  run "$WR" --auto --today 2026-08-31
  [ "$status" -eq 0 ]
  assert_ran
  run cat "$ARGV_LOG"
  [ "${lines[1]}" = "/weekly-summary week of 2026-08-24" ]
}

@test "weekly-report: --auto does not write a second time the same Monday" {
  # The mtime is now rather than a pinned time, which is what a report written
  # earlier in the same run of the day looks like. This is the guard against a
  # daily job, or a person, invoking it twice on a Monday.
  report_for 2026-08-24
  run "$WR" --auto --today 2026-08-31
  [ "$status" -eq 0 ]
  assert_not_ran
}

@test "weekly-report: --auto on a Monday replaces a draft written before the week closed" {
  # Written on Wednesday 26 August, while the week it covers was still running.
  report_for 2026-08-24 202608261200
  run "$WR" --auto --today 2026-08-31
  [ "$status" -eq 0 ]
  assert_ran
}

@test "weekly-report: --auto does nothing later in a week already reported on" {
  report_for 2026-08-24
  run "$WR" --auto --today 2026-09-01
  [ "$status" -eq 0 ]
  assert_not_ran
}

@test "weekly-report: --auto writes later in the week when Monday was missed" {
  run "$WR" --auto --today 2026-09-01
  [ "$status" -eq 0 ]
  assert_ran
  run cat "$ARGV_LOG"
  [ "${lines[1]}" = "/weekly-summary week of 2026-08-24" ]
}

@test "weekly-report: --auto replaces a report written before this Monday" {
  # A mid-week partial written on Wednesday 26 August, before the week closed.
  report_for 2026-08-24 202608261200
  run "$WR" --auto --today 2026-09-01
  [ "$status" -eq 0 ]
  assert_ran
}

@test "weekly-report: --auto leaves a report edited later in the same week alone" {
  report_for 2026-08-24 202609011500
  run "$WR" --auto --today 2026-09-02
  [ "$status" -eq 0 ]
  assert_not_ran
}

@test "weekly-report: --auto is silent when it decides there is nothing to do" {
  report_for 2026-08-24
  run "$WR" --auto --today 2026-09-01
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "weekly-report: --auto is refused for an explicit past week" {
  run "$WR" --auto --weeks-ago 3
  [ "$status" -ne 0 ]
  [[ "$output" == *"only applies to the last complete week"* ]]
  assert_not_ran
}

@test "weekly-report: --auto and --force are refused together" {
  run "$WR" --auto --force
  [ "$status" -ne 0 ]
  [[ "$output" == *"contradict"* ]]
}

@test "weekly-report: a manual run over an existing report asks first" {
  report_for 2026-08-24
  run bash -c "printf 'y\n' | '$WR' --today 2026-08-31"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Overwrite?"* ]]
  assert_ran
}

@test "weekly-report: answering no leaves the report alone" {
  report_for 2026-08-24
  run bash -c "printf 'n\n' | '$WR' --today 2026-08-31"
  [ "$status" -eq 0 ]
  assert_not_ran
}

@test "weekly-report: a bare newline is taken as no" {
  report_for 2026-08-24
  run bash -c "printf '\n' | '$WR' --today 2026-08-31"
  [ "$status" -eq 0 ]
  assert_not_ran
}

@test "weekly-report: a manual run with no report to overwrite does not ask" {
  run bash -c "'$WR' --today 2026-08-31 </dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Overwrite?"* ]]
  assert_ran
}

@test "weekly-report: an unanswerable prompt fails loudly rather than hanging" {
  report_for 2026-08-24
  run bash -c "'$WR' --today 2026-08-31 </dev/null"
  [ "$status" -ne 0 ]
  [[ "$output" == *"use --force"* ]]
  assert_not_ran
}

@test "weekly-report: --force overwrites without asking" {
  report_for 2026-08-24
  run bash -c "'$WR' --force --today 2026-08-31 </dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Overwrite?"* ]]
  assert_ran
}

@test "weekly-report: an impossible date is rejected, not rolled forward" {
  run "$WR" --week 2026-02-30
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a real date"* ]]
  assert_not_ran
}

@test "weekly-report: a malformed date is rejected before it reaches sqlite" {
  run "$WR" --week "2026-08-10'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"must be a YYYY-MM-DD date"* ]]
  assert_not_ran
}

@test "weekly-report: an unknown option is named" {
  run "$WR" --nonsense
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown option: --nonsense"* ]]
}

@test "weekly-report: a missing claude CLI is named rather than failing obscurely" {
  PATH="/usr/bin:/bin" run "$WR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"claude is not installed"* ]]
}
