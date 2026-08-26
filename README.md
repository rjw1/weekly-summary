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
