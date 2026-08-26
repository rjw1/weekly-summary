# Fixture builder for weekly-digest tests.
#
# Creates minimal stand-ins for the two histories weekly-digest reads: the
# opencode database (only the columns it queries) and a tree of Claude Code
# JSONL transcripts. Nothing here may touch the real database or the real
# ~/.claude/projects; every test points both at $BATS_TEST_TMPDIR, and the
# "guard" test asserts that.

setup_weekly_digest_env() {
  WD="$BATS_TEST_DIRNAME/../bin/weekly-digest"
  export WD
  export WEEKLY_DIGEST_DB="$BATS_TEST_TMPDIR/opencode.db"
  export WEEKLY_DIGEST_CLAUDE_DIR="$BATS_TEST_TMPDIR/claude-projects"
  export WEEKLY_DIGEST_GEMINI_DIR="$BATS_TEST_TMPDIR/gemini-sessions"
  export STUB_BIN="$BATS_TEST_TMPDIR/stub-bin"
  # An existing but empty transcript tree by default: --source defaults to
  # all, so a test that seeds only the database still exercises the claude
  # and gemini readers, and must find an empty tree rather than a missing one
  # (a missing directory is reported as unavailable, which is its own test
  # below).
  mkdir -p "$STUB_BIN" "$WEEKLY_DIGEST_CLAUDE_DIR" "$WEEKLY_DIGEST_GEMINI_DIR"
  # The digest derives a message's calendar day in local time, from sqlite's
  # 'localtime' on one side and jq's strflocaltime on the other. The fixtures
  # below write timestamps at noon UTC, so pinning the suite to UTC keeps the
  # day a fixture claims and the day the digest derives identical, instead of
  # depending on the developer's zone.
  export TZ=UTC
  # A valid, empty database by default: main() always calls require_db and
  # emit_sessions, so window-only tests need a real (if empty) fixture to
  # query even when they never seed a session.
  make_fixture_db "$WEEKLY_DIGEST_DB"
}

# make_fixture_db <path> — creates the schema once. Called from
# setup_weekly_digest_env for every test; do not call it again from a test
# body. A plain CREATE TABLE errors on a second call against an
# already-provisioned database, which is deliberate: a future schema edit
# here must not be able to silently skip itself on a database that already
# has the old tables.
#
# This does not set PRAGMA journal_mode=WAL. It was tried, to exercise the
# script's deliberate mode=ro-without-immutable=1 choice, but every seed_*
# helper opens a one-shot sqlite3 connection, and sqlite checkpoints the WAL
# to empty when the last connection to a database closes — so the -wal file
# is 0 bytes by the time any test reads the fixture, and mode=ro and
# immutable=1 return identical results against it. See the "guard" test in
# weekly-digest.bats for how that choice is actually verified instead.
make_fixture_db() {
  sqlite3 "$1" <<'SQL'
CREATE TABLE project (id text PRIMARY KEY, worktree text NOT NULL);
CREATE TABLE session (
  id text PRIMARY KEY, project_id text, parent_id text, title text NOT NULL,
  directory text NOT NULL DEFAULT '', cost real NOT NULL DEFAULT 0,
  time_created integer NOT NULL
);
CREATE TABLE message (
  id text PRIMARY KEY, session_id text NOT NULL,
  time_created integer NOT NULL, data text NOT NULL
);
CREATE TABLE part (
  id text PRIMARY KEY, message_id text NOT NULL, session_id text NOT NULL,
  time_created integer NOT NULL, data text NOT NULL
);
SQL
}

# seed_project <db> <id> <worktree>
seed_project() {
  sqlite3 "$1" "INSERT INTO project (id,worktree) VALUES ('$2','$3');"
}

# seed_session <db> <id> <parent|-> <project> <title> <created-date> <cost>
seed_session() {
  local db="$1" id="$2" parent="$3" project="$4" title="$5" date="$6" cost="$7"
  local parent_sql="NULL"
  [ "$parent" = "-" ] || parent_sql="'$parent'"
  sqlite3 "$db" <<SQL
INSERT INTO session (id,project_id,parent_id,title,directory,cost,time_created)
VALUES ('$id','$project',$parent_sql,'$title','/tmp/$project',$cost,
        strftime('%s','$date 12:00:00')*1000);
SQL
}

