#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load helpers/weekly-digest-setup

setup() {
  setup_weekly_digest_env
}

@test "window: defaults to the last complete Mon-Sun week" {
  run "$WD" --today 2026-08-25
  [ "$status" -eq 0 ]
  [[ "$output" == *"2026-08-17"*"2026-08-23"* ]]
}

@test "window: a Monday still reports the previous week" {
  run "$WD" --today 2026-08-24
  [ "$status" -eq 0 ]
  [[ "$output" == *"2026-08-17"*"2026-08-23"* ]]
}

@test "window: a Sunday belongs to the week that is ending" {
  run "$WD" --today 2026-08-23
  [ "$status" -eq 0 ]
  [[ "$output" == *"2026-08-10"*"2026-08-16"* ]]
}

@test "window: --weeks-ago shifts whole weeks, not days" {
  run "$WD" --today 2026-08-25 --weeks-ago 2
  [ "$status" -eq 0 ]
  [[ "$output" == *"2026-08-10"*"2026-08-16"* ]]
}

@test "window: crossing a year boundary" {
  run "$WD" --today 2027-01-04
  [ "$status" -eq 0 ]
  [[ "$output" == *"2026-12-28"*"2027-01-03"* ]]
}

@test "window: --week resolves from any day inside the week" {
  run "$WD" --week 2026-08-19
  [ "$status" -eq 0 ]
  [[ "$output" == *"2026-08-17"*"2026-08-23"* ]]
}

@test "window: --from/--to is used verbatim" {
  run "$WD" --from 2026-08-03 --to 2026-08-14
  [ "$status" -eq 0 ]
  [[ "$output" == *"2026-08-03"*"2026-08-14"* ]]
}

@test "args: --from without --to is rejected" {
  run "$WD" --from 2026-08-03
  [ "$status" -eq 1 ]
  [[ "$output" == *"must be given together"* ]]
}

@test "args: --week cannot be combined with --from/--to" {
  run "$WD" --week 2026-08-19 --from 2026-08-03 --to 2026-08-14
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot be combined"* ]]
}

@test "args: --week cannot be combined with an explicit --weeks-ago" {
  run "$WD" --week 2026-08-19 --weeks-ago 3
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot be combined"* ]]
}

@test "args: --week cannot be combined with --today" {
  run "$WD" --week 2026-08-19 --today 2026-08-25
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot be combined"* ]]
}

@test "args: a non-numeric --weeks-ago is rejected" {
  run "$WD" --weeks-ago x
  [ "$status" -eq 1 ]
  [[ "$output" == *"whole number"* ]]
}

@test "args: a malformed date is rejected with the script's own message" {
  run "$WD" --week "2026-08-19'"
  [ "$status" -eq 1 ]
  [[ "$output" == *"weekly-digest:"* ]]
  [[ "$output" == *"date"* ]]
  [[ "$output" != *"Parse error"* ]]
  [[ "$output" != *"syntax error"* ]]
}

@test "args: --week 2026-02-30 is rejected because sqlite silently rolls it forward" {
  run "$WD" --week 2026-02-30 --no-gh
  [ "$status" -eq 1 ]
  [[ "$output" == *"weekly-digest:"* ]]
  [[ "$output" == *"--week"* ]]
  [[ "$output" == *"not a real calendar date"* ]]
}

@test "args: a shape-valid but impossible day is rejected" {
  run "$WD" --week 2026-04-31 --no-gh
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a real calendar date"* ]]
}

@test "args: the last day of February in a non-leap year is accepted" {
  run "$WD" --week 2026-02-28 --no-gh
  [ "$status" -eq 0 ]
}

@test "args: a genuine leap day is accepted" {
  run "$WD" --today 2024-02-29 --no-gh
  [ "$status" -eq 0 ]
}

@test "args: an unknown option is rejected" {
  run "$WD" --nonsense
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown option"* ]]
}

@test "args: --help exits zero and shows usage" {
  run "$WD" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"usage: weekly-digest"* ]]
}

# seed_week — a fixture with one in-window session, one outside, and one
# created earlier but active inside the window.
seed_week() {
  seed_project "$WEEKLY_DIGEST_DB" proj1 /work/alpha
  seed_project "$WEEKLY_DIGEST_DB" proj2 /work/beta

  seed_session "$WEEKLY_DIGEST_DB" ses_new - proj1 "Inside the window" 2026-08-19 1.50
  seed_message "$WEEKLY_DIGEST_DB" ses_new user 2026-08-19 0 "do the thing"
  seed_message "$WEEKLY_DIGEST_DB" ses_new assistant 2026-08-19 1.50 "did the thing"

  seed_session "$WEEKLY_DIGEST_DB" ses_old - proj2 "Started earlier" 2026-08-11 9.00
  seed_message "$WEEKLY_DIGEST_DB" ses_old user 2026-08-11 0 "prehistoric prompt"
  seed_message "$WEEKLY_DIGEST_DB" ses_old assistant 2026-08-11 5.00 "old answer"
  seed_message "$WEEKLY_DIGEST_DB" ses_old user 2026-08-20 0 "carried over prompt"
  seed_message "$WEEKLY_DIGEST_DB" ses_old assistant 2026-08-20 4.00 "carried over answer"

  seed_session "$WEEKLY_DIGEST_DB" ses_away - proj1 "Nowhere near" 2026-07-01 2.00
  seed_message "$WEEKLY_DIGEST_DB" ses_away user 2026-07-01 0 "unrelated"
}

