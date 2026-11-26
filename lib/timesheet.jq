# Time arithmetic for bin/timesheet. Every figure on a timesheet comes from
# here; the Claude labelling step only names categories and writes
# descriptions.
#
# Times are local seconds-of-day. An interval is [start, end] in seconds.

def secs_of_day: split(":") | map(tonumber) | .[0] * 3600 + .[1] * 60 + .[2];

def hmm: (. / 60 | floor) as $h | (. % 60) as $m
  | "\($h):\(if $m < 10 then "0" else "" end)\($m)";

# h:mm zero-padded to hh:mm, for clock times rather than durations.
def clock: hmm | if length < 5 then "0" + . else . end;

def lpad($n): tostring | if length >= $n then . else (" " * ($n - length)) + . end;
def rpad($n): tostring | if length >= $n then . else . + (" " * ($n - length)) end;

# The digest as raw text -> [{tool,id,title,repo,branch,body,times:[secs]}].
# Only sessions with at least one timestamp are kept: a session block with
# none has no in-window activity to count.
def parse_digest:
  # split rather than index-and-slice: jq 1.6 returns byte offsets from index
  # but slices strings by code point, so any multibyte character in a session
  # body would shift the slice and silently drop timestamps.
  (split("\n## timestamps\n")) as $p
  | ($p[0] | split("\n## sessions\n")) as $q
  | (if ($p | length) != 2 or ($q | length) != 2
     then error("digest output has no sessions or timestamps section") else . end)
  | ($p[1] | split("\n") | map(select(test("\t")) | split("\t"))
     | map({tool: .[0], id: .[1], t: (.[2] | secs_of_day)})) as $stamps
  | [$q[1] | split("\n### ")[1:][]
     | split("\n") as $ls
     | ($ls[2:] | .[:(index([""]) // length)] | map(capture("^(?<k>tool|id|repo|branch): (?<v>.*)$")? | {(.k): .v}) | add // {}) as $f
     | {tool: $f.tool, id: $f.id, title: $ls[0], repo: ($f.repo // "(unknown)"),
        branch: ($f.branch // ""), body: ("### " + ($ls | join("\n")))}]
  | map(. as $sess
        | .times = [$stamps[] | select(.tool == $sess.tool and .id == $sess.id) | .t]
        | select(.times | length > 0));

def union:
  sort_by(.[0])
  | reduce .[] as $b ([];
      if length > 0 and $b[0] <= .[-1][1] then .[-1][1] = ([.[-1][1], $b[1]] | max)
      else . + [$b] end);

# Timestamps -> blocks: a gap over $gap starts a new block, and each block runs
# $tail past its last timestamp, but never past $cap (midnight, or the moment
# of the run when the date is today).
def blocks($gap; $tail; $cap):
  sort
  | reduce .[] as $t ([];
      if length > 0 and ($t - .[-1][1]) <= $gap then .[-1][1] = $t
      else . + [[$t, $t]] end)
  | map([.[0], ([([.[1] + $tail, $cap] | min), .[0]] | max)])
  # A tail longer than the gap can reach into the next block.
  | union;

def clip($lo; $hi):
  map([([.[0], $lo] | max), ([.[1], $hi] | min)]) | map(select(.[1] > .[0]));

def total: map(.[1] - .[0]) | add // 0;

def minutes: . / 60 | floor;

def round_up30: ((. + 29) / 30 | floor) * 30;

def basename: sub(".*/"; "");

# Labels come from a model reading transcripts and titles from the transcripts
# themselves, so either could carry terminal escape sequences; none may reach
# the terminal.
def printable: (. // "") | tostring | gsub("[\\x00-\\x1f\\x7f\\x{80}-\\x{9f}]"; " ");

# $labels: {<id>: {category, client, description}}.
# $opts: {gap, tail, cap, hours: [lo, hi], day} -- gap/tail/cap/hours in
# seconds, day in minutes.
def sheet($sessions; $labels; $opts):
  [$sessions[]
   | . as $s
   | $labels[$s.id] as $l
   | ($s.times | blocks($opts.gap; $opts.tail; $opts.cap)) as $b
   | {id, repo: (.repo | printable), blocks: $b,
      start: $b[0][0], end: ($b | map(.[1]) | max),
      raw: ($b | total | minutes),
      category: $l.category,
      key: (if $l.category == "client" then $l.client
            elif $l.key then $l.key
            else $l.category end | printable),
      description: ($l.description | printable)}] as $rows
  | ($rows | map(select(.category != "personal"))) as $work
  | {sessions: ($rows | sort_by(.start) | map(del(.blocks))),
     lines: ($work | group_by(.key)
       | map((map(.blocks[]) | union) as $u
             | {key: .[0].key, category: .[0].category,
                raw: ($u | total | minutes),
                outside_raw: (($u | total) - ($u | clip($opts.hours[0]; $opts.hours[1]) | total)
                              | minutes)}
             | .rounded = (.raw | round_up30))
       | sort_by([(.category == "internal"), -.raw, .key])),
     day_raw: ($work | map(.blocks[]) | union | total | minutes),
     personal_raw: ($rows | map(select(.category == "personal") | .blocks[])
                    | union | total | minutes)}
  | .rounded_sum = (.lines | map(.rounded) | add // 0)
  # A session can sit in two lines only through overlapping time, e.g. a
  # resumed transcript labelled differently from its twin; that time is then
  # in the rounded sum twice, so it is shown rather than left silent.
  | .overlap = ([0, (.lines | map(.raw) | add // 0) - .day_raw] | max)
  | .not_seen = ([0, $opts.day - .day_raw] | max);

def render($date; $by_repo; $opts):
  ($opts.hours | map(. / 60 | clock) | join("-")) as $hours_label
  | ("\($date)T12:00:00Z" | fromdateiso8601 | strftime("%A")) as $dayname
  | ([22, (.lines | map(.key | length + 2) | max // 0)] | max) as $w
  | [ "timesheet for \($date) (\($dayname))" ]
  + (if $by_repo then ["grouped by repo (--no-label): no client split"] else [] end)
  + (if $opts.defaults
     then ["working hours \($hours_label), \($opts.day | hmm) day (defaults; set them in \($opts.config | printable))"]
     else [] end)
  + [ "", ("" | rpad($w)) + ("raw" | lpad(6)) + ("rounded" | lpad(10)) ]
  + [ .lines[]
      | (.key | rpad($w)) + (.raw | hmm | lpad(6)) + (.rounded | hmm | lpad(10)),
        (if .outside_raw > 0
         then ("  outside \($hours_label)" | rpad($w)) + (.outside_raw | hmm | lpad(6))
         else empty end) ]
  + [ ("day total" | rpad($w)) + (.day_raw | hmm | lpad(6)) + (.rounded_sum | hmm | lpad(10))
        + "  (rounded = sum of lines)" ]
  + (if .overlap > 0
     then [("  in more than one line" | rpad($w)) + (.overlap | hmm | lpad(6))]
     else [] end)
  + [
      ("contracted day" | rpad($w)) + ($opts.day | hmm | lpad(6)),
      ("not seen" | rpad($w)) + (.not_seen | hmm | lpad(6)) + "  (meetings, Slack, reading...)" ]
  + (if .personal_raw > 0
     then [("personal (not counted)" | rpad($w)) + (.personal_raw | hmm | lpad(6))]
     else [] end)
  + (if (.sessions | length) > 0 then ["", "sessions"] else [] end)
  + [ .sessions[]
      | "  \(.start / 60 | floor | clock)-\(.end / 60 | floor | clock)  "
        + (.raw | hmm | lpad(5)) + "  " + .key + "  " + .description
        + (if $by_repo then "" else "  [\(.repo | basename)]" end) ]
  | join("\n");

# Claude's raw reply -> {labels: {<id>: {...}}} or {error: "..."}. Every
# session must be labelled exactly once with a known category, so a reply that
# drops or invents one stops the run rather than producing a timesheet with a
# hole in it. A surrounding code fence is tolerated; prose is not.
def check_labels($reply; $sessions):
  ($reply | sub("^\\s*```[A-Za-z]*\\s*"; "") | sub("\\s*```\\s*$"; "")
   | try fromjson catch null) as $r
  | ($sessions | map(.id)) as $ids
  | if ($r | type) != "array" then {error: "claude's reply was not a JSON array of labels"}
    else
      ([$r[] | select(type == "object")]) as $items
      | ([$ids[] | . as $id
          | ([$items[] | select(.id == $id)]) as $mine
          | if ($mine | length) == 0 then "session \($id) has no label"
            elif ($mine | length) > 1 then "session \($id) is labelled more than once"
            elif ($mine[0].category | IN("client", "internal", "personal") | not)
              then "session \($id) has an unknown category: \($mine[0].category)"
            elif $mine[0].category == "client"
                 and (($mine[0].client | type) != "string" or ($mine[0].client | test("^\\s*$")))
              then "session \($id) is client work with no client named"
            else empty end]) as $problems
      | if ($problems | length) > 0 then {error: ($problems | join("; ") | printable)}
        else {labels: ([$items[] | select(.id as $i | $ids | index([$i]))
                        | {key: .id,
                           value: {category, client: (if .category == "client" then .client else null end),
                                   description: ((.description // "") | tostring | gsub("[\\n\\t]"; " "))}}]
                       | from_entries)}
        end
    end;