# seed_message <db> <session-id> <role> <date> <cost> <text>
# Inserts one message plus one text part. Ids are derived from a per-db counter
# so callers never have to invent unique ids.
seed_message() {
  local db="$1" session="$2" role="$3" date="$4" cost="$5" text="$6"
  local n
  n="$(sqlite3 "$db" 'SELECT COUNT(*) FROM message;')"
  local mid="msg_$n" pid="prt_$n"
  local escaped="${text//\'/\'\'}"
  sqlite3 "$db" <<SQL
INSERT INTO message (id,session_id,time_created,data) VALUES (
  '$mid','$session',strftime('%s','$date 12:00:00')*1000,
  json_object('role','$role','cost',$cost,
              'tokens',json_object('input',10,'output',20,'reasoning',0,
                                   'cache',json_object('read',100,'write',0))));
INSERT INTO part (id,message_id,session_id,time_created,data) VALUES (
  '$pid','$mid','$session',strftime('%s','$date 12:00:00')*1000,
  json_object('type','text','text','$escaped'));
SQL
}

# --- Claude Code transcript fixtures -----------------------------------------
#
# Layout mirrors the real one: <projects>/<project>/<session-id>.jsonl for a
# session, and <projects>/<project>/<session-id>/subagents/agent-<id>.jsonl
# plus a matching .meta.json for each subagent it spawned.

cc_file() {
  printf '%s/%s/%s.jsonl' "$WEEKLY_DIGEST_CLAUDE_DIR" "$1" "$2"
}

# cc_append <project> <session-id> — append one JSON line read from stdin
cc_append() {
  local f
  f="$(cc_file "$1" "$2")"
  mkdir -p "${f%/*}"
  cat >> "$f"
}

# seed_cc_title <project> <session-id> <title>
# The ai-title record carries no timestamp in the real format, so a session
# needs at least one seeded prompt or assistant message to have a start date.
seed_cc_title() {
  jq -cn --arg sid "$2" --arg t "$3" \
    '{type:"ai-title",aiTitle:$t,sessionId:$sid}' | cc_append "$1" "$2"
}

# seed_cc_prompt <project> <session-id> <cwd> <date> <text> [prompt-source] [origin-kind]
# Defaults to a typed prompt of human origin. Pass an origin-kind of
# task-notification to seed a machine-injected message.
seed_cc_prompt() {
  local proj="$1" sid="$2" cwd="$3" date="$4" text="$5"
  local src="${6:-typed}" origin="${7:-human}"
  jq -cn --arg sid "$sid" --arg cwd "$cwd" --arg ts "${date}T12:00:00.000Z" \
         --arg text "$text" --arg src "$src" --arg origin "$origin" \
    '{type:"user",sessionId:$sid,cwd:$cwd,gitBranch:"main",timestamp:$ts,
      isSidechain:false,promptSource:$src,origin:{kind:$origin},
      message:{role:"user",content:$text}}' | cc_append "$proj" "$sid"
}

# seed_cc_assistant <project> <session-id> <cwd> <date> <model> <output-tokens> <message-id> <text>
# Writes ONE record. Call it repeatedly with the same message-id to reproduce
# the real format's per-content-block records, which all repeat the same
# message.id and usage.
seed_cc_assistant() {
  local proj="$1" sid="$2" cwd="$3" date="$4" model="$5" out="$6" mid="$7" text="$8"
  jq -cn --arg sid "$sid" --arg cwd "$cwd" --arg ts "${date}T12:00:00.000Z" \
         --arg model "$model" --argjson out "$out" --arg mid "$mid" --arg text "$text" \
    '{type:"assistant",sessionId:$sid,cwd:$cwd,gitBranch:"main",timestamp:$ts,
      isSidechain:false,
      message:{id:$mid,role:"assistant",model:$model,
               content:[{type:"text",text:$text}],
               usage:{input_tokens:10,output_tokens:$out,
                      cache_read_input_tokens:100,cache_creation_input_tokens:5,
                      output_tokens_details:{thinking_tokens:2}}}}' \
    | cc_append "$proj" "$sid"
}

