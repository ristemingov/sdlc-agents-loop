FROM node:20-slim

RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*

RUN npm install -g @openai/codex

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /project

ENTRYPOINT ["/entrypoint.sh"]
