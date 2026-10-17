# Yönetim paneli: veritabanı aktarma (pg_dump/psql) için PostgreSQL araçlarının bulunduğu imaj + Node.
FROM postgres:18-alpine
RUN apk add --no-cache nodejs
WORKDIR /app
COPY server.mjs ./
ENTRYPOINT []
EXPOSE 8090
CMD ["node", "/app/server.mjs"]