@test "sessions: a session active in the window is reported" {
  seed_week
  run "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh
  [ "$status" -eq 0 ]
  [[ "$output" == *"Inside the window"* ]]
}

@test "sessions: a session outside the window is not reported" {
  seed_week
  run "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh
  [ "$status" -eq 0 ]
  [[ "$output" != *"Nowhere near"* ]]
}

@test "sessions: a session created earlier but active in the window is reported and marked" {
  seed_week
  run "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh
  [ "$status" -eq 0 ]
  [[ "$output" == *"Started earlier"* ]]
  [[ "$output" == *"CARRIED-OVER from 2026-08-11"* ]]
}

@test "sessions: the repo comes from the project worktree" {
  seed_week
  run "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh
  [ "$status" -eq 0 ]
  [[ "$output" == *"/work/alpha"* ]]
}

@test "sessions: a session with no project row falls back to its directory" {
  seed_session "$WEEKLY_DIGEST_DB" ses_orphan - missing "No project row" 2026-08-19 0.50
  seed_message "$WEEKLY_DIGEST_DB" ses_orphan user 2026-08-19 0 "hello"
  run "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh
  [ "$status" -eq 0 ]
  [[ "$output" == *"/tmp/missing"* ]]
}

@test "sessions: activity in a grandchild carries over a pre-window root, not the intermediate sessions" {
  seed_project "$WEEKLY_DIGEST_DB" proj1 /work/alpha
  seed_session "$WEEKLY_DIGEST_DB" ses_root - proj1 "Root before window" 2026-08-05 0
  seed_message "$WEEKLY_DIGEST_DB" ses_root user 2026-08-05 0 "kickoff"
  seed_session "$WEEKLY_DIGEST_DB" ses_child ses_root proj1 "Child with no activity" 2026-08-05 0
  seed_session "$WEEKLY_DIGEST_DB" ses_grandchild ses_child proj1 "Grandchild doing the work" 2026-08-19 0
  seed_message "$WEEKLY_DIGEST_DB" ses_grandchild user 2026-08-20 0 "subagent prompt"
  run "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh
  [ "$status" -eq 0 ]
  [[ "$output" == *"### Root before window"* ]]
  [[ "$output" == *"CARRIED-OVER from 2026-08-05"* ]]
  [[ "$output" != *"### Child with no activity"* ]]
  [[ "$output" != *"### Grandchild doing the work"* ]]
}

@test "sessions: a root created inside the window is new, not carried, when only found via the grandchild walk" {
  seed_project "$WEEKLY_DIGEST_DB" proj1 /work/alpha
  seed_session "$WEEKLY_DIGEST_DB" ses_root3 - proj1 "Root spawned this week" 2026-08-18 0
  seed_session "$WEEKLY_DIGEST_DB" ses_child3 ses_root3 proj1 "Child passthrough this week" 2026-08-18 0
  seed_session "$WEEKLY_DIGEST_DB" ses_grandchild3 ses_child3 proj1 "Grandchild acted this week" 2026-08-19 0
  seed_message "$WEEKLY_DIGEST_DB" ses_grandchild3 user 2026-08-19 0 "subagent prompt"
  run "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh
  [ "$status" -eq 0 ]
  [[ "$output" == *"### Root spawned this week"* ]]
  [[ "$output" != *"CARRIED-OVER"* ]]
  [[ "$output" != *"### Child passthrough this week"* ]]
  [[ "$output" != *"### Grandchild acted this week"* ]]
}

@test "sessions: a root reachable both directly and via the walk is reported once" {
  seed_project "$WEEKLY_DIGEST_DB" proj1 /work/alpha
  seed_session "$WEEKLY_DIGEST_DB" ses_root4 - proj1 "Root reached twice" 2026-08-18 0
  seed_message "$WEEKLY_DIGEST_DB" ses_root4 user 2026-08-18 0 "root's own activity"
  seed_session "$WEEKLY_DIGEST_DB" ses_child4 ses_root4 proj1 "Child link for twice-reached root" 2026-08-18 0
  seed_session "$WEEKLY_DIGEST_DB" ses_grandchild4 ses_child4 proj1 "Grandchild link for twice-reached root" 2026-08-19 0
  seed_message "$WEEKLY_DIGEST_DB" ses_grandchild4 user 2026-08-19 0 "subagent prompt"
  run "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh
  [ "$status" -eq 0 ]
  count="$(printf '%s\n' "$output" | grep -c '^### Root reached twice')"
  [ "$count" -eq 1 ]
}

@test "sessions: an empty window says so and reports recorded history" {
  seed_week
  run "$WD" --from 2026-01-01 --to 2026-01-07 --no-gh
  [ "$status" -eq 0 ]
  [[ "$output" == *"no opencode sessions in window"* ]]
  [[ "$output" == *"2026-07-01"* ]]
  [[ "$output" == *"2026-08-20"* ]]
}

@test "prompts: every in-window user prompt is listed" {
  seed_week
  run "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh
  [ "$status" -eq 0 ]
  [[ "$output" == *"USER: do the thing"* ]]
  [[ "$output" == *"USER: carried over prompt"* ]]
}

@test "prompts: a carried-over session's earlier prompts are excluded" {
  seed_week
  run "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh
  [ "$status" -eq 0 ]
  [[ "$output" != *"prehistoric prompt"* ]]
}

