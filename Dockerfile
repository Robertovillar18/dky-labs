# --- Build stage ---
FROM node:20-alpine AS build
WORKDIR /work/site
COPY site/package*.json ./
RUN npm ci || npm install
COPY site/ .
# Opcional: fija la URL base si la necesitás
# ENV URL=https://tusitio.com
RUN npm run build

# --- Runtime stage ---
FROM nginx:alpine
# Config Nginx optimizada para SPA estática
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /work/site/build /usr/share/nginx/html
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=3s --retries=3 CMD wget -qO- http://localhost/ > /dev/null || exit 1
