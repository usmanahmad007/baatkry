# 🔐 How to Enable Google Sign-In in Baatkry (Supabase)

This step-by-step guide walks you through enabling **Google OAuth Sign-In** for your Baatkry application.

---

## 1. Google Cloud Console Configuration

1. Visit the [Google Cloud Console Credentials Page](https://console.cloud.google.com/apis/credentials).
2. Select your project (or create a new project named **Baatkry**).
3. If not already configured, go to **OAuth consent screen**:
   - User Type: **External**
   - App Name: **Baatkry**
   - User support email: Select your email (`abbasusman753@gmail.com`)
   - Developer contact email: Enter your email
   - Scopes: Add `.../auth/userinfo.email`, `.../auth/userinfo.profile`, `openid`, and `.../auth/user.birthday.read` (for 18+ age verification)
   - Save and Continue.
4. Go to **Credentials** -> Click **+ CREATE CREDENTIALS** -> Select **OAuth client ID**.
5. Select **Application type**: **Web application**.
6. Set **Name**: `Baatkry Supabase Auth`.
7. Under **Authorized redirect URIs**, click **+ ADD URI** and enter:
   ```
   https://ahrsyiwgvkvosccwabpi.supabase.co/auth/v1/callback
   ```
   *(This is the official Supabase Auth callback URL for your project)*.
8. Click **CREATE**.
9. A popup will show:
   - **Client ID** (e.g. `123456789-xxxxxxxx.apps.googleusercontent.com`)
   - **Client Secret** (e.g. `GOCSPX-xxxxxxxxxxxx`)
   - Copy both values!

---

## 2. Supabase Dashboard Configuration

1. Open your [Supabase Project Dashboard](https://supabase.com/dashboard/project/ahrsyiwgvkvosccwabpi).
2. In the left sidebar, click **Authentication** (the key icon) -> **Providers**.
3. Locate **Google** in the list of providers and click to expand it.
4. Turn on the toggle **"Enable Google provider"**.
5. Paste:
   - **Client ID**: *(paste from step 1)*
   - **Client Secret**: *(paste from step 1)*
6. Click **Save** at the bottom.

---

## 3. Configure Redirect URLs in Supabase

1. In Supabase Dashboard, go to **Authentication** -> **URL Configuration**.
2. **Site URL**: Enter your main app URL (e.g. `http://localhost:3000` or production web URL).
3. Under **Redirect URLs**, click **Add URL** and add:
   - `com.usmanahmad.baatkry://login-callback/` *(for Android / iOS deep link)*
   - `http://localhost:3000/**` *(for local web testing)*
   - `https://baatkry.com/**` *(for production web)*
4. Click **Save**.

---

## 4. How Google Auth Works in Baatkry

- **Anonymous Guests** can browse and enter free unlimited random video calls without signing in.
- When an anonymous user attempts to:
  1. Filter by specific gender (**Women 👑**, **Men 👑**, **Trans 👑**), or
  2. Purchase coin packages in the Shop (min 500 Rs for 60 mins),
- Baatkry prompts the user to **Sign In with Google**.
- Once signed in, their coin balance, VIP status, and identity are permanently linked to their Google account and stored securely in Supabase.
