# weekly-summary

`bin/weekly-digest` extracts a week of assistant session history as structured
facts. `skill/weekly-summary/SKILL.md` tells an agent how to turn those facts
into a written weekly report.

It reads three histories:

- **opencode** — the sqlite database at `~/.local/share/opencode/opencode.db`
- **claude-code** — the JSONL transcripts under `~/.claude/projects/`
- **gemini-cli** — the JSON session files under `~/.gemini/tmp/`

## Running it

```bash
bin/weekly-digest --weeks-ago 1
```

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
