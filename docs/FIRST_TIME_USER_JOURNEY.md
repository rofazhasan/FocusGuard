# FocusGuard — Non-Technical First-Time User Journey & Permission Onboarding

**Audience**: Everyday Non-Technical User (Student, Remote Professional, Parent)  
**Core Standard**: Zero Terminal, Zero Developer Tools, Zero Manual Database Edits, Progressive Permission Disclosure  

---

## 1. The 10-Stage Real-Life User Journey

```
[1. Download & Install]
        ↓
[2. Welcome & Account Creation]
        ↓
[3. Progressive Permission Consent]
        ↓
[4. Device Pairing & Sync]
        ↓
[5. First Focus Rule Creation]
        ↓
[6. First Focus Session]
        ↓
[7. Understanding Daily Dashboard]
        ↓
[8. Real-Life Error Recovery]
        ↓
[9. Data Ownership & Export]
        ↓
[10. Clean Uninstallation (If Desired)]
```

---

## 2. Stage-by-Stage User Experience Design

### Stage 1: Download & Install (Zero Terminal)
- **Problem Today**: Requires `git clone`, `go build`, `npm install`, and Chrome Developer Mode "Load Unpacked".
- **Target Experience**:
  - **Browser**: Single-click "Add to Chrome" / "Add to Firefox" button.
  - **macOS**: Drag `FocusGuard.app` into `/Applications`.
  - **Windows**: Standard `.msi` wizard with auto-launch shortcut.
  - **Android**: Standard `.apk` or Play Store install.

### Stage 2: Welcome & Account Creation
- User visits the Web Dashboard (`http://localhost:3001` or `app.focusguard.io`).
- Clear, welcoming prompt:
  > **Welcome to FocusGuard**  
  > *Protect your attention across all your devices with a single unified policy.*
- **Action**: Enter Email + Password -> Click "Create Account" or "Sign In".
- No cryptic error codes; instant email format validation and clear password requirements.

---

## 3. Progressive Permission Onboarding (The 4-Question Rule)

Never request permissions all at once. Never ask without explaining:
1. **WHAT** permission is needed?
2. **WHY** is it needed?
3. **WHAT** does FocusGuard do with it?
4. **WHAT** happens if you deny it?

### Permission Matrix & User Disclosures

| Platform | Permission Requested | Why It Is Needed | What FocusGuard Does | What Happens If Denied |
|---|---|---|---|---|
| **Browser Extension** | `declarativeNetRequest` & `webNavigation` | To detect and block distracting websites you specify (e.g., YouTube, Reddit). | Intercepts navigation requests only to domains in your active policy and redirects to a peaceful block screen. | Extension can track time spent but **cannot block** distracting websites. |
| **Browser Extension** | `idle` | To detect when you step away from your keyboard or mouse. | Pauses attention counters after 60 seconds of inactivity so idle time isn't counted as screen time. | Computer sleep or stepping away will falsely count as active distraction time. |
| **macOS** | Screen Time & FamilyControls | To shield distracting Mac desktop applications during deep work. | Applies native Apple Screen Time shields to locked apps during Focus Sessions. | Website blocking still works in browser, but native desktop apps cannot be shielded. |
| **Android** | Usage Access (`PACKAGE_USAGE_STATS`) | To track foreground time spent in distracting mobile apps. | Reads foreground package duration to calculate your daily attention budget. | Mobile app limits cannot be enforced. Device remains in tracking-only mode. |
| **Android** | Local VPN (`VpnService`) | To block distracting websites inside mobile browsers without routing traffic to external servers. | Runs a 100% on-device DNS filter. Blocked domains resolve to `NXDOMAIN`. **Zero traffic leaves your phone.** | Website blocking will not work on Android; app limits remain active. |
| **Android** | Notifications (`POST_NOTIFICATIONS`) | To alert you when 5 minutes remain in your budget or when a focus session concludes. | Sends gentle, rate-limited alerts. | You won't receive warnings before an app is locked. |

---

## 4. Stage 4: Device Pairing (Zero Technical Steps)

1. User opens Web Dashboard on primary computer -> Clicks **"+ Pair New Device"**.
2. Dashboard displays a large, high-contrast **6-Character Code** (e.g., `FG-7842`) and a QR Code, with a 5-minute countdown timer.
3. User opens FocusGuard on Android phone, secondary laptop, or browser popup:
   - Types `FG-7842` or scans QR code.
4. Dashboard instantly shows:
   > *"Pixel 8 Pro is requesting to pair with your account. Allow?"*
5. Owner clicks **"Approve Device"**.
6. Both devices show green checkmark: **✓ Device Paired & Protected**.

---

## 5. Stage 5: Creating Your First Focus Rule (Human Language UI)

Avoid raw JSON or developer terminology. Provide clear, conversational presets:

```
[ Conversational Policy Creator ]

"I want to:"
[ Limit ] [ Block Entirely ] [ Schedule Quiet Hours ]

"This website or app:"
[ YouTube.com                       ▼ ] (e.g., youtube.com, instagram.com, tiktok.com)

"To a maximum of:"
[ 30 minutes ] daily

"Applies to:"
[ All My Devices (Fleet)            ▼ ]

[ Save & Apply Protection ]
```

---

## 6. Stage 6: The Daily Focus Session

User clicks large hero button: **START FOCUS**.
- Select duration: **25 min** (Pomodoro), **45 min** (Standard), **60 min**, or **Custom**.
- Select target group: **All Devices** or **Work Devices**.
- Real-time display during session:
  - Remaining time: `34:21`
  - Active shields: `Active across 3 devices`
  - Offline devices: `Pixel 8 Pro (Offline - local shield active)`
- Button: **End Session Early** (with 10-second deliberate hold to prevent impulsive bypass).

---

## 7. Stage 7: Clear, Human Error Recovery

When a user encounters a block or network outage, never show `403 Forbidden` or `ERR_CONNECTION_FAILED`:

### Blocked Screen Message:
> ### 🛡️ Attention Budget Reached
> **Why am I seeing this?**  
> You set a daily limit of **30 minutes** on **youtube.com**. You have used **30m 12s** today.  
> **When does it reset?**  
> Tomorrow at **12:00 AM (Your Local Time)**.  
> *Need an emergency bypass? Open your Owner Dashboard to adjust your policy.*

### Offline State Message:
> ### ⚠️ Device Offline
> Your current restrictions and focus rules are **active and protecting you locally**.  
> Your usage data is safely saved on this device and will synchronize automatically when your internet connection returns.

---

## 8. Stage 8: Data Ownership & Clean Uninstall

- **Data Export**: User can click **"Export My Data"** at any time to receive a `.csv` or `.json` file of their usage history.
- **Device Disconnection**: User can click **"Disconnect Device"** in settings. All local tokens and policies are wiped immediately.
- **Account Deletion**: User can click **"Delete Account & Wipe All History"**. All records in `users`, `devices`, `policies`, and `usage_aggregates` are deleted with cascading database cleanup.
