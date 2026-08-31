---
name: weekly-summary
description: Use when asked to summarise what was done last week, produce a weekly review, or write up a past week's work from opencode, Claude Code or Gemini CLI session history. Covers running the digest helper, resolving which week is meant, and what the written report must contain.
---

# Weekly summary

`bin/weekly-digest` extracts a week of session history as structured facts. This
skill turns those facts into a written report.

It reads **three** histories and reports all of them by default:

- **opencode** — the sqlite database at `~/.local/share/opencode/opencode.db`
- **claude-code** — the JSONL transcripts under `~/.claude/projects/`
- **gemini-cli** — the JSON session files under `~/.gemini/tmp/`

**Never query any history directly.** The digest owns the window arithmetic,
the activity-based session selection, the cost attribution and the token
accounting. Hand-rolled queries re-derive those rules and get them wrong. Four
traps in particular:

- Filtering opencode sessions on creation date drops work carried over from an
  earlier week.
- Claude Code writes one record per *content block* of an assistant message,
  each repeating the same `message.id` and its usage. Summing per record
  inflates token counts severalfold; the digest deduplicates by message id.
- Gemini names its older project directories with a hash of the project path
  and records the path nowhere inside the session file. The digest resolves
  those; a hand-rolled query reports them as unattributed.
- Gemini also leaves copies of a session in several project directories — it
  copied rather than moved them when it migrated from hash-named to
  name-named directories, and one session can appear in as many as nine
  directories. On the real store, 255 session files hold only 188 distinct
  sessions. The digest deduplicates by `sessionId`, keeping the fullest copy;
  a hand-rolled query that counted files would overstate the week's work by
  36%, and would inflate token totals by the same proportion.

## Running it

```bash
~/git/rjw1/weekly-summary/bin/weekly-digest --weeks-ago 1
```

Claude Code pricing comes from a models.dev table cached under
`~/.cache/weekly-digest/`, refreshed when it is more than 30 days old. A run
with no network and no cache still works: it reports the Claude Code cost as
unavailable with the reason. `--no-pricing` skips the estimate deliberately,
and `--pricing FILE` prices from a local models.dev `api.json`.

Add `--source opencode`, `--source claude` or `--source gemini` to restrict the
report to one tool. The default is `all` — `both` is still accepted as an alias
for it — and that is what a weekly review normally wants, since work routinely
moves between tools inside a single week and one workstream can have sessions
in each.

Map the request onto flags rather than doing date arithmetic yourself:

| Request | Invocation |
|---|---|
| "last week" | `--weeks-ago 1` (the default) |
| "the week before last" | `--weeks-ago 2` |
| "three weeks ago" | `--weeks-ago 3` |
| "the week of 10 August" | `--week 2026-08-10` — any day inside the week works |
| "week commencing 13 July" | `--week 2026-07-13` |
| an arbitrary span | `--from 2026-08-03 --to 2026-08-14` |
| "this week so far" | `--from <this monday> --to <today>` |

If the phrasing is ambiguous, ask. "Last week" said on a Monday is the obvious
trap: the speaker usually means the week that just finished (yesterday, if
today is Monday, is Sunday of that week), not the seven days immediately
preceding today, and not the week containing today. When in doubt, state which
Mon–Sun span you're about to use and let the user correct it before running
the digest.

## Reading the digest

- `## window` — state the resolved dates in the report header.
- `## stats` — one `###` block per tool: in-window cost and tokens, plus
  a per-repo breakdown, and (for claude-code and gemini-cli) a per-model one.
  opencode's cost is metered; claude-code's is estimated from models.dev
  pricing; gemini-cli's is unavailable. See below before quoting any of them.
- `## pull requests` — see below. This section is tool-agnostic.
- `## sessions` — one block per session, grouped by tool, opencode first, then
  claude-code, then gemini-cli, each group in chronological order. Every block
  names its `tool:`, so read that rather than inferring the tool from
  position.

`note: CARRIED-OVER from <date>` means the session began in an earlier week.
Say the work continued rather than presenting it as newly started.

`note: LIKELY-TRIVIAL` is advisory and fitted to a small sample. Judge from the
prompts, not the flag. The opencode side fits it on cost; claude-code and
gemini-cli both fit it on output tokens, on the same threshold, since neither
records cost. Opencode's basis is not directly comparable with the other two.

`USER:` is a prompt typed at the terminal. `USER[<source>]:` is one that
arrived another way — `sdk` for a `claude -p` headless run, and similarly for
other surfaces. Say so when it matters: a week's `sdk` prompts are usually
scripted or throwaway rather than deliberate work.

A Gemini prompt that referenced files with `@` has the file contents inlined
beneath it. The digest cuts them off, so a `USER:` line is what was typed, not
the file that came with it.

### What the tools record differently

**Only opencode records a real cost.** Claude Code computes spend live from
token usage and persists none; Gemini CLI records tokens and no cost either.
The digest fills the Claude Code gap by pricing its recorded tokens against
models.dev's published rates, so its stats block reads
`cost: (estimated N from models.dev list API pricing, not a billed amount)`
with a `pricing:` line naming the table and its date. Gemini CLI is still
unpriced and reads `cost: (unavailable: …)`.

