.PHONY: help init build start stop restart logs logs-orchestrator logs-agent \
        status submit-feature submit-text reset-state clean clean-workspace \
        ps plan-view review-view report-view

COMPOSE = docker compose

WORKSPACE_DIRS = \
    workspace/user-input \
    workspace/plan/prds \
    workspace/plan/tasks \
    workspace/plan/architecture \
    workspace/code \
    workspace/review \
    workspace/reports \
    workspace/archive \
    workspace/state \
    workspace/logs

# ── Help ──────────────────────────────────────────────────────────────────────

help: ## Show available commands
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-22s\033[0m %s\n", $$1, $$2}'

# ── Setup ─────────────────────────────────────────────────────────────────────

init: ## Create workspace directories and initialize pipeline state
	@echo "Initializing workspace..."
	@mkdir -p $(WORKSPACE_DIRS)
	@for dir in $(WORKSPACE_DIRS); do touch $$dir/.gitkeep 2>/dev/null || true; done
	@if [ ! -f workspace/state/current-state ]; then \
		echo "WAITING_INPUT" > workspace/state/current-state; \
		echo "State initialized to WAITING_INPUT"; \
	else \
		echo "State already initialized: $$(cat workspace/state/current-state)"; \
	fi
	@echo "Workspace ready."

build: init ## Build all Docker images
	$(COMPOSE) build

# ── Lifecycle ─────────────────────────────────────────────────────────────────

start: init ## Start all pipeline services
	$(COMPOSE) up -d
	@echo ""
	@echo "SDLC pipeline started."
	@echo "Submit a feature: make submit-text FEATURE=\"Add user login\" NAME=user-login"
	@echo "Watch progress:   make logs-orchestrator"
	@echo "Check status:     make status"

stop: ## Stop all services
	$(COMPOSE) down

restart: ## Restart all services
	$(COMPOSE) restart

ps: ## Show container status
	$(COMPOSE) ps

# ── Logs ──────────────────────────────────────────────────────────────────────

logs: ## Tail all container logs
	$(COMPOSE) logs -f

logs-orchestrator: ## Tail orchestrator log file
	@tail -f workspace/logs/orchestrator.log 2>/dev/null \
		|| (echo "Log not yet created — falling back to container logs" && \
		    $(COMPOSE) logs -f orchestrator)

logs-agent: ## Tail a specific agent log  (usage: make logs-agent AGENT=developer)
	@if [ -z "$(AGENT)" ]; then echo "Usage: make logs-agent AGENT=<agent-name>"; exit 1; fi
	@tail -f workspace/logs/$(AGENT).log 2>/dev/null \
		|| echo "Log not yet created: workspace/logs/$(AGENT).log"

# ── Status ────────────────────────────────────────────────────────────────────

status: ## Show current pipeline state and pending files
	@echo "━━━ Pipeline Status ━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "Current state:   $$(cat workspace/state/current-state 2>/dev/null || echo 'UNKNOWN')"
	@echo "Current feature: $$(cat workspace/state/current-feature 2>/dev/null || echo '(none)')"
	@echo ""
	@echo "━━━ State Files ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "Triggers:"; ls workspace/state/trigger-* 2>/dev/null | sed 's|workspace/state/||' | sed 's/^/  /' || echo "  (none)"
	@echo "Done:    "; ls workspace/state/done-* 2>/dev/null | sed 's|workspace/state/||' | sed 's/^/  /' || echo "  (none)"
	@echo "Review result: $$(cat workspace/state/review-result 2>/dev/null || echo '(none)')"
	@echo "Test result:   $$(cat workspace/state/test-result 2>/dev/null || echo '(none)')"
	@echo ""
	@echo "━━━ Containers ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@$(COMPOSE) ps
	@echo ""
	@echo "━━━ Pending Features ━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@ls workspace/user-input/ 2>/dev/null | grep -v '.gitkeep' | sed 's/^/  /' || echo "  (none)"

# ── Feature Submission ────────────────────────────────────────────────────────

submit-feature: ## Copy a feature file into user-input/  (usage: make submit-feature FILE=path/to/feature.md)
	@if [ -z "$(FILE)" ]; then \
		echo "Usage: make submit-feature FILE=path/to/feature.md"; exit 1; \
	fi
	@cp "$(FILE)" workspace/user-input/
	@echo "Feature submitted: $$(basename $(FILE))"
	@echo "The orchestrator will pick it up within $${HEARTBEAT_INTERVAL:-300} seconds."

submit-text: ## Write an inline feature request  (usage: make submit-text FEATURE="Add login" NAME=add-login)
	@if [ -z "$(FEATURE)" ] || [ -z "$(NAME)" ]; then \
		echo "Usage: make submit-text FEATURE=\"description\" NAME=slug-name"; exit 1; \
	fi
	@echo "$(FEATURE)" > workspace/user-input/$(NAME).md
	@echo "Feature '$(NAME)' submitted to user-input/."
	@echo "The orchestrator will pick it up within $${HEARTBEAT_INTERVAL:-300} seconds."

# ── Recovery ─────────────────────────────────────────────────────────────────

reset-state: ## Reset pipeline to WAITING_INPUT (use if stuck in ERROR or stale state)
	@echo "WARNING: This resets the pipeline state. The current feature will be re-queued if still in user-input/."
	@echo "Press Enter to continue, Ctrl+C to cancel."
	@read _
	@rm -f workspace/state/trigger-* workspace/state/done-* workspace/state/ack-* \
	        workspace/state/phase-start-time workspace/state/review-result \
	        workspace/state/test-result workspace/state/error-message \
	        2>/dev/null || true
	@echo "WAITING_INPUT" > workspace/state/current-state
	@echo "State reset to WAITING_INPUT."

# ── Inspection ────────────────────────────────────────────────────────────────

plan-view: ## Show the latest PRD and task list
	@echo "━━━ Latest PRD ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@ls -t workspace/plan/prds/*.md 2>/dev/null | head -1 | xargs cat 2>/dev/null || echo "(none yet)"
	@echo ""
	@echo "━━━ Latest Task List ━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@ls -t workspace/plan/tasks/*.md 2>/dev/null | head -1 | xargs cat 2>/dev/null || echo "(none yet)"

review-view: ## Show the latest code review
	@echo "━━━ Latest Code Review ━━━━━━━━━━━━━━━━━━━━━━━━"
	@ls -t workspace/review/*.md 2>/dev/null | head -1 | xargs cat 2>/dev/null || echo "(none yet)"

report-view: ## Show the latest test report
	@echo "━━━ Latest Test Report ━━━━━━━━━━━━━━━━━━━━━━━━"
	@ls -t workspace/reports/*.md 2>/dev/null | head -1 | xargs cat 2>/dev/null || echo "(none yet)"

# ── Cleanup ───────────────────────────────────────────────────────────────────

clean: stop ## Stop services and remove local images
	$(COMPOSE) down --rmi local --remove-orphans

clean-workspace: ## Delete all workspace runtime content (DESTRUCTIVE — asks for confirmation)
	@echo "WARNING: This deletes all content from user-input/, plan/, code/, review/, reports/, archive/, logs/."
	@echo "Press Enter to continue, Ctrl+C to cancel."
	@read _
	@find workspace/user-input workspace/plan workspace/code workspace/review \
	      workspace/reports workspace/archive workspace/logs \
	      -not -name '.gitkeep' -not -type d -delete 2>/dev/null || true
	@rm -f workspace/state/trigger-* workspace/state/done-* workspace/state/ack-* \
	        workspace/state/phase-start-time workspace/state/review-result \
	        workspace/state/test-result workspace/state/error-message \
	        workspace/state/current-feature workspace/state/cycle-count \
	        2>/dev/null || true
	@echo "WAITING_INPUT" > workspace/state/current-state
	@echo "Workspace cleaned."
