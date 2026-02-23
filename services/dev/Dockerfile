FROM node:20-slim

RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*

RUN npm install -g @anthropic-ai/claude-code

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /project/workspace

ENTRYPOINT ["/entrypoint.sh"]