@test "prompts: the final assistant message is the last one in the window" {
  seed_week
  run "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh
  [ "$status" -eq 0 ]
  [[ "$output" == *"FINAL: carried over answer"* ]]
  [[ "$output" != *"FINAL: old answer"* ]]
}

@test "prompts: text is truncated at --max-chars" {
  seed_project "$WEEKLY_DIGEST_DB" proj1 /work/alpha
  seed_session "$WEEKLY_DIGEST_DB" ses_long - proj1 "Long prompt" 2026-08-19 0.50
  seed_message "$WEEKLY_DIGEST_DB" ses_long user 2026-08-19 0 \
    "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
  run "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh --max-chars 10
  [ "$status" -eq 0 ]
  [[ "$output" == *"USER: AAAAAAAAAA"* ]]
  [[ "$output" != *"USER: AAAAAAAAAAA"* ]]
}

@test "prompts: newlines are folded so one prompt stays on one line" {
  seed_project "$WEEKLY_DIGEST_DB" proj1 /work/alpha
  seed_session "$WEEKLY_DIGEST_DB" ses_nl - proj1 "Multiline" 2026-08-19 0.50
  seed_message "$WEEKLY_DIGEST_DB" ses_nl user 2026-08-19 0 "first
second"
  run "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh
  [ "$status" -eq 0 ]
  [[ "$output" == *"USER: first / second"* ]]
}

# seed_tree — a root with a nested subagent chain, all active in the window.
seed_tree() {
  seed_project "$WEEKLY_DIGEST_DB" proj1 /work/alpha
  seed_session "$WEEKLY_DIGEST_DB" ses_root -        proj1 "Has subagents" 2026-08-19 1.00
  seed_session "$WEEKLY_DIGEST_DB" ses_kid  ses_root proj1 "Child"         2026-08-19 2.00
  seed_session "$WEEKLY_DIGEST_DB" ses_gkid ses_kid  proj1 "Grandchild"    2026-08-19 3.00
  seed_message "$WEEKLY_DIGEST_DB" ses_root user      2026-08-19 0    "start"
  seed_message "$WEEKLY_DIGEST_DB" ses_root assistant 2026-08-19 1.00 "done"
  seed_message "$WEEKLY_DIGEST_DB" ses_kid  assistant 2026-08-19 2.00 "child work"
  seed_message "$WEEKLY_DIGEST_DB" ses_gkid assistant 2026-08-19 3.00 "grandchild work"
}

@test "subagents: nested descendants are counted and their cost summed" {
  seed_tree
  run "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh
  [ "$status" -eq 0 ]
  [[ "$output" == *"subagents: 2"* ]]
  [[ "$output" == *"5.00"* ]]
}

@test "subagents: a child session is not reported as a root" {
  seed_tree
  run "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh
  [ "$status" -eq 0 ]
  [[ "$output" != *"### Child"* ]]
  [[ "$output" != *"### Grandchild"* ]]
}

@test "cost: only in-window messages count toward a session's cost" {
  seed_week
  run "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh
  [ "$status" -eq 0 ]
  # ses_old spent 5.00 before the window and 4.00 inside it.
  [[ "$output" == *"cost: 4.00"* ]]
  [[ "$output" != *"cost: 9.00"* ]]
}

@test "cost: a user message's cost is not counted toward a session's cost" {
  seed_project "$WEEKLY_DIGEST_DB" proj1 /work/alpha
  seed_session "$WEEKLY_DIGEST_DB" ses_usercost - proj1 "User cost ignored" 2026-08-19 1.50
  # Real data never attributes a cost to a user message; this seeds one
  # anyway to pin the assistant-only filter so per-session cost and the
  # stats total cannot silently diverge again.
  seed_message "$WEEKLY_DIGEST_DB" ses_usercost user 2026-08-19 9.00 "do the thing"
  seed_message "$WEEKLY_DIGEST_DB" ses_usercost assistant 2026-08-19 1.50 "did the thing"
  run "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh
  [ "$status" -eq 0 ]
  [[ "$output" == *"cost: 1.50"* ]]
  [[ "$output" != *"cost: 10.50"* ]]
}

@test "trivial: a single-prompt cheap session is flagged" {
  seed_project "$WEEKLY_DIGEST_DB" proj1 /work/alpha
  seed_session "$WEEKLY_DIGEST_DB" ses_test - proj1 "Just testing" 2026-08-19 0.03
  seed_message "$WEEKLY_DIGEST_DB" ses_test user      2026-08-19 0    "testing a thing"
  seed_message "$WEEKLY_DIGEST_DB" ses_test assistant 2026-08-19 0.03 "ok"
  run "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh
  [ "$status" -eq 0 ]
  [[ "$output" == *"LIKELY-TRIVIAL"* ]]
}

@test "trivial: a substantive session is not flagged" {
  seed_week
  run "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh
  [ "$status" -eq 0 ]
  [[ "$output" != *"LIKELY-TRIVIAL"* ]]
}

@test "trivial: a cost of exactly 0.20 is not flagged, only strictly below it" {
  seed_project "$WEEKLY_DIGEST_DB" proj1 /work/alpha
  seed_session "$WEEKLY_DIGEST_DB" ses_boundary - proj1 "Right at the boundary" 2026-08-19 0.20
  seed_message "$WEEKLY_DIGEST_DB" ses_boundary user      2026-08-19 0    "one prompt"
  seed_message "$WEEKLY_DIGEST_DB" ses_boundary assistant 2026-08-19 0.20 "ok"
  run "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh
  [ "$status" -eq 0 ]
  [[ "$output" != *"LIKELY-TRIVIAL"* ]]
}

