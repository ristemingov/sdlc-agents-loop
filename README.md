# SDLC Agents Loop

A containerized SDLC pipeline where Claude Code agents autonomously handle feature requests from intake through testing. An orchestrator with a configurable heartbeat manages a state machine that routes work between 6 specialized agents.

## Prerequisites

- Docker + Docker Compose
- An Anthropic API key
- Claude Code credentials at `~/.claude` (the agents reuse your local session)

## Quick Start

```bash
# 1. Copy and fill in your API key
cp .env.example .env

# 2. Initialize workspace directories and build images
make build

# 3. Start the pipeline
make start

# 4. Submit your first feature
make submit-text FEATURE="Build a hello world REST API endpoint" NAME=hello-world-api

# 5. Watch the orchestrator route it through the pipeline
make logs-orchestrator

# 6. Check overall status at any time
make status
```

## Architecture

### Agents

| Container | Role | Reads | Writes |
|---|---|---|---|
| `orchestrator` | Heartbeat state machine — no Claude | `user-input/`, `state/` | `state/`, `logs/`, `archive/` |
| `product-manager` | Turns feature requests into PRDs | `user-input/` | `plan/prds/` |
| `project-manager` | Breaks PRDs into task lists | `plan/` | `plan/tasks/` |
| `architect` | Writes architecture design docs | `plan/` | `plan/architecture/` |
| `developer` | Implements code from the plan | `plan/` (read), `review/` (read) | `code/` |
| `code-reviewer` | Reviews code against the plan | `plan/` (read), `code/` (read) | `review/` |
| `tester` | Runs API tests and writes reports | `plan/`, `code/`, `review/` (read) | `reports/` |

### State Machine

```
WAITING_INPUT  ──(file in user-input/)──► PRODUCT_PLANNING  ──► PROJECT_PLANNING
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

Timeout (>30 min in any phase) → ERROR  (manual reset required)
```

State is stored as plain-text files under `workspace/state/`:

| File | Purpose |
|---|---|
| `current-state` | Active phase (one of the strings above) |
| `current-feature` | Basename of the feature file being processed |
| `phase-start-time` | Unix timestamp of phase start (for timeout detection) |
| `trigger-{agent}` | Written by the orchestrator to activate an agent |
| `done-{agent}` | Written by an agent on completion |
| `review-result` | `APPROVED` or `NEEDS_REVISION` |
| `test-result` | `PASS` or `FAIL` |
| `error-message` | Set when state is `ERROR` |

## Directory Structure

```
.
├── agents/                     # Agent system-prompt .md files (mounted read-only)
│   ├── product/
│   ├── project-management/
│   ├── engineering/
│   └── testing/
├── docker/                     # Per-agent Dockerfile + entrypoint.sh
│   ├── orchestrator/           # debian:bookworm-slim — bash only, no Claude
│   ├── product-manager/        # node:20-slim + claude-code
│   ├── project-manager/
│   ├── architect/
│   ├── developer/
│   ├── code-reviewer/
│   └── tester/
├── workspace/                  # Runtime data (gitignored, bind-mounted)
│   ├── user-input/             # Drop feature requests here (.md / .txt)
│   ├── plan/
│   │   ├── prds/
│   │   ├── tasks/
│   │   └── architecture/
│   ├── code/
│   ├── review/
│   ├── reports/
│   ├── archive/                # Completed feature artifacts
│   ├── state/                  # Orchestrator state files
│   └── logs/                   # Per-agent logs + orchestrator.log
├── docker-compose.yml
├── Makefile
└── .env.example
```

## Configuration

Copy `.env.example` to `.env` and set:

```env
ANTHROPIC_API_KEY=sk-ant-...
CLAUDE_MODEL=claude-sonnet-4-6       # optional, this is the default
HEARTBEAT_INTERVAL=60                # orchestrator tick in seconds (default 60)
AGENT_TIMEOUT=1800                   # seconds before a stuck phase → ERROR (default 1800)
```

## Make Commands

### Setup & Lifecycle

| Command | Description |
|---|---|
| `make init` | Create workspace dirs and initialize pipeline state |
| `make build` | `init` + `docker compose build` |
| `make start` | `init` + `docker compose up -d` |
| `make stop` | `docker compose down` |
| `make restart` | `docker compose restart` |
| `make ps` | Show container status |

### Submitting Features

| Command | Description |
|---|---|
| `make submit-feature FILE=path/to/feature.md` | Copy a feature file into `user-input/` |
| `make submit-text FEATURE="..." NAME=slug` | Write an inline feature request |

### Monitoring

| Command | Description |
|---|---|
| `make status` | Current state, pending trigger/done files, container status |
| `make logs` | Tail all container logs |
| `make logs-orchestrator` | Tail the orchestrator log file |
| `make logs-agent AGENT=developer` | Tail a specific agent log |
| `make plan-view` | Print the latest PRD and task list |
| `make review-view` | Print the latest code review |
| `make report-view` | Print the latest test report |

### Recovery & Cleanup

| Command | Description |
|---|---|
| `make reset-state` | Clear state files and return to `WAITING_INPUT` |
| `make clean` | Stop services and remove local images |
| `make clean-workspace` | Delete all workspace runtime content (destructive, asks for confirmation) |

## Monitoring a Feature End-to-End

After submitting a feature, artifacts appear in this order:

1. `workspace/plan/prds/prd-{slug}.md` — Product Manager's PRD
2. `workspace/plan/tasks/tasks-{slug}.md` — Project Manager's task list
3. `workspace/plan/architecture/architecture-{slug}.md` — Architect's design doc
4. `workspace/code/` — Developer's implementation
5. `workspace/review/review-{slug}.md` — Code Reviewer's feedback
6. `workspace/reports/test-report-{slug}-{ts}.md` — Tester's report
7. `workspace/archive/{timestamp}-{slug}/` — All artifacts archived on success

## Troubleshooting

**Pipeline stuck / `make status` shows `ERROR`**

Check the error message and then reset:

```bash
cat workspace/state/error-message
make reset-state
```

**Agent not running after trigger file appears**

The agent polls every 30 seconds. Check its log:

```bash
make logs-agent AGENT=developer
```

**Claude credentials issues**

The agents bind-mount `~/.claude` and `~/.claude.json` from your host. Make sure you are logged in on the host (`claude` CLI) before starting the pipeline.

## Agent System Prompts

Each agent loads its system prompt from `/agents/` at runtime. To update an agent's behavior, edit the corresponding `.md` file under `agents/` and restart that container:

```bash
docker compose restart developer
```
