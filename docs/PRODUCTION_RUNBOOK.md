# FocusGuard — Production Deployment & Operations Runbook

## 1. System Overview

FocusGuard is a multi-platform attention management and policy enforcement platform consisting of:
- **Go 1.22+ Backend API & WebSocket Gateway** (`:8080`)
- **PostgreSQL 16** (`:5432`) with embedded Pure-Go SQLite fallback
- **Web Administration Dashboard** (`:3001`)
- **Cross-Platform Enforcers**: Browser Extension (MV3 DNR), macOS Native Agent (`ScreenTime`/`DeviceActivity`), Android (`VpnService`).

---

## 2. Production Environment Variables (`.env.production`)

Create `/path/to/focusguard/.env.production` before launching:

```ini
# Application Mode
ENV=production
NODE_ENV=production
PORT=8080

# Security (CRITICAL: Must be at least 32 characters, unique, and kept secret)
JWT_SECRET=fg_prod_sec_99348bcae2801f4961d84a329e701bc93ef64201

# Allowed Origins for CORS and WebSocket CSWSH Defense
# Comma-separated list of fully qualified domains:
ALLOWED_ORIGINS=https://dashboard.focusguard.io,https://app.focusguard.io

# PostgreSQL Configuration
DB_HOST=postgres
DB_PORT=5432
DB_USER=focusguard
DB_PASSWORD=YOUR_STRONG_DATABASE_PASSWORD_HERE
DB_NAME=focusguard_db
DB_SSLMODE=disable

# Optional SQLite Persistent File Path (if running without Postgres)
# SQLITE_PATH=/var/lib/focusguard/data/focusguard.db
```

---

## 3. Production Deployment with Docker Compose

### 3.1 Start Services
```bash
# Clone the repository
git clone https://github.com/focusguard/focusguard.git /opt/focusguard
cd /opt/focusguard

# Create production env
cp .env.example .env.production
# Edit passwords and JWT secrets
nano .env.production

# Build and start all services in detached mode
docker compose -f docker-compose.yml up -d --build
```

### 3.2 Verify Running Services
```bash
docker compose ps
```
Expected output:
```text
NAME                  IMAGE                        COMMAND                  SERVICE    STATUS
focusguard-postgres   postgres:16-alpine           "docker-entrypoint.s…"   postgres   Up (healthy)
focusguard-backend    focusguard-backend:latest    "./focusguard-server"    backend    Up (healthy)
focusguard-web        focusguard-web:latest        "node server.js"         web        Up (healthy)
```

---

## 4. Health Checks & Verification

### 4.1 Readiness Probe (Verifies API + DB connection)
```bash
curl -i http://localhost:8080/ready
```
Expected response:
```json
HTTP/1.1 200 OK
Content-Type: application/json

{"status":"READY","database":"UP"}
```

### 4.2 Liveness Probe
```bash
curl -i http://localhost:8080/health
```

### 4.3 Web Dashboard Health
```bash
curl -i http://localhost:3001/
```

---

## 5. Reverse Proxy Configuration (Nginx / SSL Termination)

In front of FocusGuard, terminate SSL using Nginx or Caddy:

```nginx
# /etc/nginx/sites-available/focusguard.conf
upstream focusguard_api {
    server 127.0.0.1:8080;
}

upstream focusguard_web {
    server 127.0.0.1:3001;
}

server {
    listen 80;
    server_name app.focusguard.io;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name app.focusguard.io;

    ssl_certificate /etc/letsencrypt/live/app.focusguard.io/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/app.focusguard.io/privkey.pem;

    # Web Dashboard
    location / {
        proxy_pass http://focusguard_web;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # REST APIs
    location /api/ {
        proxy_pass http://focusguard_api;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # WebSocket Real-Time Gateway
    location /ws {
        proxy_pass http://focusguard_api;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }
}
```

---

## 6. Client Distribution & Artifact Building

### 6.1 Chrome / Edge Browser Extension
```bash
cd apps/extension
# Package as a release zip
zip -r ../../dist/focusguard-extension-v1.0.0.zip . -x "*.DS_Store" "*tests*"
```
Upload `focusguard-extension-v1.0.0.zip` to the **Chrome Web Store Developer Dashboard**.

### 6.2 macOS Native Agent Release Build
```bash
cd apps/macos
swift build -c release
# The hardened executable is located at:
# apps/macos/.build/release/FocusGuardApp
```
To notarize for macOS:
```bash
codesign --deep --force --options runtime --sign "Developer ID Application: Your Name" .build/release/FocusGuardApp
xcrun notarytool submit FocusGuardApp.zip --keychain-profile "AC_PASSWORD" --wait
```

---

## 7. Backup & Maintenance

### 7.1 PostgreSQL Daily Backup
```bash
docker exec -t focusguard-postgres pg_dump -U focusguard focusguard_db | gzip > /backups/focusguard_$(date +%F).sql.gz
```

### 7.2 Database Restore
```bash
gunzip < /backups/focusguard_YYYY-MM-DD.sql.gz | docker exec -i focusguard-postgres psql -U focusguard -d focusguard_db
```

---

## 8. Rollback Procedures

If an issue occurs post-deployment:
```bash
# Revert to previous image tag or commit
git checkout <previous-tag>
docker compose -f docker-compose.yml up -d --build
```
EOF
