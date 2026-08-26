---
name: weekly-summary
description: Use when asked to summarise what was done last week, produce a weekly review, or write up a past week's work from opencode or Claude Code session history. Covers running the digest helper, resolving which week is meant, and what the written report must contain.
---

# Weekly summary

`bin/weekly-digest` extracts a week of session history as structured facts. This
skill turns those facts into a written report.

It reads **two** histories and reports both by default:

- **opencode** — the sqlite database at `~/.local/share/opencode/opencode.db`
- **claude-code** — the JSONL transcripts under `~/.claude/projects/`

**Never query either history directly.** The digest owns the window arithmetic,
the activity-based session selection, the cost attribution and the token
accounting. Hand-rolled queries re-derive those rules and get them wrong. Two
traps in particular:

- Filtering opencode sessions on creation date drops work carried over from an
  earlier week.
- Claude Code writes one record per *content block* of an assistant message,
  each repeating the same `message.id` and its usage. Summing per record
  inflates token counts severalfold; the digest deduplicates by message id.

## Running it

```bash
~/git/rjw1/weekly-summary/bin/weekly-digest --weeks-ago 1
```

Add `--source opencode` or `--source claude` to restrict the report to one
tool. The default is `both`, which is what a weekly review normally wants —
work routinely moves between the two tools inside a single week, and one
workstream can have sessions in each.

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
  per-repo and (for claude-code) per-model breakdowns.
- `## pull requests` — see below. This section is tool-agnostic.
- `## sessions` — one block per session, grouped by tool, opencode first, each
  group in chronological order. Every block names its `tool:`, so read that
  rather than inferring the tool from position.

`note: CARRIED-OVER from <date>` means the session began in an earlier week.
Say the work continued rather than presenting it as newly started.

`note: LIKELY-TRIVIAL` is advisory and fitted to a small sample. Judge from the
prompts, not the flag. The opencode side fits it on cost and the claude-code
side on output tokens, so the two are not directly comparable.

`USER:` is a prompt typed at the terminal. `USER[<source>]:` is one that
arrived another way — `sdk` for a `claude -p` headless run, and similarly for
other surfaces. Say so when it matters: a week's `sdk` prompts are usually
scripted or throwaway rather than deliberate work.

### What the two tools record differently

**Claude Code records no cost.** Nothing persists spend — `/cost` computes it
live from token usage — so its stats block reads
`cost: (unavailable: Claude Code transcripts record no cost)` and its
breakdowns are in output tokens. Copy that reason into the report rather than
printing a zero, computing an estimate, or quietly implying the week was free.
The opencode figure is a real cost and must not be presented as a total across
both tools.

**Subagents differ in kind.** An opencode subagent is a child session with its
own cost, reported as `subagents: N (cost X)`. A Claude Code subagent is a
sidechain transcript, reported as
`subagents: N (output tokens X) types: <agent types>`. The types are worth a
mention when a session leaned heavily on one.

A Claude Code session block also carries `branch:` and `models:`. Use `models:`
when a week's work was deliberately split across models; do not read a model
name as a cost signal, since none is recorded.

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
5. Stats — keep the two tools' figures distinct, and carry across the reason
   Claude Code reports no cost
6. Per-session appendix

### Narrative rules

- Group by workstream, not by session or by tool. One theme routinely spans
  several sessions, several days, and both tools; splitting the narrative by
  tool would break a single piece of work in half. Name the tool only where it
  is part of the story.
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