@test "trivial: a cheap session with more than one prompt is not flagged" {
  seed_project "$WEEKLY_DIGEST_DB" proj1 /work/alpha
  seed_session "$WEEKLY_DIGEST_DB" ses_twoprompt - proj1 "Cheap but chatty" 2026-08-19 0.03
  seed_message "$WEEKLY_DIGEST_DB" ses_twoprompt user      2026-08-19 0    "first prompt"
  seed_message "$WEEKLY_DIGEST_DB" ses_twoprompt user      2026-08-19 0    "second prompt"
  seed_message "$WEEKLY_DIGEST_DB" ses_twoprompt assistant 2026-08-19 0.03 "ok"
  run "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh
  [ "$status" -eq 0 ]
  [[ "$output" != *"LIKELY-TRIVIAL"* ]]
}

@test "stats: totals count only in-window cost" {
  seed_week
  run "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh
  [ "$status" -eq 0 ]
  # 1.50 in ses_new plus 4.00 in ses_old; the 5.00 before the window is excluded.
  [[ "$output" == *"cost: 5.50"* ]]
}

@test "stats: token classes are reported separately" {
  seed_week
  run "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh
  [ "$status" -eq 0 ]
  [[ "$output" == *"input="* ]]
  [[ "$output" == *"output="* ]]
  [[ "$output" == *"cache_read="* ]]
}

@test "stats: per-repo breakdown lists each worktree" {
  seed_week
  run "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh
  [ "$status" -eq 0 ]
  # Matches the per-repo line's own shape ('  ' + %8.2f cost + '  ' + repo),
  # which the sessions section's plain 'repo: <path>' lines cannot produce.
  alpha_count="$(printf '%s\n' "$output" | grep -cE '^  +[0-9]+\.[0-9]{2}  /work/alpha$')"
  beta_count="$(printf '%s\n' "$output" | grep -cE '^  +[0-9]+\.[0-9]{2}  /work/beta$')"
  [ "$alpha_count" -eq 1 ]
  [ "$beta_count" -eq 1 ]
}

@test "stats: the per-repo list has a column header labelling cost and repo" {
  seed_week
  run "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh
  [ "$status" -eq 0 ]
  header_count="$(printf '%s\n' "$output" | grep -cE '^ +cost  repo$')"
  [ "$header_count" -eq 1 ]
}

@test "stats: session counts distinguish roots from the total" {
  seed_tree
  run "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh
  [ "$status" -eq 0 ]
  root_count="$(printf '%s\n' "$output" | grep -c '^root sessions: 1$')"
  session_count="$(printf '%s\n' "$output" | grep -c '^sessions: 3$')"
  [ "$root_count" -eq 1 ]
  [ "$session_count" -eq 1 ]
}

@test "stats: an orphaned message's session_id does not inflate the count beyond what sessions reports" {
  seed_project "$WEEKLY_DIGEST_DB" proj1 /work/alpha
  seed_session "$WEEKLY_DIGEST_DB" ses_real - proj1 "Has a real session row" 2026-08-19 1.00
  seed_message "$WEEKLY_DIGEST_DB" ses_real assistant 2026-08-19 1.00 "did the thing"
  # No matching session row for this session_id: emit_sessions' parent_id
  # walk through session can never find it, so emit_stats' count must agree
  # that it does not exist either, or the two sections contradict each other.
  seed_message "$WEEKLY_DIGEST_DB" ses_orphan_msg assistant 2026-08-19 1.00 "orphaned"
  run "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\nsessions: 1\n'* ]]
  [[ "$output" == *"### Has a real session row"* ]]
}

@test "stats: a session whose parent_id names a nonexistent session does not inflate the count beyond what sessions reports" {
  seed_project "$WEEKLY_DIGEST_DB" proj1 /work/alpha
  # ses_ghost has its own valid session row, but its parent_id points at a
  # session that was never seeded: emit_sessions' root walk can never reach
  # a root for it, so it reports nothing for this chain. emit_stats must
  # agree, or the report claims both spend and "no sessions" at once.
  seed_session "$WEEKLY_DIGEST_DB" ses_ghost ghost_parent proj1 "Parent points nowhere" 2026-08-19 3.00
  seed_message "$WEEKLY_DIGEST_DB" ses_ghost assistant 2026-08-19 3.00 "did the thing"
  run "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\nsessions: 0\n'* ]]
  [[ "$output" == *"no opencode sessions in window"* ]]
}

@test "prs: classified as opened, merged or merely touched" {
  seed_week
  # gh search prs reports state lowercase; this pins that reality rather
  # than the uppercase gh pr view uses.
  stub_gh <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "search" ]; then
  cat <<'ROWS'
owner/one|11|merged|2026-08-19T10:00:00Z|2026-08-19T11:00:00Z|Opened and merged inside
owner/two|22|merged|2026-08-01T10:00:00Z|2026-08-20T11:00:00Z|Opened earlier merged inside
owner/three|33|open|2026-08-02T10:00:00Z|0001-01-01T00:00:00Z|Still open
ROWS
  exit 0
