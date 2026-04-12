# SDLC Automation System — Docker Compose Plan

## Context

The user wants a containerized SDLC pipeline where Claude Code agents autonomously handle feature requests from intake through testing. An orchestrator with a 5-minute heartbeat manages a state machine that routes work between 6 specialized agents. Strict volume separation enforces role boundaries (PM cannot touch code; developer cannot touch user-input). Agent prompts embed the relevant `agency-agents` system prompt plus workspace-specific instructions.

---

## File Structure to Create

```
agents-sdlc-v2/
├── .gitignore
├── .env.example
├── Makefile
├── docker-compose.yml
│
├── docker/
│   ├── orchestrator/
│   │   ├── Dockerfile              # debian:bookworm-slim (bash only, no claude)
│   │   └── entrypoint.sh           # 5-min heartbeat state machine
│   ├── product-manager/
│   │   ├── Dockerfile              # node:20-slim + claude-code
│   │   └── entrypoint.sh           # polls trigger-product-manager
│   ├── project-manager/
│   │   ├── Dockerfile
│   │   └── entrypoint.sh
│   ├── architect/
│   │   ├── Dockerfile
│   │   └── entrypoint.sh
│   ├── developer/
│   │   ├── Dockerfile
│   │   └── entrypoint.sh
│   ├── code-reviewer/
│   │   ├── Dockerfile
│   │   └── entrypoint.sh
│   └── tester/
│       ├── Dockerfile
│       └── entrypoint.sh
│
├── agents/                         # Copies of agency-agents .md files
│   ├── product/product-manager.md
│   ├── project-management/project-manager-senior.md
│   ├── engineering/
│   │   ├── engineering-software-architect.md
│   │   ├── engineering-senior-developer.md
│   │   └── engineering-code-reviewer.md
│   └── testing/testing-api-tester.md
│
└── workspace/                      # Gitignored runtime data, bind-mounted
    ├── user-input/                 # Feature requests (.md/.txt) dropped here
    ├── plan/
    │   ├── prds/                   # Product Manager writes PRDs
    │   ├── tasks/                  # Project Manager writes task lists
    │   └── architecture/           # Architect writes design docs
    ├── code/                       # Developer writes all code here
    ├── review/                     # Code Reviewer writes reviews
    ├── reports/                    # Tester writes test reports
    ├── archive/                    # Completed feature artifacts
    ├── state/                      # Orchestrator state files
    └── logs/                       # Per-agent logs + orchestrator.log
```

---

## State Machine

State stored in `/workspace/state/current-state` (plain text). Additional files:

| File | Purpose |
|---|---|
| `state/current-state` | One of the phase strings below |
| `state/current-feature` | Basename of the feature file being processed |
| `state/phase-start-time` | Unix timestamp of phase start (timeout detection) |
| `state/trigger-{agent}` | Written by orchestrator to activate an agent |
| `state/done-{agent}` | Written by agent on completion |
| `state/review-result` | `APPROVED` or `NEEDS_REVISION` (written by code-reviewer) |
| `state/test-result` | `PASS` or `FAIL` (written by tester) |
| `state/error-message` | Set on ERROR state |

### Transitions

```
WAITING_INPUT   ──(file in user-input/)──► PRODUCT_PLANNING  ──► PROJECT_PLANNING
                                                                         │
                                                                         ▼
                                                                    ARCHITECTURE
                                                                         │
                                                                         ▼
TESTING ◄──── CODE_REVIEW ◄──── DEVELOPMENT ◄────────────────────────────┘
   │              │                  ▲
   │         NEEDS_REVISION ─────────┘
   │
   └──► (archive feature) ──► WAITING_INPUT

Timeout (>30min in a phase) → ERROR (requires manual reset)
```

---

## Volume Access Matrix

| Agent | user-input | plan | code | review | reports | state | logs |
|---|---|---|---|---|---|---|---|
| Orchestrator | RW | — | — | — | — | RW | RW |
| Product Manager | R | RW | — | — | — | RW | RW |
| Project Manager | — | RW | — | — | — | RW | RW |
| Architect | — | RW | — | — | — | RW | RW |
| Developer | — | R | RW | R | — | RW | RW |
| Code Reviewer | — | R | R | RW | — | RW | RW |
| Tester | — | R | R | R | RW | RW | RW |

---

## Key Implementation Details

