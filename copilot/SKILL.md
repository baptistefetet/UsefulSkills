---
name: copilot
description: >
  Delegate a task to GitHub Copilot CLI. Use this skill when the user mentions
  copilot in their message — e.g. "demande à copilot", "ask copilot",
  "copilot's opinion", "what does copilot think", etc. Also triggered via
  /copilot <prompt>.
---

# Copilot Skill

Delegate a task to GitHub Copilot CLI installed on this system.

## Trigger

Activate this skill whenever the user's message references copilot as a delegate
(e.g. "demande à copilot", "ask copilot what it thinks", "copilot's take on
this"). Also activated via the explicit `/copilot` command.

## Instructions

### 1. Build the prompt

Do **not** forward the user's raw message. Instead, craft a clear, self-contained
prompt for copilot that includes all necessary context:

- **Project**: which project/repo is being worked on, its purpose, relevant tech stack.
- **Current task**: what the user is currently doing or discussing.
- **Specific question**: what copilot should answer or review.
- **Relevant code snippets or file paths** if they help copilot understand the situation.

The prompt must be understandable by someone with zero prior context about the
conversation.

### 2. Extract optional model

If the user explicitly mentions a model name (e.g. "avec gpt-5.4", "using
claude-sonnet-4-5-20250514", "with o3"), extract it. Otherwise, do not pass
`--model`.

### 3. Run the command

Always use `--silent` (`-s`) to suppress session stats from the output.

```bash
# With model:
copilot -s --yolo --model <model> -p "<prompt>"

# Without model:
copilot -s --yolo -p "<prompt>"
```

- Shell-escape the prompt properly.

### 4. Present the result

Always show **both**:

1. **The exact prompt** that was passed to copilot (in a quote block or code
   block), so the user can verify the context was adequate.
2. **Copilot's response**.

If copilot returns an error, show it as-is.
Do not interpret or modify copilot's response unless the user asks.
