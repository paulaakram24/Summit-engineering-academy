# Google sign-in: owner setup

This is for the development app's browser-based OAuth flow. No paid Google Cloud services or billing activation are needed for these steps. Do not enable billing or paid Supabase upgrades for this setup.

1. Open https://console.cloud.google.com/ and sign in to the Google account that should own the academy project.
2. Use the project selector, choose **New project**, name it **Summit Engineering Academy Dev**, and create/select it. Use the appropriate organization or **No organization** if this is a personal account.
3. Open **Google Auth Platform** (or **APIs & Services → OAuth consent screen**). Choose **Get started** if prompted.
4. In **Branding**, set the app name to **Summit Engineering Academy**. Use an email you control for support/contact. Do not invent a website, privacy policy or terms URL. If required fields prevent completing development configuration, ask for guidance rather than entering fake links.
5. Choose **External** audience. Keep publishing status **Testing**, and add `bolaakram123@gmail.com` as a test user. Add other controlled test accounts only when needed.
6. Under **Data Access**, use only identity scopes: `openid`, email and profile. Do not request Gmail/mailbox access for app sign-in.
7. Under **Clients**, create an OAuth client with application type **Web application**, named **SEA Supabase Dev**. This is correct even though SEA is a mobile app: Google returns to Supabase first.
8. Add this exact **Authorized redirect URI**:

   `https://ucbdgbspzvjinjpvxjdk.supabase.co/auth/v1/callback`

   It must match the callback displayed in the Supabase Google provider panel. Do not put the mobile custom scheme in Google's redirect field. No JavaScript origin is required for this browser-redirect-only mobile flow.
9. In Supabase project **summit-academy-dev**, open **Authentication → Sign In / Providers → Google** (labels may vary), enable Google, and paste the client ID and secret directly from Google into Supabase. Save. Never send the secret in chat or add it to the repository.
10. Supabase **Authentication → URL Configuration → Redirect URLs** must contain `seaacademy-dev://auth/callback`. The owner reported saving this already on 2026-10-16.
11. Tell the coding assistant **Google configured**. It can check the public provider settings without seeing your secret, then guide a real device login/cancel/restart test.

Google Cloud project membership, Supabase organization membership, and SEA app admin role are separate. Completing this setup does not automatically make a user an SEA admin. That happens only after verified app registration and explicit server provisioning.

Source: [Supabase Google provider configuration](https://supabase.com/docs/guides/auth/social-login/auth-google). A successful provider toggle is not yet proof of successful mobile login. Production consent/branding and store policy review remain later release gates.

## Device acceptance (2026-10-18 follow-up)

Start every attempt from the current SEA app's Continue with Google button. A saved browser authorization URL is not a reusable login link: PKCE requires a fresh SDK-generated challenge and the corresponding verifier held by that installation. Do not open the Supabase callback URL directly; it requires state/code values supplied by Google's actual redirect.

The app now validates its SDK-generated S256 PKCE URL and opens an Android Custom Tab / iOS browser view with an account chooser. It never uses an embedded Android WebView for Google sign-in. Only identity scopes (openid, email, profile) are requested. No OAuth state/code/token values should be copied into chat or logs.

After successful sign-in, incomplete profiles must review/save their name and enter a valid phone number and university before the learning-space screen appears. Name and phone are mandatory; university remains mandatory under the original requirements. A prefilled Google name is editable. Complete returning profiles do not repeat onboarding. Test real login, profile save, restart, logout, and device-session denial before marking Phase 1 accepted.

### Huawei Chrome account-settings detour

Phone tracing confirmed Google returned HTTP 204 with `X-Chrome-Manage-Accounts` action `ADDSESSION`: Chrome canceled the web navigation and opened its native account-management screen. Tapping an account there opens Android account settings; that screen is not SEA's Google web account chooser.

An isolated Chrome Custom Tab rendered the real Google sign-in webpage on the same phone. Android uses capability-checked ephemeral browsing where supported, with the existing real-browser fallback elsewhere. This does not change the user's Chrome accounts, cookies or security settings. In an isolated window, enter your Google email and complete Google's prompts yourself; do not send passwords, codes or the full browser URL to anyone. Successful page rendering alone does not prove the callback/session exchange works.

Reference: [Chrome's ephemeral Custom Tabs guide](https://developer.chrome.com/docs/android/custom-tabs/guide-ephemeral-tab).
