---
name: codex-review
description: >
  Get a code review or second opinion from Codex (OpenAI's CLI) on a diff, bug,
  design or plan, with follow-ups in the same Codex session. Use when the user
  mentions codex or wants a cross-check, or before finishing a complex task.
---

# Codex review / second opinion

## Command

One template for every call. All flags go **before** the optional subcommand:

```bash
out=$(mktemp /tmp/codex_out.XXXX.md); log=${out%.md}.log
timeout -k 10s 600 codex exec -s read-only --skip-git-repo-check -C <project_dir> -c model_reasoning_effort="xhigh" \
  -o "$out" [resume <id> | fork <id> | review --uncommitted] "<prompt>" </dev/null >"$log" 2>&1 \
  && cat "$out" || tail -30 "$log"; grep -m1 'session id:' "$log"
```

- `-s read-only` — enforced (a write fails with `Read-only file system`); "do
  not modify" in the prompt is only advisory. Codex reads the whole filesystem
  with ordinary permissions: even as root, a file owned by another account with
  no read access for others (e.g. a mode-660 `.env`) stays unreadable, so give
  it the facts it needs. `--yolo` instead only when Codex must write (fixes,
  build): it then has full root privileges. Middle ground: `-s workspace-write`.
- `-C <dir>` — root of the project being reviewed.
- `model_reasoning_effort="xhigh"` — always, for every kind of call.
- `-o` — final answer only; the log holds the full transcript, read it only on failure.
- `</dev/null` — Codex appends piped stdin to the prompt and hangs on an idle
  pipe. Long prompt: `-` instead of `"<prompt>"`, and a `<<'EOF'` heredoc instead of `</dev/null`.
- A run takes 2-6 minutes. `codex --search exec ...` for web access.

## Background runs

When a run may exceed the 600 s foreground cap, or to keep working meanwhile
(e.g. an audit in parallel), launch it with `run_in_background`. Use fixed
paths, which the wait command needs, and an exit marker: `-o` is not written
when Codex fails.

```bash
# run_in_background: true
out=/tmp/codex_<topic>.md; log=/tmp/codex_<topic>.log; rm -f "$out" "$log"
timeout -k 10s 1500 codex exec <same flags> -o "$out" [subcommand] "<prompt>" </dev/null >"$log" 2>&1; echo "__codex_exit=$?" >>"$log"
# later, foreground (timeout 600000; repeat if it times out), before replying:
until grep -q '^__codex_exit=' "$log"; do sleep 5; done; tail -1 "$log"; cat "$out"; grep -m1 'session id:' "$log"
```

## Sessions

- No subcommand: new session. The trailing `grep` prints its id.
- `resume <id>`: follow-up on the same project and topic (fix applied →
  re-check, counter-argument, clarification). Codex keeps its reading of the
  code and its earlier findings. Works on `review` sessions too.
- `fork <id>`: new session with the same history, for a side question that
  should not pollute the main thread.
- New session when the topic or project changes, or when the session has grown
  long (its whole history stays in context).
- Resume restores the history only: without the template flags it falls back
  to the config's sandbox and the shell cwd.
- Always the explicit id, never `--last`: another channel or agent may have run
  Codex since.

## Diff review

`review --uncommitted` | `--base <branch>` | `--commit <sha>`. Custom
instructions cannot be combined with `--uncommitted`: pipe them via `-` or use
a plain prompt instead. `--uncommitted` covers untracked files; a plain prompt
on `git diff` does not, so name new files in it.

## Prompt content

- Goal, absolute file paths (Codex opens them itself), and what to check.
- Say "report only, do not modify any file" even under `-s read-only`: it stops
  Codex from planning edits it cannot make.
- Scope the reading. "Review the uncommitted diff" is cheap; asking it to trace
  every call site or validate parsers "against real output" sends it through
  the whole project for many minutes.
- Ask for findings as `file:line` + severity, no restatement of the code.
- For an opinion: list the options considered and ask for a recommendation
  with reasons. To confront views, get Codex's independent opinion first, then
  `resume` with your counterpoints and ask for agree/disagree per point.

## Reporting back

Summarize the findings, never paste the raw transcript. Codex can be wrong or
off-scope: check each point against the code and tell the user which ones you
accept or reject, and why.
