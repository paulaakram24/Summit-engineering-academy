# Gmail SMTP for SEA authentication emails

Latest2026-10-25 acceptance: owner confirmed actual signup and recovery email
receipt from the new academy sender. Backend confirmed test-account email
verification. Owner-controlled recovery activation reached SEA; the updated
reset form visibly identified the original controlled test student. Owner then privately updated
the password, confirmed return to login and successful new-password sign-in;
main observed authenticated incomplete-profile routing. This Android recovery
path is accepted. Subsequent normal student logout ended server admission and
restart stayed signed out. Post-logout login and broader callback/device gates
remain separate; no production deliverability or every-platform claim.
No real password or token-bearing URL is recorded in this guide.

Academy mailbox changed by owner on2026-10-25 to summitengineeringacademy66@gmail.com, replacing summitengineeringacademy1@gmail.com. Owner reports saving SMTP sender/username/new-account app password and Google Branding support/contact settings. These are owner reports, not live secret/config inspection. This guide does not mean delivery is verified. This server-side SMTP setup is separate from Google sign-in/OAuth.

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
| Sender email | summitengineeringacademy66@gmail.com |
| Sender name | Summit Engineering Academy |
| SMTP host | smtp.gmail.com |
| Port | 587 |
| Username | summitengineeringacademy66@gmail.com |
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

## Coordinated retry — 2026-10-25

Owner authorized one signup-confirmation test for the original controlled test student. Preflight
found no existing Auth account. Public settings showed email enabled and
confirmation required. One public signup with a random memory-only disposable
password returned HTTP500/unexpected_failure, no user/session. Postflight found
zero test users, confirmations or account send timestamps. No automatic retry,
admin-session action or credential/config read occurred.

Sanitized Auth-log classification for13:50–13:57UTC found SMTP535/BadCredentials,
not the earlier534/InvalidSecondFactor. This establishes rejected SMTP
authentication, not which dashboard field is wrong. Recheck the username is the
new mailbox, generate a fresh app password in that same Google account and
replace only the protected SMTP credential directly in Supabase. Never share
it. Delivery/confirmation/recovery acceptance remain open; coordinate before
another send.

## Official references (setup)

### Password-recovery send check — 2026-10-25

Owner authorized one recovery test for the confirmed test account. One request
returnedHTTP200 and fresh readback shows recovery_sent_at14:17:14UTC. Mailbox
receipt is not yet confirmed. No reset link/code/token read or password changed.
This delivery-only REST check does not originate a mobile PKCE verifier:
complete native recovery must later start in a separate test installation,
not the retained administrator installation. No automatic resend.

Owner subsequently confirmed mailbox receipt and correct sender
summitengineeringacademy66@gmail.com. One real signup delivery is accepted.
After owner-controlled link activation on laptop, fresh read-only follow-up
finds1test account/1confirmed at2026-10-25T14:14:48.946092Z. Address confirmation
is accepted; the owner reported a blank browser return. Mobile callback,
deep-link/login and password-recovery acceptance remain open; the retained
emulator administrator session must not be replaced by this test.

### Follow-up after private app-password replacement — 2026-10-25

One newly authorized retry passed: preflight zero test accounts; HTTP200 signup
returned a user, no session, and unconfirmed state. Mailbox receipt and correct
sender still require owner observation; confirmation/deep-link and recovery are
separate open gates. The pending test account is retained, not deleted or
automatically resent. No administrator sign-in/session was changed.

- Google app passwords and eligibility: https://support.google.com/accounts/answer/185833
- Gmail SMTP host, TLS and authentication: https://support.google.com/mail/answer/7104828?hl=en-GB
- Supabase custom SMTP: https://supabase.com/docs/guides/auth/auth-smtp
- Free-tier custom SMTP/template distinction: https://supabase.com/changelog/46599-changes-to-email-template-customisation-on-free-tier
