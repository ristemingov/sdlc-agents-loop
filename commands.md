codex -a never -s workspace-write exec "$(cat instructions/pm_agent.md)"

claude --dangerously-skip-permissions -p "$(cat instructions/dev_agent.md)"
