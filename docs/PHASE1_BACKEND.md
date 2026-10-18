# Phase 1 backend

Development project: `summit-academy-dev`, reference `ucbdgbspzvjinjpvxjdk`, Frankfurt, PostgreSQL 17. Free-only is authorized; no paid upgrade. The connector project listing does not expose billing status.

## Deployment and repository connection

The owner connected GitHub in Supabase. No preview branches or existing migrations were returned before setup. The exact integration/deployment settings were not exposed by the available connector. Do not enable paid branching or production deployment without approval. Migration `20261016060804_phase1_identity` was applied explicitly to development; its local version matches hosted history to avoid duplicate application by a future GitHub deployment. Pushes still require owner approval.

CLI version: `2.121.0` (`npx --yes supabase@2.121.0`). Connector authentication works; local CLI login is not configured. Never copy connector tokens or request secrets in chat. Local `config.toml` does NOT prove hosted Auth settings were changed.

## Authorization

- `public.profiles`: active verified users read/update only their own name, phone and university. No client role column, insertion, deletion or identity reassignment.
- `private.account_access`: server-controlled student/admin role, disabled flag and active session. User-editable metadata never grants authorization.
- `private.devices`: maximum two unrevoked installation tokens per user. Random 256-bit values stay in secure device storage; only hashes go into the database. This limits installations, not guaranteed physical hardware identity. Cloned/stolen tokens and compromised phones remain a limitation.
- `private.session_access`: one active application session. Owner confirmed BLOCK new login until current session logs out. A per-account row lock serializes device counts and login/logout. Ended sessions cannot reactivate themselves.
- Protected profile requests check actual Auth session existence, confirmation, ban, expiry, device revocation and account state. JWT validity alone is insufficient.
- Security-definer helpers are in unexposed `private`, verify callers and use empty search paths. Public RPC wrappers are security-invoker. Clients cannot directly read/write private tables.
- `course-materials`, `payment-receipts`, `assignment-submissions` buckets are private with no client policies. Upload/download stays denied until the corresponding feature defines access rules.
- Device self-service removal is not implemented. Lost-device recovery requires a verified administrator intervention; clarify replacement rules before implementing that flow.

RPCs `register_device(p_device_token,p_label)` and `get_access_context()` return `{role,device_id}`. `end_session()` ends only the caller's app session. Auth logout uses local scope: a blocked second login must not log out the active first session.

## First administrator

Owner selected `bolaakram123@gmail.com`. The app account must register and verify its email first; inspection found no app users. Provision through a trusted database session, never student metadata or an unauthenticated endpoint, and log the role change in `private.security_events`. Supabase organization membership alone grants no app role.

## Live setup and acceptance

Hosted email confirmation is enabled; Google is disabled. Owner needs Google Cloud OAuth and Gmail SMTP configured securely. Never put client secrets, SMTP passwords, database passwords or service-role keys in Flutter, Git, logs or chat.

Add exact hosted redirect `seaacademy-dev://auth/callback` before email/OAuth device acceptance. Use PKCE; test expired/replayed links, cold/warm launch and canceled OAuth. Production requires verified HTTPS links and final identifiers. Test Huawei Android 9 networking: Supabase announced obsolete TLS cipher removal on November 10, 2026.

From `app/`: `flutter run --dart-define-from-file=config/development.json`. That file contains only a public URL and publishable client key. Database authorization remains the security boundary.

## Advisors and verification

Initial security advisor returned only informational RLS-without-policy notices for four private tables: intentional deny-by-default, not missing client grants. [Advisor explanation](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy). Two initially unused session-table indexes are retained for user/device foreign-key lookups as traffic begins.

Phase completion requires Flutter/database tests plus live registration, email verification/recovery, Google login, verified admin provisioning and device/session acceptance evidence. SQL fixtures do not prove email delivery or OAuth. iOS execution requires macOS and remains unverified here.