# seed_cc_subagent <project> <session-id> <agent-id> <agent-type> <cwd> <date> <output-tokens>
seed_cc_subagent() {
  local proj="$1" sid="$2" agent="$3" type="$4" cwd="$5" date="$6" out="$7"
  local dir="$WEEKLY_DIGEST_CLAUDE_DIR/$proj/$sid/subagents"
  mkdir -p "$dir"
  jq -cn --arg sid "$sid" --arg cwd "$cwd" --arg ts "${date}T12:00:00.000Z" \
         --argjson out "$out" --arg mid "msg_${agent}" \
    '{type:"assistant",sessionId:$sid,cwd:$cwd,timestamp:$ts,isSidechain:true,
      message:{id:$mid,role:"assistant",model:"claude-haiku-4-5-20251001",
               content:[{type:"text",text:"subagent said so"}],
               usage:{input_tokens:1,output_tokens:$out,
                      cache_read_input_tokens:2,cache_creation_input_tokens:3,
                      output_tokens_details:{thinking_tokens:1}}}}' \
    > "$dir/agent-$agent.jsonl"
  jq -cn --arg t "$type" '{agentType:$t,spawnDepth:1}' > "$dir/agent-$agent.meta.json"
}

# stub_gh <<'EOF' ... EOF — install a fake gh on PATH reading its body from stdin
stub_gh() {
  cat > "$STUB_BIN/gh"
  chmod +x "$STUB_BIN/gh"
  PATH="$STUB_BIN:$PATH"
  export PATH
}

# --- Gemini CLI session fixtures ---------------------------------------------
#
# Layout mirrors the real one: <sessions>/<project>/chats/session-<stamp>.json
# holding one JSON object per session, and an optional <project>/.project_root
# naming the absolute path the project lives at.

# seed_gemini_project <project> <project-root-path>
seed_gemini_project() {
  mkdir -p "$WEEKLY_DIGEST_GEMINI_DIR/$1/chats"
  [ -z "${2:-}" ] || printf '%s' "$2" > "$WEEKLY_DIGEST_GEMINI_DIR/$1/.project_root"
}

# seed_gemini_session <project> <session-id> <start-date> <json-messages-array>
# start-date is YYYY-MM-DD; the fixture stamps it at noon UTC, matching the
# Claude seeders, so the suite's TZ=UTC keeps derived days stable.
seed_gemini_session() {
  local proj="$1" sid="$2" date="$3" messages="$4"
  mkdir -p "$WEEKLY_DIGEST_GEMINI_DIR/$proj/chats"
  jq -n --arg sid "$sid" --arg start "${date}T12:00:00.000Z" \
        --argjson msgs "$messages" \
    '{sessionId:$sid,projectHash:"unused",startTime:$start,
      lastUpdated:$start,messages:$msgs}' \
    > "$WEEKLY_DIGEST_GEMINI_DIR/$proj/chats/session-$sid.json"
}

# gmsg_user <date> <text> — one user message, for the messages array
gmsg_user() {
  jq -cn --arg ts "${1}T12:00:00.000Z" --arg t "$2" \
    '{id:"u",timestamp:$ts,type:"user",content:$t}'
}

# gmsg_model <date> <model> <output-tokens> <text> — one assistant message
gmsg_model() {
  jq -cn --arg ts "${1}T12:00:00.000Z" --arg m "$2" --argjson out "$3" --arg t "$4" \
    '{id:"g",timestamp:$ts,type:"gemini",model:$m,content:$t,thoughts:null,
      tokens:{input:10,output:$out,cached:1,thoughts:2,tool:3,
              total:(10+$out+1+2+3)}}'
}

# gmsg_error <date> <text> — one error message
gmsg_error() {
  jq -cn --arg ts "${1}T12:00:00.000Z" --arg t "$2" \
    '{id:"e",timestamp:$ts,type:"error",content:$t}'
}