### Orchestrator (`docker/orchestrator/entrypoint.sh`)
- `while true; do tick; sleep 300; done` loop
- `tick()` reads `current-state`, runs the matching case
- Writes `trigger-{agent}` files to activate agents
- Reads `done-{agent}` files to advance phases
- Timeout check: if `phase-start-time` > 1800s old and no done file → ERROR
- Cleans up trigger/done/ack files between phases via `reset_state_files()`
- Archives completed features to `workspace/archive/{timestamp}-{feature}/`
- Logs to `workspace/logs/orchestrator.log` with ISO8601 timestamps

### Agent Containers (`docker/{agent}/entrypoint.sh`)
- `while true; do poll; sleep 30; done` polling loop
- On trigger: build `$PROMPT` = agent system prompt (from `/agents/...md`) + task instructions
- Call `claude --dangerously-skip-permissions -p "$PROMPT"`
- Write `state/done-{agent}` after completion (guaranteed even if claude doesn't)
- Remove trigger file before running to prevent re-trigger

### Prompt Design (per agent)
Each prompt = `[agent .md system prompt]` + `[task context including specific paths]`:
- **Product Manager**: reads `user-input/{feature}`, writes `plan/prds/prd-{slug}.md`, signals done
- **Project Manager**: reads latest PRD, writes `plan/tasks/tasks-{slug}.md`, signals done
- **Architect**: reads PRD + tasks, writes `plan/architecture/architecture-{slug}.md`, signals done
- **Developer**: reads plan/ (all), writes to `code/`, creates `code/IMPLEMENTATION_NOTES.md`, signals done; re-triggered with review feedback on revision
- **Code Reviewer**: reads plan/ + code/, writes `review/review-{slug}.md` + `state/review-result`, signals done
- **Tester**: reads plan/ + code/ + review/, writes `reports/test-report-{slug}-{ts}.md` + `state/test-result`, signals done

### docker-compose.yml Structure
- Uses `x-claude-credentials` YAML anchor: `- ${HOME}/.claude:/root/.claude:ro`
- Uses `x-agent-base` anchor for shared env vars (`ANTHROPIC_API_KEY`, `CLAUDE_MODEL`)
- All workspace dirs are bind-mounted (not named volumes) so host developers can see all output
- Orchestrator: `restart: unless-stopped`, separate debian image (no claude needed)
- Agent services: `restart: unless-stopped`, node:20-slim + claude-code

### Agent Dockerfiles
- **Orchestrator**: `FROM debian:bookworm-slim` — bash + coreutils + findutils only
- **All agents**: `FROM node:20-slim` — git, curl, bash, jq, claude-code npm package
- Each agent has its own `Dockerfile` + `entrypoint.sh` in `docker/{agent}/`

### Makefile Targets
- `make init` — create workspace dirs + initialize state
- `make build` — docker compose build
- `make start` — docker compose up -d
- `make stop` / `make restart`
- `make status` — show current state, trigger/done files, container status
- `make logs` / `make logs-orchestrator` / `make logs-agent AGENT=developer`
- `make submit-feature FILE=path/to/feature.md` — copy into user-input/
- `make submit-text FEATURE="..." NAME=slug` — write inline feature request
- `make reset-state` — clear state files, return to WAITING_INPUT (with confirmation)
- `make clean-workspace` — destructive full reset (with confirmation)
- `make plan-view` / `make review-view` / `make report-view` — inspect latest outputs

---

## Files to Copy from agency-agents

Copy (not symlink, for container portability):
```bash
cp ../agency-agents/product/product-manager.md ./agents/product/
cp ../agency-agents/project-management/project-manager-senior.md ./agents/project-management/
cp ../agency-agents/engineering/engineering-software-architect.md ./agents/engineering/
cp ../agency-agents/engineering/engineering-senior-developer.md ./agents/engineering/
cp ../agency-agents/engineering/engineering-code-reviewer.md ./agents/engineering/
cp ../agency-agents/testing/testing-api-tester.md ./agents/testing/
```

These are mounted as `/agents:ro` in all agent containers.

---

## Verification

1. `make build` — all images build without errors
2. `make start` — all 7 containers running (`docker compose ps`)
3. `make submit-text FEATURE="Build a hello world REST API endpoint" NAME=hello-world-api`
4. `make status` — shows `PRODUCT_PLANNING` after ~5 min
5. `make logs-orchestrator` — shows heartbeat ticks and state transitions
6. Monitor through: PRD appears in `workspace/plan/prds/`, tasks in `workspace/plan/tasks/`, code in `workspace/code/`, review in `workspace/review/`, report in `workspace/reports/`
7. `make reset-state` — recovers from ERROR state cleanly
