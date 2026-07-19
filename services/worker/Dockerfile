# Multi-stage build for the services/worker job/deployment
# (Stage 5.5 dispatch/reconciliation). Built from the repo root:
#   docker build -f services/worker/Dockerfile -t writerflow-worker .

FROM node:24-alpine AS build
WORKDIR /workspace
COPY package.json package-lock.json ./
COPY services/shared/package.json services/shared/package.json
COPY services/api/package.json services/api/package.json
COPY services/worker/package.json services/worker/package.json
RUN npm ci
COPY tsconfig.base.json ./
COPY services/shared services/shared
COPY services/worker services/worker
RUN npm run build --workspace services/shared --workspace services/worker

FROM node:24-alpine AS runtime
ENV NODE_ENV=production
WORKDIR /app
COPY package.json package-lock.json ./
COPY services/shared/package.json services/shared/package.json
COPY services/api/package.json services/api/package.json
COPY services/worker/package.json services/worker/package.json
RUN npm ci --omit=dev --workspace services/shared --workspace services/worker
COPY --from=build /workspace/services/shared/dist services/shared/dist
COPY --from=build /workspace/services/worker/dist services/worker/dist
USER node
CMD ["node", "services/worker/dist/src/index.js"]