fi
if [ "$1" = "pr" ]; then
  echo "REVIEW_REQUIRED|BLOCKED|false"
  exit 0
fi
exit 1
EOF
  run "$WD" --from 2026-08-17 --to 2026-08-23
  [ "$status" -eq 0 ]
  [[ "$output" == *"owner/one#11 opened-in-window"* ]]
  [[ "$output" == *"owner/two#22 merged-in-window"* ]]
  [[ "$output" == *"owner/three#33 touched-only"* ]]
}

@test "prs: a pull request opened before the window and merged inside it is merged-in-window" {
  seed_week
  # Pins the live defect: created 2026-08-01 (before the window), merged
  # 2026-08-19 (inside it), state lowercase as gh search prs actually
  # returns it.
  stub_gh <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "search" ]; then
  echo "owner/four|44|merged|2026-08-01T10:00:00Z|2026-08-19T11:00:00Z|Opened earlier merged inside"
  exit 0
fi
if [ "$1" = "pr" ]; then
  echo "REVIEW_REQUIRED|BLOCKED|false"
  exit 0
fi
exit 1
EOF
  run "$WD" --from 2026-08-17 --to 2026-08-23
  [ "$status" -eq 0 ]
  [[ "$output" == *"owner/four#44 merged-in-window"* ]]
}

@test "prs: a merged pull request triggers no enrichment lookup" {
  seed_week
  # If emit_prs ever calls gh pr view for a merged PR again, this stub makes
  # that loud: it drops a marker file and returns a review state that would
  # otherwise sail through unnoticed.
  stub_gh <<EOF
#!/usr/bin/env bash
if [ "\$1" = "search" ]; then
  echo "owner/five|55|merged|2026-08-01T10:00:00Z|2026-08-19T11:00:00Z|Merged, should not be enriched"
  exit 0
fi
if [ "\$1" = "pr" ]; then
  touch "$STUB_BIN/enrichment-called"
  echo "REVIEW_REQUIRED|BLOCKED|false"
  exit 0
fi
exit 1
EOF
  run "$WD" --from 2026-08-17 --to 2026-08-23
  [ "$status" -eq 0 ]
  [[ "$output" == *"owner/five#55 merged-in-window"* ]]
  [[ "$output" != *"review:"* ]]
  [ ! -e "$STUB_BIN/enrichment-called" ]
}

@test "prs: an uppercase merged state (as gh pr view reports it) is still handled" {
  seed_week
  # Pins the other casing: if gh changes what gh search prs emits, or a
  # future caller feeds this function gh pr view's uppercase form, the
  # classification and enrichment guard must still agree.
  stub_gh <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "search" ]; then
  echo "owner/six|66|MERGED|2026-08-01T10:00:00Z|2026-08-19T11:00:00Z|Uppercase merged state"
  exit 0
fi
if [ "$1" = "pr" ]; then
  echo "gh pr view should not be called for a merged PR" >&2
  exit 1
fi
exit 1
EOF
  run "$WD" --from 2026-08-17 --to 2026-08-23
  [ "$status" -eq 0 ]
  [[ "$output" == *"owner/six#66 merged-in-window"* ]]
  [[ "$output" != *"review:"* ]]
}

@test "prs: anything not merged is enriched with review state" {
  seed_week
  stub_gh <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "search" ]; then
  echo "owner/three|33|open|2026-08-02T10:00:00Z|0001-01-01T00:00:00Z|Still open"
  exit 0
fi
if [ "$1" = "pr" ]; then
  echo "REVIEW_REQUIRED|BLOCKED|false"
  exit 0
fi
exit 1
EOF
  run "$WD" --from 2026-08-17 --to 2026-08-23
  [ "$status" -eq 0 ]
  [[ "$output" == *"review: REVIEW_REQUIRED"* ]]
  [[ "$output" == *"merge: BLOCKED"* ]]
}

@test "prs: --no-gh states the section is unavailable rather than empty" {
  seed_week
  run "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh
  [ "$status" -eq 0 ]
  [[ "$output" == *"## pull requests"* ]]
  [[ "$output" == *"unavailable: --no-gh"* ]]
}

@test "prs: a missing gh states the section is unavailable" {
  seed_week
  # A PATH holding only the externals the digest genuinely needs, so gh is
  # absent rather than merely broken. Stubbing a gh that exits non-zero would
  # exercise the search-failure path instead, which is a different test.
  # bash is symlinked in too: without it the script dies at its
  # `#!/usr/bin/env bash` shebang with status 127 before running any of its
  # own logic.
  # jq and find are needed too: the default --source of both reads the Claude
  # Code transcripts, and the script refuses to run without them rather than
  # silently reporting an empty transcript tree.
  mkdir -p "$BATS_TEST_TMPDIR/minimal-bin"
  ln -s "$(command -v bash)" "$BATS_TEST_TMPDIR/minimal-bin/bash"
  ln -s "$(command -v sqlite3)" "$BATS_TEST_TMPDIR/minimal-bin/sqlite3"
  ln -s "$(command -v jq)" "$BATS_TEST_TMPDIR/minimal-bin/jq"
  ln -s "$(command -v find)" "$BATS_TEST_TMPDIR/minimal-bin/find"
  ln -s "$(command -v sort)" "$BATS_TEST_TMPDIR/minimal-bin/sort"
  run env PATH="$BATS_TEST_TMPDIR/minimal-bin" "$WD" --from 2026-08-17 --to 2026-08-23
  [ "$status" -eq 0 ]
  [[ "$output" == *"unavailable: gh is not installed"* ]]
}

