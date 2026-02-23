codex -a never -s workspace-write exec "$(cat plan/instructions/pm_agent.md)"

claude --dangerously-skip-permissions -p "$(cat plan/instructions/dev_agent.md)"
