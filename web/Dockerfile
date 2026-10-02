FROM node:22-alpine AS build
WORKDIR /app
COPY web/package*.json ./
COPY web/.npmrc ./
RUN npm ci
COPY web/ ./
RUN npm run build
FROM nginxinc/nginx-unprivileged:1.30-alpine3.24
USER root
RUN apk upgrade --no-cache
USER 101
LABEL org.opencontainers.image.source="https://github.com/jorgefprietol/atlas-cloud-operations"
COPY --from=build /app/dist /usr/share/nginx/html
COPY web/nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 8080