@test "prs: a failing gh does not produce an empty list" {
  seed_week
  stub_gh <<'EOF'
#!/usr/bin/env bash
echo "gh: authentication required" >&2
exit 4
EOF
  run "$WD" --from 2026-08-17 --to 2026-08-23
  [ "$status" -eq 0 ]
  [[ "$output" == *"unavailable"* ]]
  [[ "$output" != *"no pull requests"* ]]
}

@test "prs: a genuinely empty result is distinguishable from a failure" {
  seed_week
  stub_gh <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  run "$WD" --from 2026-08-17 --to 2026-08-23
  [ "$status" -eq 0 ]
  [[ "$output" == *"none found"* ]]
  [[ "$output" != *"unavailable"* ]]
}

@test "prs: an unparseable non-empty gh row is distinguishable from a failure or an empty result" {
  seed_week
  # Non-empty output that fails every field check: rows is non-empty so the
  # "none found" branch is skipped, but the row itself is skipped too, so
  # without an explicit marker the section prints its header with nothing
  # beneath it -- indistinguishable from "no pull requests this week".
  stub_gh <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "search" ]; then
  echo "|||||"
  exit 0
fi
exit 1
EOF
  run "$WD" --from 2026-08-17 --to 2026-08-23
  [ "$status" -eq 0 ]
  [[ "$output" == *"unavailable: could not parse gh output"* ]]
  [[ "$output" != *"none found"* ]]
}

@test "output: the four sections appear in order" {
  seed_week
  run "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh
  [ "$status" -eq 0 ]
  order="$(printf '%s\n' "$output" | grep '^## ' | tr '\n' ' ')"
  [ "$order" = "## window ## stats ## pull requests ## sessions " ]
}

@test "database: is not modified by a run" {
  seed_week
  before="$(shasum -a 256 "$WEEKLY_DIGEST_DB" | cut -d' ' -f1)"
  run "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh
  [ "$status" -eq 0 ]
  after="$(shasum -a 256 "$WEEKLY_DIGEST_DB" | cut -d' ' -f1)"
  [ "$before" = "$after" ]
}

# This is a guard on the source text, not a behavioural test: the fixture's
# WAL is checkpointed to empty as soon as each one-shot seed_* helper's
# connection closes, so mode=ro and mode=ro&immutable=1 return identical
# results against it, and no fixture can distinguish the two behaviourally.
# See the comment at db_query in bin/weekly-digest for why immutable=1 would
# be wrong against the real (actively written) database. This checks the
# actual sqlite3 invocation line, not the file as a whole -- comments nearby
# legitimately say "immutable" when explaining the choice not to use it.
@test "guard: db_query connects with mode=ro and never immutable" {
  run grep 'sqlite3 -readonly -batch' "$WD"
  [ "$status" -eq 0 ]
  [[ "$output" == *'mode=ro'* ]]
  [[ "$output" != *'immutable'* ]]
}

@test "database: a missing database is a clear error" {
  # Triggers SC2030/SC2031 on any later test reading WEEKLY_DIGEST_DB --
  # the linter models each @test as a subshell, so it's a lint-order
  # artifact, not real leakage; fixture-building tests must stay above
  # this one, and neither `unset` nor a subshell wrapper clears it.
  export WEEKLY_DIGEST_DB="$BATS_TEST_TMPDIR/nope.db"
  run "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh
  [ "$status" -eq 1 ]
  [[ "$output" == *"no such database"* ]]
}

@test "database: a missing sqlite3 is a clear error" {
  seed_week
  # bash must be on the restricted PATH or the script dies at its
  # `#!/usr/bin/env bash` shebang with status 127 before any of its own checks
  # run, and the test would pass for entirely the wrong reason.
  mkdir -p "$BATS_TEST_TMPDIR/no-bin"
  ln -s "$(command -v bash)" "$BATS_TEST_TMPDIR/no-bin/bash"
  run env PATH="$BATS_TEST_TMPDIR/no-bin" "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh
  [ "$status" -eq 1 ]
  [[ "$output" == *"sqlite3 is not installed"* ]]
}

# --- Claude Code transcripts -------------------------------------------------

seed_cc_week() {
  seed_cc_title cc-alpha ses_cc "Claude session this week"
  seed_cc_prompt cc-alpha ses_cc /work/alpha 2026-08-19 "make it work"
  seed_cc_assistant cc-alpha ses_cc /work/alpha 2026-08-19 claude-opus-5 40 msg_a "it works"

  seed_cc_title cc-beta ses_cc_old "Claude session from before"
  seed_cc_prompt cc-beta ses_cc_old /work/beta 2026-08-11 "prehistoric claude prompt"
  seed_cc_prompt cc-beta ses_cc_old /work/beta 2026-08-20 "carried over claude prompt"
  seed_cc_assistant cc-beta ses_cc_old /work/beta 2026-08-20 claude-opus-5 60 msg_b "carried answer"

  seed_cc_title cc-alpha ses_cc_away "Claude session nowhere near"
  seed_cc_prompt cc-alpha ses_cc_away /work/alpha 2026-07-01 "unrelated claude prompt"
}

@test "claude: a session active in the window is reported and labelled by tool" {
  seed_cc_week
  run "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh
  [ "$status" -eq 0 ]
  [[ "$output" == *"### Claude session this week"* ]]
  [[ "$output" == *"tool: claude-code"* ]]
}

