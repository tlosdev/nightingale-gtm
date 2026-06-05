# syntax=docker/dockerfile:1
#
# Nightingale UI — containerized DASHBOARD.
#
# IMPORTANT (honesty note, also in README): this image reproduces the UI and
# the agent *definitions*, NOT the agent *runtime*. The container is a Linux
# box with no Claude Code CLI, no claude.ai MCP auth, and no PowerShell, so it
# runs in "container mode": it reads the mounted Desktop output tree + secrets
# file and renders everything, but agent runs / approvals / secrets edits are
# disabled (they need the host — see scripts/start-ui.ps1 — or the Phase 3
# self-hosted GitHub runner dispatch path).
#
# Build context is ui/. The repo's .claude/agents tree is bind-mounted at
# runtime by docker-compose, not copied here.

# ---- Stage 1: build the React bundle -----------------------------------------
FROM node:20 AS build
WORKDIR /app/ui

# Install deps first (cached layer). devDependencies (vite) are needed to build,
# so do NOT set NODE_ENV=production here.
COPY package.json package-lock.json ./
RUN npm ci

# Copy the rest of the source and build web/dist. .dockerignore keeps host
# node_modules / web/dist out so they're produced fresh inside the image.
COPY . .
RUN npm run build

# ---- Stage 2: slim runtime ---------------------------------------------------
FROM node:20-slim AS runtime
ENV NODE_ENV=production
# Marks this process as containerized — the server reads NIGHTINGALE_CONTAINER
# to switch on container mode (disable host-process actions, bind 0.0.0.0).
ENV NIGHTINGALE_CONTAINER=1
ENV NIGHTINGALE_UI_PORT=8765
# os.homedir() honors $HOME on POSIX; the signals tree + secrets file are
# mounted under /data so paths.ts resolves them there.
ENV HOME=/data
WORKDIR /app/ui

# Bring over the built app + node_modules (pure-JS deps; node:20 build glibc is
# compatible with node:20-slim glibc).
COPY --from=build /app/ui /app/ui

EXPOSE 8765

# `npm start` == `tsx server/index.ts`. tsx is a runtime dependency.
CMD ["npm", "start"]
