# FocusGuard Web App — Production Container
FROM node:20-alpine AS runner

WORKDIR /app

# Copy package and server files
COPY apps/web/package.json ./
RUN if [ -f package.json ]; then npm install --production; fi

COPY apps/web/ ./

ENV PORT=3001
ENV NODE_ENV=production

EXPOSE 3001

HEALTHCHECK --interval=10s --timeout=5s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3001/ || exit 1

CMD ["node", "server.js"]