@test "claude: a session outside the window is not reported" {
  seed_cc_week
  run "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh
  [ "$status" -eq 0 ]
  [[ "$output" != *"Claude session nowhere near"* ]]
}

@test "claude: a session started earlier but active in the window is marked carried over" {
  seed_cc_week
  run "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh
  [ "$status" -eq 0 ]
  [[ "$output" == *"### Claude session from before"* ]]
  [[ "$output" == *"CARRIED-OVER from 2026-08-11"* ]]
}

@test "claude: a carried-over session's earlier prompts are excluded" {
  seed_cc_week
  run "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh
  [ "$status" -eq 0 ]
  [[ "$output" == *"USER: carried over claude prompt"* ]]
  [[ "$output" != *"prehistoric claude prompt"* ]]
}

@test "claude: the repo comes from the transcript's cwd and the branch is reported" {
  seed_cc_week
  run "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh
  [ "$status" -eq 0 ]
  [[ "$output" == *"repo: /work/alpha"* ]]
  [[ "$output" == *"branch: main"* ]]
}

@test "claude: a session with no ai-title falls back to its first prompt" {
  seed_cc_prompt cc-alpha ses_untitled /work/alpha 2026-08-19 "untitled session's opening prompt"
  run "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh
  [ "$status" -eq 0 ]
  [[ "$output" == *"### untitled session's opening prompt"* ]]
}

@test "claude: the last assistant message in the window is the closing message" {
  seed_cc_title cc-alpha ses_fin "Session with two answers"
  seed_cc_prompt cc-alpha ses_fin /work/alpha 2026-08-19 "first ask"
  seed_cc_assistant cc-alpha ses_fin /work/alpha 2026-08-19 claude-opus-5 10 msg_f1 "first answer"
  seed_cc_assistant cc-alpha ses_fin /work/alpha 2026-08-20 claude-opus-5 10 msg_f2 "last answer"
  run "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh
  [ "$status" -eq 0 ]
  [[ "$output" == *"FINAL: last answer"* ]]
  [[ "$output" != *"FINAL: first answer"* ]]
}

# The real format writes one record per content block, each repeating the same
# message.id and usage, with usage growing as the message streams. Counting per
# record would multiply the totals; the last record for an id is the completed
# figure. This is the single most important claude-side behaviour to hold.
@test "claude: repeated records for one message id are counted once, at their final usage" {
  seed_cc_title cc-alpha ses_dup "Streamed message"
  seed_cc_prompt cc-alpha ses_dup /work/alpha 2026-08-19 "stream it"
  seed_cc_assistant cc-alpha ses_dup /work/alpha 2026-08-19 claude-opus-5 5 msg_same "thinking"
  seed_cc_assistant cc-alpha ses_dup /work/alpha 2026-08-19 claude-opus-5 5 msg_same "tool use"
  seed_cc_assistant cc-alpha ses_dup /work/alpha 2026-08-19 claude-opus-5 700 msg_same "final text"
  run "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh --source claude
  [ "$status" -eq 0 ]
  [[ "$output" == *"output=700"* ]]
  [[ "$output" != *"output=710"* ]]
  [[ "$output" != *"output=1400"* ]]
  [[ "$output" != *"output=2100"* ]]
}

@test "claude: a prompt from another surface is kept and labelled with its source" {
  seed_cc_title cc-alpha ses_sdk "Headless session"
  seed_cc_prompt cc-alpha ses_sdk /work/alpha 2026-08-19 "run it headless" sdk ""
  run "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh
  [ "$status" -eq 0 ]
  [[ "$output" == *"USER[sdk]: run it headless"* ]]
}

@test "claude: an injected task notification is not reported as a prompt" {
  seed_cc_title cc-alpha ses_notif "Session with a notification"
  seed_cc_prompt cc-alpha ses_notif /work/alpha 2026-08-19 "real work please"
  seed_cc_prompt cc-alpha ses_notif /work/alpha 2026-08-19 \
    "a background job finished" typed task-notification
  run "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh
  [ "$status" -eq 0 ]
  [[ "$output" == *"USER: real work please"* ]]
  [[ "$output" != *"a background job finished"* ]]
}

@test "claude: subagents are counted with their type and output tokens" {
  seed_cc_title cc-alpha ses_sub "Session that delegated"
  seed_cc_prompt cc-alpha ses_sub /work/alpha 2026-08-19 "delegate this"
  seed_cc_assistant cc-alpha ses_sub /work/alpha 2026-08-19 claude-opus-5 40 msg_s "delegated"
  seed_cc_subagent cc-alpha ses_sub aaa Explore /work/alpha 2026-08-19 900
  run "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh
  [ "$status" -eq 0 ]
  [[ "$output" == *"subagents: 1 (output tokens 900) types: Explore"* ]]
}

@test "claude: a subagent active outside the window is not counted" {
  seed_cc_title cc-alpha ses_sub2 "Session that delegated last month"
  seed_cc_prompt cc-alpha ses_sub2 /work/alpha 2026-08-19 "delegate this"
  seed_cc_subagent cc-alpha ses_sub2 bbb Explore /work/alpha 2026-07-01 900
  run "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh
  [ "$status" -eq 0 ]
  [[ "$output" == *"subagents: 0 (output tokens 0)"* ]]
}

