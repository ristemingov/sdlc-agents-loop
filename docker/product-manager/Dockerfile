FROM node:20-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        git \
        curl \
        bash \
        jq \
        findutils \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g @anthropic-ai/claude-code

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# node:20-slim ships a non-root "node" user — required because
# claude --dangerously-skip-permissions is blocked for root
USER node
WORKDIR /workspace
ENTRYPOINT ["/entrypoint.sh"]
