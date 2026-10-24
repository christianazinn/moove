# Agent worker image (see docs/deploy.md). Build from agents/: docker build -t moove-agents .
# Keeps dev deps on purpose: the worker runs TypeScript through tsx (a devDependency), so there
# is no compile step that could drift from `npm start`.
FROM node:22-slim
WORKDIR /app
ENV NODE_ENV=production \
    UPLOAD_PORT=8787 \
    UPLOAD_DIR=/app/uploads
COPY package.json package-lock.json ./
RUN npm ci --include=dev && npm cache clean --force
COPY . .
# Mount a persistent volume here: photos, USDZ scans and simulated listing pages live in it.
RUN mkdir -p /app/uploads
EXPOSE 8787
# Runs as root so a freshly mounted (root-owned) platform volume is writable.
# node directly (not npm start) so SIGTERM from the platform reaches the worker (src/index.ts exits on it).
CMD ["node", "--import", "tsx", "src/index.ts"]
