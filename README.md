# Baatkry (بات کری) ⚡
### Next-Gen Live Random & Gender-Filtered Video Chat Platform

[![Flutter](https://img.shields.io/badge/Flutter-3.24.5-blue.svg)](https://flutter.dev)
[![LiveKit](https://img.shields.io/badge/LiveKit-WebRTC%20SFU-magenta.svg)](https://livekit.io)
[![Supabase](https://img.shields.io/badge/Supabase-Backend%20%26%20Auth-green.svg)](https://supabase.com)
[![License](https://img.shields.io/badge/License-Proprietary-orange.svg)](#)

Baatkry is a cross-platform live video chatting platform (Web, Android, iOS) inspired by modern high-speed video matching apps. It combines zero-barrier 1-tap anonymous entry with a VIP economy for gender-targeted matchmaking.

---

## ✨ Key Features

- **Unified Flow (No Confusing Switchers):**
  - **Free Unlimited Chat:** Instant 1-tap random video matching worldwide. No email/password or phone registration needed.
  - **VIP Gender Filters:** Choose specifically to talk to **Women 👑**, **Men 👑**, or **Transgender 👑**.
- **Transparent Coin Economy:**
  - **Rate:** 20 Rupees = 1 Minute (1 Coin = 1 Second of Gender-Filtered Video Chat).
  - **Minimum Deposit:** 500 Rs (25 Minutes = 1,500 Coins).
  - **Free Tier:** Unlimited random matching is 100% free forever.
- **One-Time Permission System:**
  - Camera & microphone permissions are requested once and cached with `SharedPreferences`.
  - Zero redundant prompts across screens or calls.
- **Dual Video Interface:**
  - **Desktop:** Half screen for user and half screen for partner, side-by-side with sleek chat panel.
  - **Mobile:** 50/50 vertical responsive split with quick emojis and skip button.
- **Modern Cyberpunk / Obsidian Gradient Design:**
  - Deep obsidian mesh background with electric violet, indigo, and hot pink accents.
  - Frosted glassmorphic card containers with glowing gradient borders.
- **Google OAuth & Anonymous Auth:**
  - Guests can join instantly.
  - Google Sign-In is required to purchase coin packages and save VIP status.
- **Safety Lab & Moderation:**
  - Apple App Store & Google Play Guideline compliant.
  - Instant user reporting, blocking, and Zero-Tolerance EULA agreement.

---

## 🪙 Coin Packages

| Package | Price (PKR) | Minutes | Coins (1 coin = 1 sec) | Bonus Perks |
| :--- | :--- | :--- | :--- | :--- |
| **Starter Pack** | Rs. 500 | 25 Mins | 1,500 Coins | Minimum Deposit Tier |
| **Popular VIP** | Rs. 1,000 | 55 Mins | 3,300 Coins | +5 Bonus Minutes |
| **Pro VIP Pass** | Rs. 2,500 | 150 Mins | 9,000 Coins | +25 Bonus Mins + Gold VIP Badge |
| **King VIP Access**| Rs. 5,000 | 350 Mins | 21,000 Coins | +100 Bonus Mins + Instant Priority |

---

## 🛠 Tech Stack

- **Frontend:** Flutter 3.24.5 / Dart 3.5.4 (Web, Android, iOS)
- **WebRTC SFU:** LiveKit Cloud
- **Backend / Database:** Supabase (PostgreSQL, Realtime Presence, Auth)
- **State Management:** Riverpod & StatefulStreams
- **Package Identifier:** `com.usmanahmad.baatkry`

---

## 🚀 Running Locally

```bash
# 1. Clone repository
git clone https://github.com/usmanahmad007/baatkry.git
cd baatkry

# 2. Get dependencies
flutter pub get

# 3. Run Web
flutter run -d chrome

# 4. Build Web Release
flutter build web --release
```

---

## 🔐 Setup Google Sign-In

Refer to [GOOGLE_AUTH_SETUP.md](GOOGLE_AUTH_SETUP.md) for full instructions on setting up Google Cloud OAuth credentials and Supabase Auth.