**An estimate is never a charge, and the report must never let it read as one.**
Two things make the figure notional rather than billed: it applies list API
prices, which is not what a subscription plan charges, and it prices only the
tokens the transcripts recorded. Always attach the word *estimated* and the
models.dev attribution to the Claude Code figure. The opencode figure is real
metered spend. A combined week total is allowed, but only if it says plainly
that it adds metered opencode spend to an estimate — never present the sum as
one measured number.

A `pricing-note:` line names models the table had no rate for. Their tokens are
outside the estimate, so say so: the total is a floor, not a complete figure.

If the Claude Code cost reads `(unavailable: … no estimate: …)`, the rate table
could not be had — offline, `--no-pricing`, or a bad `--pricing` file. Copy the
reason into the report rather than printing a zero, substituting your own
arithmetic, or quietly implying the week was free.

Cost figures appear in three places: the stats total, a cost column on the
per-model and per-repo breakdowns (both then sorted by cost rather than output
tokens), and each claude-code session block's
`cost: (estimated N, session and subagents)`. That last one covers the session
and its subagents together, matching how an opencode root session totals its
children, so the two tools' per-session figures can be ranked side by side —
with opencode's real and Claude Code's estimated.

**Never add the claude-code session costs up.** Resuming a session writes a new
transcript that repeats the earlier records, so one message can appear in
several session files — 264 of them did in a single real week, and the session
figures for that week summed about 4% above the true total. The `## stats`
figure deduplicates by message id across every file at once and is the only
correct week total; the per-session figures are for ranking sessions against
each other, nothing more. The same caveat applies to the per-session token
counts, which have always overlapped the same way.

**The three tools count cache tokens differently, so the `input=` figures are
not the same measurement.** gemini-cli's `cached` is contained within its
`input`: `input` is the *total* input including cache hits, and the line adds up
as `total = input + output + thoughts + tool`. claude-code's `cache_read` and
opencode's `cache.read` are the other way round — additive, disjoint from an
`input` that counts uncached input only. So never add gemini's `cached` to its
`input`, and never set gemini's `input` beside another tool's `input` as though
they measured the same thing: a real week reads `input=521311809
cached=456772659` for gemini against 64,539,150 tokens of fresh input, so
treating the column like claude-code's overstates it eightfold and summing the
two doubles it. If a report quotes gemini's `input`, say it is total input
including cache reads.

**Subagents differ in kind.** An opencode subagent is a child session with its
own cost, reported as `subagents: N (cost X)`. A Claude Code subagent is a
sidechain transcript, reported as
`subagents: N (output tokens X) types: <agent types>`. The types are worth a
mention when a session leaned heavily on one.

**Gemini CLI has no subagents.** Its session blocks carry no `subagents:` line
at all, which means absence, not zero. They do carry `errors: N`, counting
in-window error messages — a run that hit quota or tool failures is worth a
mention in the narrative.

`branch:` is the one claude-specific line: a Claude Code session block carries
it, a gemini-cli block does not. Both carry `models:`. Use `models:` when a
week's work was deliberately split across models; do not read a model name as a
cost signal, since none is recorded.

## Checking the pull request section

If it reads `(unavailable: …)`, **say so in the report.** Do not omit the pull
request section, and never imply there were no pull requests — the digest
distinguishes `(unavailable: …)` from `none found` precisely so this cannot be
fudged. Copy the reason given into the report rather than paraphrasing it away.

Discovery finds only pull requests authored by the user. If the transcripts show
work on one raised by a bot or a colleague — a dependency bump whose build was
fixed, someone else's branch debugged locally — mention it in the narrative and
leave it out of the table. The table is for pull requests the digest actually
found; the narrative can say more than the table proves.

## Writing the report

Write to `~/weekly-summaries/week-of-<monday>.md` and print it as well. Create
the directory if needed. If the file exists, say that you are overwriting it —
a previous report may carry hand-written notes.

Required sections:

1. Header — resolved window and headline figures
2. Themed narrative of the work
3. Pull request table with current state
4. Outstanding / needs attention
5. Stats — keep the three tools' figures distinct. Label the Claude Code cost
   an estimate and name models.dev as its basis wherever it appears, and carry
   across the reason Gemini CLI reports no cost
6. Per-session appendix

### Narrative rules

- Group by workstream, not by session or by tool. One theme routinely spans
  several sessions, several days, and more than one tool; splitting the
  narrative by tool would break a single piece of work in half. Name the tool
  only where it is part of the story.
- Say what was done, why, and how it turned out. Include course corrections and
  dead ends where they are informative — mid-session reversals are often the most
  interesting content of a week.
- Assert only what the digest contains. Never invent pull request numbers,
  commit hashes or file paths.
- Distinguish work that shipped from work left uncommitted or unpushed. The
  closing assistant message usually says which.

### Outstanding section

Pull together, from the digest: pull requests still open and what they are
waiting on, work described as committed but not pushed, and follow-ups deferred
in the transcripts.

## Data handling

The report lives outside any git repository, at `~/weekly-summaries/`, so real
names, client references and account identifiers are fine in it — this is
deliberate, because a summary of a person's own week names clients, colleagues
and account identifiers by nature, and a redacted version would be far less
useful to them. Credentials never appear in it regardless of where it lives.

Do not copy the report into a working repository, and do not put it in the
spec store. It is not an artefact; it is a personal record, and moving it
anywhere that gets committed reintroduces exactly the identifiers this
location was chosen to avoid redacting.
