FROM node:22-slim
# Debian-based image. Alpine + Prisma имеет проблему с OpenSSL,
# bundled schema-engine у Prisma ждёт OpenSSL 1.1/3.0 в нужной версии.
# С slim'ом всё работает из коробки.

# Prisma нужны системные библиотеки openssl и ca-certificates.
# ffmpeg нужен Instagram-downloader'у (Phase B): извлечь width/height/duration
# через ffprobe и сгенерировать thumbnail для рилсов через ffmpeg.
RUN apt-get update -y \
  && apt-get install -y --no-install-recommends openssl ca-certificates ffmpeg \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install dependencies first (leverages Docker layer cache).
COPY package.json package-lock.json* ./
RUN npm install --no-audit --no-fund

# Prisma needs the schema to generate the client.
COPY prisma ./prisma
RUN npx prisma generate

# App source.
COPY tsconfig.json ./
COPY src ./src

EXPOSE 3000

# Default command — used by Railway in production.
# In docker-compose dev mode this is overridden by `command: npm run dev`.
CMD ["npx", "tsx", "src/server.ts"]
