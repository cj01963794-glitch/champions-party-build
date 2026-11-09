FROM node:24-bookworm-slim
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends gosu && rm -rf /var/lib/apt/lists/*
COPY app.tar.br /tmp/app.tar.br
COPY frontier.tar.gz /app/frontier.tar.gz
RUN node -e "const fs=require('node:fs'),z=require('node:zlib');fs.writeFileSync('/tmp/app.tar',z.brotliDecompressSync(fs.readFileSync('/tmp/app.tar.br')))" && \
    tar -xf /tmp/app.tar -C /app && rm /tmp/app.tar /tmp/app.tar.br && \
    mkdir -p engine && tar -xzf frontier.tar.gz -C engine assets/workers game-content && \
    groupadd --system frontier && useradd --system --gid frontier --home-dir /app frontier && \
    mkdir -p /var/data && chown -R frontier:frontier /app /var/data && \
    chmod +x /app/docker-entrypoint.sh
ENV NODE_ENV=production FRONTIER_HOST=0.0.0.0 FRONTIER_WORKERS=1 FRONTIER_DATA=/var/data
EXPOSE 10000
ENTRYPOINT ["/app/docker-entrypoint.sh"]
CMD ["node","--expose-gc","--max-old-space-size=256","server.mjs"]
