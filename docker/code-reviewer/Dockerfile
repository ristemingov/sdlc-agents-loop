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

USER node
WORKDIR /workspace
ENTRYPOINT ["/entrypoint.sh"]
