# Operations: Deployment Guide

This guide describes production deployment options for FocusGuard using Docker, systemd, and reverse proxies.

---

## 1. Docker Compose Deployment

```yaml
version: '3.8'

services:
  focusguard-db:
    image: postgres:15-alpine
    environment:
      POSTGRES_USER: focusguard
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      POSTGRES_DB: focusguard_db
    volumes:
      - pgdata:/var/lib/postgresql/data
    restart: unless-stopped

  focusguard-server:
    build:
      context: ./backend
      dockerfile: Dockerfile
    environment:
      PORT: "8080"
      DB_HOST: focusguard-db
      DB_PORT: "5432"
      DB_USER: focusguard
      DB_PASSWORD: ${DB_PASSWORD}
      DB_NAME: focusguard_db
      JWT_SECRET: ${JWT_SECRET}
    ports:
      - "8080:8080"
    depends_on:
      - focusguard-db
    restart: unless-stopped

  focusguard-web:
    build:
      context: ./apps/web
      dockerfile: Dockerfile
    ports:
      - "3001:3001"
    restart: unless-stopped

volumes:
  pgdata:
```

---

## 2. Nginx Reverse Proxy & SSL Configuration

```nginx
server {
    listen 443 ssl http2;
    server_name focusguard.yourdomain.com;

    ssl_certificate /etc/letsencrypt/live/focusguard.yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/focusguard.yourdomain.com/privkey.pem;

    # REST API
    location /api/ {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    # WebSocket Hub
    location /ws {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_read_timeout 86400s;
    }

    # Web Dashboard
    location / {
        proxy_pass http://127.0.0.1:3001;
    }
}
```