@test "claude: stats state that no cost is recorded rather than reporting zero" {
  seed_cc_week
  run "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh
  [ "$status" -eq 0 ]
  [[ "$output" == *"cost: (unavailable: Claude Code transcripts record no cost)"* ]]
}

@test "claude: stats break output tokens down by model and by repo" {
  seed_cc_title cc-alpha ses_m1 "Opus work"
  seed_cc_prompt cc-alpha ses_m1 /work/alpha 2026-08-19 "opus please"
  seed_cc_assistant cc-alpha ses_m1 /work/alpha 2026-08-19 claude-opus-5 500 msg_m1 "opus answer"
  seed_cc_title cc-beta ses_m2 "Haiku work"
  seed_cc_prompt cc-beta ses_m2 /work/beta 2026-08-19 "haiku please"
  seed_cc_assistant cc-beta ses_m2 /work/beta 2026-08-19 claude-haiku-4-5-20251001 30 msg_m2 "haiku answer"
  run "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh --source claude
  [ "$status" -eq 0 ]
  [[ "$output" == *"per-model:"* ]]
  [[ "$output" == *"500  claude-opus-5"* ]]
  [[ "$output" == *"30  claude-haiku-4-5-20251001"* ]]
  [[ "$output" == *"per-repo:"* ]]
  [[ "$output" == *"500  /work/alpha"* ]]
  [[ "$output" == *"30  /work/beta"* ]]
}

@test "claude: subagent tokens are included in the stats totals" {
  seed_cc_title cc-alpha ses_st "Session that delegated"
  seed_cc_prompt cc-alpha ses_st /work/alpha 2026-08-19 "delegate this"
  seed_cc_assistant cc-alpha ses_st /work/alpha 2026-08-19 claude-opus-5 100 msg_st "delegated"
  seed_cc_subagent cc-alpha ses_st ccc Explore /work/alpha 2026-08-19 900
  run "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh --source claude
  [ "$status" -eq 0 ]
  # 100 from the session itself plus 900 from its subagent.
  [[ "$output" == *"tokens: input=11 output=1000"* ]]
}

@test "claude: an empty window says so" {
  seed_cc_week
  run "$WD" --from 2026-01-01 --to 2026-01-07 --no-gh
  [ "$status" -eq 0 ]
  [[ "$output" == *"no claude-code sessions in window"* ]]
}

# The overrides here are passed in the same command as the invocation rather
# than exported into the test: re-exporting a variable another test also sets
# reads to shellcheck as a lost subshell modification (SC2030/SC2031).
@test "claude: a missing transcript directory is unavailable, not fatal" {
  run env WEEKLY_DIGEST_CLAUDE_DIR="$BATS_TEST_TMPDIR/not-there" \
    "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh
  [ "$status" -eq 0 ]
  [[ "$output" == *"unavailable: no such transcript directory"* ]]
}

@test "source: opencode omits the claude-code sections entirely" {
  seed_week
  seed_cc_week
  run "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh --source opencode
  [ "$status" -eq 0 ]
  [[ "$output" == *"### opencode"* ]]
  [[ "$output" == *"Inside the window"* ]]
  [[ "$output" != *"### claude-code"* ]]
  [[ "$output" != *"Claude session this week"* ]]
}

@test "source: claude omits the opencode sections entirely" {
  seed_week
  seed_cc_week
  run "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh --source claude
  [ "$status" -eq 0 ]
  [[ "$output" == *"### claude-code"* ]]
  [[ "$output" == *"Claude session this week"* ]]
  [[ "$output" != *"### opencode"* ]]
  [[ "$output" != *"Inside the window"* ]]
}

@test "source: both reports each session under its own tool" {
  seed_week
  seed_cc_week
  run "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh
  [ "$status" -eq 0 ]
  [[ "$output" == *"tool: opencode"* ]]
  [[ "$output" == *"tool: claude-code"* ]]
}

@test "source: an unknown value is rejected" {
  run "$WD" --from 2026-08-17 --to 2026-08-23 --source vscode
  [ "$status" -ne 0 ]
  [[ "$output" == *"--source must be opencode, claude or both"* ]]
}

@test "source: a claude-only run does not need the opencode database" {
  seed_cc_week
  run env WEEKLY_DIGEST_DB="$BATS_TEST_TMPDIR/absent.db" \
    "$WD" --from 2026-08-17 --to 2026-08-23 --no-gh --source claude
  [ "$status" -eq 0 ]
  [[ "$output" != *"no such database"* ]]
  [[ "$output" == *"Claude session this week"* ]]
}

# Guard on the fixture builder's source text, not a behavioural test: a
# WEEKLY_DIGEST_CLAUDE_DIR that resolved to the real ~/.claude/projects would
# make the suite read months of genuine transcripts, and every assertion about
# session counts would then depend on the developer's own history. Checking the
# assignment itself catches that at the one place it could be introduced.
@test "guard: the claude fixture tree is seeded inside the test tmpdir" {
  run grep 'WEEKLY_DIGEST_CLAUDE_DIR=' \
    "$BATS_TEST_DIRNAME/helpers/weekly-digest-setup.bash"
  [ "$status" -eq 0 ]
  # The literal text of the assignment is what is being checked, so the
  # variable reference must not expand here.
  # shellcheck disable=SC2016
  [[ "$output" == *'$BATS_TEST_TMPDIR'* ]]
  [[ "$output" != *'.claude'* ]]
}
