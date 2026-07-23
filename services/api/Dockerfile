# Multi-stage build for the services/api Container App
# (infra/bicep/modules/container-app-api.bicep). Built from the repo root:
#   docker build -f services/api/Dockerfile -t writerflow-api .

FROM node:24-alpine AS build
WORKDIR /workspace
COPY package.json package-lock.json ./
COPY services/shared/package.json services/shared/package.json
COPY services/api/package.json services/api/package.json
COPY services/worker/package.json services/worker/package.json
RUN npm ci
COPY tsconfig.base.json ./
COPY services/shared services/shared
COPY services/api services/api
COPY prompts prompts
RUN npm run build --workspace services/shared --workspace services/api

FROM node:24-alpine AS runtime
ENV NODE_ENV=production
WORKDIR /app
COPY package.json package-lock.json ./
COPY services/shared/package.json services/shared/package.json
COPY services/api/package.json services/api/package.json
COPY services/worker/package.json services/worker/package.json
RUN npm ci --omit=dev --workspace services/shared --workspace services/api
COPY --from=build /workspace/services/shared/dist services/shared/dist
COPY --from=build /workspace/services/api/dist services/api/dist
COPY --from=build /workspace/prompts prompts
ENV PROMPTS_DIR=/app/prompts
USER node
EXPOSE 8080
CMD ["node", "services/api/dist/src/index.js"]
