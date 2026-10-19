# Gmail SMTP for SEA authentication emails

Checked against official Google and Supabase guidance on 2026-10-19. This guide does not mean SMTP is configured or delivery verified. Use the academy mailbox summitengineeringacademy1@gmail.com, not the developer's personal mailbox. This server-side SMTP setup is separate from Google sign-in/OAuth.

Owner reported SMTP saved on 2026-10-19. Public Auth settings independently show email enabled and confirmation required; they do not verify SMTP credentials or delivery. One owner-controlled test recipient is needed before signup/confirmation acceptance. Never disturb the current administrator session to test sending.

## 1. Prepare the academy Google account

1. Sign into the academy mailbox in your browser; check the account avatar/email before continuing.
2. Open https://myaccount.google.com/security and enable 2-Step Verification yourself, completing Google's verification prompts.
3. Open https://myaccount.google.com/apppasswords using that same account.
4. Create an app password named `SEA Supabase Auth`.
5. Keep the generated password private. Enter it directly in Supabase's SMTP password field; never send it in chat, screenshots, Git, app configuration or a normal document. Do not use the regular Gmail password or Google OAuth client secret. A password manager may retain it securely.

If App passwords is unavailable, verify the correct account and 2-Step Verification first. Google may restrict the feature for managed accounts, Advanced Protection or security-key-only setups. Do not disable account security or look for an obsolete less-secure-apps switch; report the nonsecret message instead.

## 2. Configure Supabase

1. Open the `summit-academy-dev` project in Supabase.
2. Under Authentication, open the email/SMTP configuration. Look for Emails → SMTP Settings, or search settings for `SMTP` if the navigation differs.
3. Enable Custom SMTP and enter:

| Field | Value |
| --- | --- |
| Sender email | summitengineeringacademy1@gmail.com |
| Sender name | Summit Engineering Academy |
| SMTP host | smtp.gmail.com |
| Port | 587 |
| Username | summitengineeringacademy1@gmail.com |
| Password | The Google app password, entered privately |
| Encryption, if shown | STARTTLS/TLS appropriate for port 587; never plaintext |

4. Save the configuration. Keep email confirmation enabled and retain the existing `seaacademy-dev://auth/callback` redirect allowlist. Do not change Google OAuth settings or disable certificate verification.
5. Leave conservative send limits in place during testing; no paid upgrade is required merely to try this setup. Gmail quotas and Supabase limits both apply. Personal Gmail is a development/small-volume starting point, not a production delivery guarantee; evaluate a transactional sender before broad launch.

## 3. Verify, separately from saving settings

Tell the developer `SMTP saved`, without sending the password. Then coordinate one verification email to an owner-controlled test address. Do not log out the currently signed-in owner merely to test delivery.

Required acceptance remains: email arrives (check Spam), sender is correct, confirmation link returns to the app, confirmed email/password login works, and a separately coordinated reset email/link/password update works. Delivery alone does not prove mobile callback or recovery acceptance. Never send the full confirmation/reset URL, code or token in chat. A failed send should be diagnosed from sanitized errors, not repeated in a loop.

Changing the Google account password revokes app passwords; if that happens, generate a replacement and update Supabase privately. This SMTP configuration handles Supabase Auth emails, not future course announcements or marketing delivery.

## Observed test failure — 2026-10-19

The first owner-authorized delivery test failed with HTTP 500 / unexpected_failure. Sanitized backend error classification identified Gmail SMTP `534 5.7.9 Application-specific password required` / `InvalidSecondFactor`. No test user or session persisted and no repeated sends were attempted. This proves Gmail was reached but rejected SMTP authentication; it does not prove which value was entered in the dashboard.

Sign into the configured academy sender account, verify 2-Step Verification, generate a fresh `SEA Supabase Auth` app password, and privately replace Supabase's SMTP password field with that value (without Google's display spacing). Keep the SMTP username equal to the same academy account and save. Never share the app password; tell the developer only that it was updated before one coordinated retry. Do not disable confirmation, account security or certificate checks to bypass the failure.

## Official references

- Google app passwords and eligibility: https://support.google.com/accounts/answer/185833
- Gmail SMTP host, TLS and authentication: https://support.google.com/mail/answer/7104828?hl=en-GB
- Supabase custom SMTP: https://supabase.com/docs/guides/auth/auth-smtp
- Free-tier custom SMTP/template distinction: https://supabase.com/changelog/46599-changes-to-email-template-customisation-on-free-tier
