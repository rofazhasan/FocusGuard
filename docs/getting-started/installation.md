# Installation Guide

This guide details the prerequisite toolchains and build processes required to deploy the FocusGuard backend, web command dashboard, and native client applications.

---

## 1. System Requirements

### Backend & Web Dashboard
- **Operating System**: macOS (Sonoma 14+ / Sequoia 15+), Linux (Ubuntu 22.04+, Debian 12+, Arch), or Windows (WSL2).
- **Go**: Version `1.22` or later.
- **Node.js**: Version `18.0.0` or later with `npm`.
- **Database (Optional)**: PostgreSQL `14+` (if not using the default embedded SQLite).

### macOS Client
- **macOS**: Version `14.0 (Sonoma)` or `15.0 (Sequoia)`.
- **Xcode**: Version `15.0` or later.
- **Swift**: Version `5.9` or `6.0+`.
- **Entitlements**: Apple Developer account with `Family Controls` capability for production builds.

### Android Client
- **Android OS**: Android 10 (API Level 29) through Android 15 (API Level 35).
- **JDK**: OpenJDK `17` or `21`.
- **Android Studio**: `Iguana (2023.2.1)` or later.
- **Android SDK**: Build-Tools `35.0.0`, SDK Platform `android-35`.

---

## 2. Installing the Backend Server

### Clone the Repository
```bash
git clone https://github.com/rofazhasan/FocusGuard.git
cd FocusGuard/backend
```

### Build the Go Server Binary
```bash
go build -o bin/focusguard-server cmd/server/main.go
```

### Environment Configuration
By default, FocusGuard automatically initializes an embedded SQLite database (`focusguard.db`) in write-ahead log (WAL) mode if PostgreSQL environment variables are absent.

To configure PostgreSQL instead, set the following environment variables:
```bash
export DB_HOST="localhost"
export DB_PORT="5432"
export DB_USER="focusguard"
export DB_PASSWORD="your_secure_password"
export DB_NAME="focusguard_db"
export JWT_SECRET="your_production_jwt_signing_key_32_chars_min"
export PORT="8080"
```

---

## 3. Installing the Web Command Dashboard

```bash
cd FocusGuard/apps/web
npm install
```

The Web Command Center uses native web standards (Vanilla CSS & JavaScript) with WebSocket client bindings for low-latency command dispatch and live usage monitoring.

---

## 4. Building the Native macOS Client

1. Open the project in Xcode:
   ```bash
   open apps/macos/FocusGuard.xcodeproj
   ```
2. Select your development team in **Signing & Capabilities**.
3. Ensure the `Family Controls (Development)` entitlement is active.
4. Select the target **FocusGuard (macOS)** and click **Product > Build** (`Cmd+B`).

---

## 5. Building the Native Android Client

1. Open `apps/android` in Android Studio.
2. Allow Gradle to synchronize dependencies.
3. Build the debug APK via Gradle wrapper:
   ```bash
   cd apps/android
   ./gradlew assembleDebug
   ```
4. Output APK location: `app/build/outputs/apk/debug/app-debug.apk`.
