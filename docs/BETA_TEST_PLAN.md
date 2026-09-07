# FocusGuard — Real User Beta Test Plan

**Cohort Size**: 3–5 Non-Technical External Testers  
**Duration**: 14 Continuous Days  
**Guiding Objective**: Find what confuses users, what breaks in the real world, and what would stop someone from using FocusGuard every day.

---

## 1. Tester Cohort Profiles

1. **Tester 1 (Student / Heavy Multitasker)**:
   - Primary: MacBook Pro (macOS Sonoma) + Android Phone (Pixel 7).
   - Core behavior: 40+ browser tabs, daily YouTube study sessions, frequent sleep/wake laptop toggles, campus WiFi transitions.
2. **Tester 2 (Remote Professional)**:
   - Primary: Windows 11 Desktop + Chrome & Firefox + Android Tablet.
   - Core behavior: 8-hour workday, Zoom calls, dual monitors, home VPN usage.
3. **Tester 3 (Digital Minimalist / Parent)**:
   - Primary: MacBook Air + Android Phone.
   - Core behavior: Seeking strict 30-minute daily limits on social media across all personal devices.

---

## 2. Testing Schedule & Scenarios

| Day | Action & Test Scenario | Verification Objective |
|:---:|---|---|
| **Day 1** | Initial Install & Account Creation | Can the user install the extension and apps without asking for help or using the terminal? |
| **Day 2** | Device Pairing | Pair secondary computer and phone using the 6-digit code. Did pairing complete in under 60 seconds? |
| **Day 3** | First Policy Setup | Create rule: "Limit YouTube to 30 minutes daily across all devices". Is the conversational UI intuitive? |
| **Day 4** | Normal Usage & Idle Detection | Watch YouTube for 10 minutes, walk away from computer for 20 minutes. Did FocusGuard count 10m or 30m? |
| **Day 5** | Multi-Device Budget Depletion | Use 15m YouTube on Mac, then 15m on phone. Did both devices lock YouTube simultaneously? |
| **Day 6** | Deep Focus Session | Start a 45-minute Focus Session. Verify that all distracting apps and websites lock across all paired devices. |
| **Day 7** | Offline Resilience & Reboot | Turn off WiFi, restart computer, use computer offline. Did existing restrictions stay active? |
| **Day 8** | Network Recovery & Resync | Reconnect WiFi. Did offline usage upload without duplicating totals or losing events? |
| **Day 10** | Error Experience & Block Screen | Trigger a block. Does the block page clearly explain the policy, used time, and next reset time? |
| **Day 14** | Data Export & Clean Disconnect | Export usage history to CSV and test removing a device cleanly. |

---

## 3. Qualitative & Quantitative Feedback Protocol

Never ask generic questions like *"Do you like the product?"*. Ask targeted, friction-revealing questions:
- *"Where did you feel stuck or confused during setup?"*
- *"Did FocusGuard ever block a website you legitimately needed for work or study?"*
- *"Did you notice any battery drain or laptop heating while FocusGuard was running?"*
- *"What would make you uninstall FocusGuard?"*

---

## 4. Exit Criteria for STABLE Release

- [ ] Zero crash loops on any tester device over 14 days.
- [ ] Zero unrecoverable pairing or synchronization lockouts.
- [ ] Average tester battery impact on mobile < 3.5% over 24 hours.
- [ ] 100% of offline events synchronized accurately upon network restoration without duplicate records.
