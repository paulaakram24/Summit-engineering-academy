# Phase 1 native callback acceptance

## Updated failure guidance installed, 2026-10-26

Bootstrap now routes exchange/link-stream failures to a dedicated callback category. The UI conditionally advises email/password sign-in if email is already confirmed, otherwise restarting sign-in/password reset. It never claims a failed link verified an account and no longer mislabels all callback failures as network problems. No exchange/storage/admission/logout logic changed; private exception text is not displayed or logged.

Five new synthetic tests and all1035serial app tests passed (71s); analysis clean (8.6s) and three-file formatting unchanged. Android debug build passed142.2s; install-r retained data. APK189803233bytes/SHA2567D25D501BD3925BC3C158CEEE5231884C2997B01B40C32FF5A003E43A50E7907, installed hash matched. Empty Android user12 tested token-free cold/warm errors and visibly showed new guidance without protected content. Initial launch while locked timed out; swipe unlock plus a fresh app start completed the check. No device security setting was disabled.

Returned to existing Android user10: main freshly observed saved alias Student home without password/relogin. Backend alias registrations/admissions stay1/1; base Google1/1, original student2/0 and admin4/4 retain latest accepted counts. Test user12 has no account. Evidence: E:/Android-prerequisites-Summit/sea-callback-guidance-unlocked.png, sea-callback-guidance-warm-new.png and sea-alias-update-ready.png.

This fixes misleading guidance only. Original live exchange failure cause and a clean new live confirmation handoff remain open under roadmap1.3.6.2.3. Do not replay a consumed real link, inspect credentials or delete the working account. No push or new live signup email was performed. Earlier generic-error screenshots below are historical observations before this change.

## Accepted: synthetic denial on emulator, 2026-10-26

Used the existing installed APK and signed-out Android user 0 on emulator-5554. Preserved the signed-in administrator installation and all other user data. The callback used only the app's configured scheme/host/path and `error=access_denied`; it contained no code, token, email, recovery link or user credential.

1. Warm activity: Android delivered the VIEW/BROWSABLE intent to the already-running SEA activity. Main observed Account access unavailable and no protected workspace.
2. Cold activity: force-stopped only SEA for user 0, then launched the same synthetic error intent. Android reported COLD; main observed the same fail-closed error screen without a crash.
3. Back to sign in returned to empty email/password fields.
4. Fresh read-only backend comparison preserved all four pre-test admin application-admission fingerprints/four registrations and student two registrations/zero admissions/cleared pointer. A later additional admin admission had already appeared before these tests; the historical three-admission logout result is not the current baseline.

Evidence outside Git:

- `E:/Android-prerequisites-Summit/sea-callback-user0-settled.png`
- `E:/Android-prerequisites-Summit/sea-synthetic-callback-warm.png`
- `E:/Android-prerequisites-Summit/sea-synthetic-callback-cold.png`
- `E:/Android-prerequisites-Summit/sea-google-cancel-ready.png`

The generic error text suggests checking the connection; this is not a claim that cancellation-specific wording exists. No real Google cancellation or expired/used-link validation was performed. No code, package, SDK, Auth configuration, device-registration policy or account role changed. No test email or automated suite was run. This is not a performance benchmark or independent physical-device test.

## Accepted: owner-reported browser cancellation, 2026-10-26

The owner was asked to:

1. Tap Continue with Google.
2. At the first Google page, use Android Back before selecting an account, entering credentials or granting consent.
3. Report the final SEA screen. Share neither the browser URL nor passwords/codes.

In response, the owner supplied a screenshot of SEA Sign in with empty credentials, enabled Continue with Google, no visible error and no protected workspace. Accepted as owner-reported return after cancellation. Main did not observe/automate the Google page itself and did not perform a subsequent successful retry login. The visible retry entry point is not proof of a completed second OAuth attempt.

Fresh read-only backend comparison preserved the exact four pre-cancellation admin application-admission fingerprints/four registrations and student two registrations/zero admissions/cleared pointer. No session mutation or test email was performed. This is a bounded emulator result, not physical cancellation, expired/replayed credentials, other OAuth paths or every Supabase Auth session.

## Still separate

- Actual cold/warm successful OAuth return and failure paths.
- Owner-controlled expired/used-link handling; never route live credentials or recovery links through agent tooling.
- Original historical confirmation-exchange failure cause remains unknown. Fresh clean confirm2 native handoff is now accepted below; do not infer all OAuth/expired-used-link paths from that success.
- Physical Huawei and independent-device restart/session checks. Only the emulator was connected during this run.

Keep ROADMAP.md parent 1.3.8 and Phase 1 open until their full acceptance gates are met.

## Signup confirmation followed by password login, 2026-10-26

Owner approved fresh confirmation alias 1. Read-only preflight found no existing alias account. SEA signup was prepared in signed-out Android user 10 without logging out the base Google account in user 0 or touching admin sessions. Owner privately completed signup and reported receipt, then explicitly confirmed opening the link inside the emulator. Agent did not read/copy/activate the real confirmation link or a verification code.

First owner screenshot showed SEA Sign in with a generic account-access/connection warning. Read-only lookup at that checkpoint found verified email/email identity but no Auth session row, device registration or application admission. This proves neither a clean PKCE exchange nor the exact reason for failure.

Owner next privately entered the signup password and supplied Student home screenshot. Fresh read-only lookup confirmed verified email/email identity, enabled student role, one Auth session row, one registered installation, one unended application admission and active pointer. Accept fresh signup/delivery/owner-reported native return and subsequent password login under 1.3.6.1, but retain the unexpected callback-return warning under 1.3.6.2. Do not mark parent 1.3.6 or Phase 1 complete, and do not delete the now-working account or replay the consumed confirmation link to obtain diagnostics.

## Clean fresh confirm2 handoff accepted, 2026-10-26

This subsequent result supersedes the pending clean-handoff state above, not the historical observations. Owner approved fresh confirmation alias 2; read-only preflight found no existing account. Signup was prepared on installed7D25D5artifact in empty Android user12, with only approved email prefilled. Owner handled password/signup/email/link privately. The supplied screenshot shows warning-free Student home for confirm2. After being asked whether this was direct link return rather than a password fallback, owner explicitly confirmed "yes without entering the password."

The preceding read-only check verified confirmed email/email identity, enabled student, one Auth session row, one registered installation, one unended application admission and active pointer; current Android user12. No fresh backend query, build or suite was run for the clarification. Accept bounded1.3.6 native email signup/confirmation return plus the earlier password-login result. The original failed exchange's exact cause is not established; conditional error-guidance correction is not proof of a PKCE defect fix. Preserve working accounts and investigate any recurrence without replaying real consumed links or reading credentials.

Parent1.3.8, remaining physical/device and concurrency acceptance gates, and overall Phase1 remain open. No push approval inferred from this successful acceptance test.
