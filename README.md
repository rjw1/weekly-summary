# weekly-summary

`bin/weekly-digest` extracts a week of assistant session history as structured
facts. `skill/weekly-summary/SKILL.md` tells an agent how to turn those facts
into a written weekly report.

It reads three histories:

- **opencode** — the sqlite database at `~/.local/share/opencode/opencode.db`
- **claude-code** — the JSONL transcripts under `~/.claude/projects/`
- **gemini-cli** — the JSON session files under `~/.gemini/tmp/`

## Running it

`bin/weekly-digest` prints the facts and nothing else:

```bash
bin/weekly-digest --weeks-ago 1
```

`bin/weekly-report` writes the report itself, by running the skill headlessly
through the Claude Code CLI. Output goes to `~/weekly-summaries/`:

```bash
bin/weekly-report                    # last complete Monday-to-Sunday week
bin/weekly-report --weeks-ago 3
bin/weekly-report --week 2026-08-10  # the week containing that day
```

Run by hand it asks before overwriting an existing report, since one may have
notes added after it was generated; `--force` skips the question.

Symlink it onto `PATH` (`ln -s "$PWD/bin/weekly-report" ~/bin/weekly-report`) to
run it as a bare command. Reading a whole week of history costs real money on a
busy week; the digest alone costs nothing.

### Running it daily

`--auto` makes the script safe to call from a daily cron and still produce one
report a week:

```bash
weekly-report --auto
```

One rule covers every day, with no Monday special case: it writes when the
report is missing, or was last written before this week's Monday. Later in the
week that means the Monday run did not happen; on the Monday itself it means
the report has not been written today, so calling it twice in a day writes
once. A stale mid-week draft written before the week closed is replaced, while
a report edited by hand during the week keeps a current timestamp and is left
alone. When it decides there is nothing to do it exits silently unless run from
a terminal, so a daily job does not mail a line every day of the week it
correctly did nothing.

`--auto` refuses `--week` and `--weeks-ago`: "is a report due today" only means
anything for the week that has just ended.

## Cost

opencode records what a session cost; Claude Code and Gemini CLI do not. The
Claude Code figures are therefore estimated by pricing the tokens its
transcripts record against [models.dev](https://models.dev) published rates,
cached under `~/.cache/weekly-digest/` and refreshed when older than 30 days.
The estimate applies list API prices, so it is not what a subscription plan
charges, and the digest labels it that way wherever it appears. `--no-pricing`
skips it; `--pricing FILE` prices from a local models.dev `api.json`. With no
network and no cache, the cost is reported as unavailable rather than zero.

## Reports

Reports are written to `~/weekly-summaries/`, which is deliberately **not** a
git repository: a summary of a person's own week names clients, colleagues and
account identifiers by nature, and redacting it would make it far less useful.
Do not add a `.git` there, and do not copy reports into this repo.

## Tests

```bash
npm run test:bash
```

Requires `bats` and `shellcheck` on `PATH` (`brew install bats-core shellcheck`).
