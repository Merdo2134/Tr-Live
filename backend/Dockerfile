FROM node:20-alpine
ENV NODE_ENV=production
WORKDIR /app
COPY package*.json ./
RUN npm install --omit=dev && npm cache clean --force
COPY src ./src
# Yüklenen profil görselleri için kalıcı bir dizin (volume bağlayın: -v trlive-uploads:/app/uploads)
RUN mkdir -p /app/uploads && chown -R node:node /app
USER node
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s CMD wget -qO- http://127.0.0.1:${PORT:-3000}/health || exit 1
# Migration'lar advisory lock ile korunur; her açılışta güvenle çalıştırılabilir.
CMD ["sh", "-c", "node src/migration_runner.js && node src/server.js"]
