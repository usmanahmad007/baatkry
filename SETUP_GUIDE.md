# 🐒 Monkey & Omegle Cross-Platform Video App Setup Guide

This guide walks you through connecting your **Supabase** backend and **LiveKit Cloud** WebRTC video infrastructure.

---

## 1. Supabase Backend Setup

### Step 1.1: Run Database Schema
1. Open your [Supabase Dashboard](https://supabase.com/dashboard).
2. Go to **SQL Editor** -> **New Query**.
3. Copy and paste the entire contents of `supabase_schema.sql` (located in the project root).
4. Click **Run**. This will create:
   - `profiles` table (supports both Anonymous Guests and Registered Users).
   - `blocked_users` table (guarantees you never match with a blocked user again).
   - `reports` table (moderation flagging for Apple/Google App Store compliance).
   - `match_queue` table (realtime queue fallback).
   - `coin_transactions` table (purchase history).
   - Realtime Publication enabling sub-50ms queue updates.

### Step 1.2: Enable Anonymous Sign-In in Supabase
1. In your Supabase Dashboard, navigate to **Authentication** -> **Providers**.
2. Under **General**, ensure **Enable Anonymous Sign-ins** is switched **ON** (allows 1-click Omegle guest chat).
3. Under **Email**, make sure email sign-in/sign-up is enabled (used when users upgrade to buy coins or VIP).

### Step 1.3: Add Credentials to Flutter
Open `lib/core/config/app_config.dart` and paste your project URL and Anon key:
```dart
static const String supabaseUrl = 'https://YOUR_PROJECT_ID.supabase.co';
static const String supabaseAnonKey = 'eyJhbGciOi...YOUR_ANON_KEY';
```

---

## 2. LiveKit Cloud Setup

1. Create a free account at [LiveKit Cloud](https://cloud.livekit.io).
2. Create a new project.
3. Under **Settings** -> **Keys**, copy your:
   - **WebSocket URL** (e.g. `wss://your-project.livekit.cloud`)
   - **API Key**
   - **API Secret**
4. Paste them into `lib/core/config/app_config.dart`:
```dart
static const String liveKitWsUrl = 'wss://your-project.livekit.cloud';
static const String liveKitApiKey = 'API...';
static const String liveKitApiSecret = 'SECRET...';
```

---

## 3. Purchase & Login Policy (Requirement Verification)

- **Anonymous Guests (Omegle Mode)**: Users can enter and chat immediately without an account.
- **Login Requirement for Purchases**:
  - If an anonymous user attempts to buy coins or unlock VIP gender filters, the app blocks the transaction and presents the **Login Required** modal.
  - Once signed in or registered, the user's wallet is credited, securely tied to their Supabase user ID.

---

## 4. Running the App & Website

### Run as a Website in Google Chrome:
```bash
flutter run -d chrome
```

### Run on iOS:
```bash
flutter run -d ios
```

### Run on Android:
```bash
flutter run -d android
```

---

## 5. Development / Offline Testing Mode

Even before you paste your API keys, the app has a built-in **high-fidelity preview mode**:
- Camera and microphone preview work locally.
- 15-second Monkey countdown timer, "+15s" coin booster, and dual video PiP are interactive.
- Matchmaking generates a simulated partner with sound and chat interaction so you can test all screens immediately.
