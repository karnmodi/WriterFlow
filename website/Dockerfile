# Multi-stage build for the website Container App
# (infra/bicep/modules/container-app-website.bicep). Built from the repo root:
#   docker build -f website/Dockerfile -t writerflow-website .
# Mirrors services/api/Dockerfile's shape; uses Next's `output: "standalone"`
# (next.config.ts) to keep the runtime image to just the traced dependency
# subset instead of the full node_modules tree.

FROM node:24-alpine AS build
WORKDIR /workspace
COPY website/package.json website/package-lock.json ./
RUN npm ci
COPY website .
RUN npm run build

FROM node:24-alpine AS runtime
ENV NODE_ENV=production
WORKDIR /app
COPY --from=build /workspace/public ./public
COPY --from=build /workspace/.next/standalone ./
COPY --from=build /workspace/.next/static ./.next/static
USER node
EXPOSE 3000
CMD ["node", "server.js"]
