# 🔐 How to Enable Google Sign-In in Baatkry (Supabase)

This step-by-step guide walks you through enabling **Google OAuth Sign-In** for your Baatkry application and resolving any permission or verification errors.

---

## 🚨 Fixing `Error 403: access_denied` ("App has not completed Google verification")

If you see this error when logging in with Google:
> **`ahrsyiwgvkvosccwabpi.supabase.co has not completed the Google verification process. The app is currently being tested, and can only be accessed by developer-approved testers. Error 403: access_denied`**

This happens because your Google Cloud OAuth Consent Screen is currently in **"Testing"** mode. In Testing mode, Google restricts login exclusively to email addresses registered in the **"Test Users"** list.

### Solution A: The 30-Second Fix (Add Test User for immediate testing)
1. Go to the [Google Cloud Console - OAuth Consent Screen](https://console.cloud.google.com/apis/credentials/consent).
2. Ensure project **Baatkry** is selected at the top.
3. Scroll down to the **"Test users"** section.
4. Click **`+ ADD USERS`**.
5. Enter your Google/Gmail address (e.g., `abbasusman753@gmail.com` and any other testing emails).
6. Click **SAVE**.
7. Go back to Baatkry and click **Sign in with Google** — it will now work immediately!

---

### Solution B: The Permanent Fix (Make available for ALL users)
1. In [Google Cloud Console - OAuth Consent Screen](https://console.cloud.google.com/apis/credentials/consent).
2. Under **Publishing status**, click the **"PUBLISH APP"** button.
3. A popup will ask *"Push to production?"* -> Click **CONFIRM**.
4. **Why this works without verification:** Baatkry uses standard non-sensitive scopes (`email`, `profile`, `openid`). Official age verification is performed directly by asking the user to enter their date of birth according to their official birth certificate. Non-sensitive apps do NOT require Google manual review or CASA security assessment!
5. Once published, ANY user can sign in with Google without getting Error 403.

---

## 1. Google Cloud Console Configuration

1. Visit the [Google Cloud Console Credentials Page](https://console.cloud.google.com/apis/credentials).
2. Select your project (or create a new project named **Baatkry**).
3. If not already configured, go to **OAuth consent screen**:
   - User Type: **External**
   - App Name: **Baatkry**
   - User support email: Select your email (`abbasusman753@gmail.com`)
   - Developer contact email: Enter your email
   - Scopes: Keep standard non-sensitive scopes:
     - `.../auth/userinfo.email`
     - `.../auth/userinfo.profile`
     - `openid`
     *(Do not request sensitive scopes like `birthday.read` so Google verification is not required)*
   - Save and Continue.
4. Under **Test users**, click **+ ADD USERS** and add your Gmail address.
5. Go to **Credentials** -> Click **+ CREATE CREDENTIALS** -> Select **OAuth client ID**.
6. Select **Application type**: **Web application**.
7. Set **Name**: `Baatkry Supabase Auth`.
8. Under **Authorized redirect URIs**, click **+ ADD URI** and enter:
   ```
   https://ahrsyiwgvkvosccwabpi.supabase.co/auth/v1/callback
   ```
   *(This is the official Supabase Auth callback URL for your project)*.
9. Click **CREATE**.
10. A popup will show:
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

## 4. How Age Verification & Google Auth Work Together in Baatkry

- **Official Birth Certificate Age Verification:**
  - Baatkry does NOT assume or pre-fill any birth date.
  - When opening the app or starting a call, the user is required to enter their exact Date of Birth according to their official birth certificate or government ID.
  - If calculated age is **18+**: They are granted access.
  - If calculated age is **under 18**: They are permanently locked out and forbidden from using the app.
- **Anonymous Guests:**
  - Can chat randomly for 3 minutes total (max 30 seconds per partner with automatic rotation).
- **Google Users:**
  - Get unlimited random chat.
  - To filter by specific gender (Women 👑, Men 👑, Trans 👑), they purchase coins (minimum 500 Rs = 60 minutes).
