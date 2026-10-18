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
