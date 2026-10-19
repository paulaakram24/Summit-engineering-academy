# Phase 2 content checkpoint — independent audit handoff

Prepared 2026-10-19. This is an audit request, **not an executed Claude Code audit** and not Phase 2/release completion. Read the latest PROJECT_STATUS.md before reviewing: cover UI work and evidence can advance after this handoff was prepared. Claude Code was not found on this session's command path; no account, subscription or installation was changed.

## Review scope and baseline

Read ROADMAP.md, REQUIREMENTS_CORRECTIONS.md, docs/CONTENT_CONTRACT.md, docs/COURSE_COVER_DESIGN.md, docs/PHASE2_COVERS.md and docs/PHASE2_DEVICE_ACCEPTANCE.md. Compare the working tree against last pushed checkpoint `2e08f0ff1a98e7e2b646d699bac945bffe5e8d88`, including **untracked files**, not just Git's tracked diff. Do not edit, commit, push, publish content, alter accounts/roles or mutate a hosted database during review.

Key implementation paths:

- `app/lib/content/`: models, authenticated metadata repository, administrator workspace/lifecycle, cover service, selector and private preview controls.
- `app/lib/auth/auth_panel.dart` and `app/lib/main.dart`: role-gated entry and application lifecycle integration.
- `supabase/migrations/20261018154932_phase2_content_core.sql` and `20261019015308_phase2_private_covers.sql`.
- New admin-only material migration `20261019154009_phase2_admin_materials.sql`, `supabase/tests/phase2_materials.sql`, `docs/PHASE2_MATERIALS.md` and client `*material*` models/repository/tests. Review originating-actor request binding, exact retry behavior, stale revisions and safe metadata versus protected payloads; no material UI or student delivery exists yet.
- `supabase/tests/phase1_identity.sql`, `phase2_content.sql`, `phase2_covers.sql`, plus `app/test/*content*`, `*cover*` and `admin_entrypoint_test.dart`.
- `.github/workflows/backend-checks.yml`, dependency manifest/lockfile and iOS picker purpose string, if included in the current tree.

## Required questions

1. Are admin mutations and private storage reads/writes governed by a valid Auth session, enabled server-controlled role, admitted installation and active application session, without trusting editable metadata? Can direct REST/Storage calls bypass Flutter gates?
2. Do column grants, RLS, triggers and RPC wrappers prevent student writes, cross-course reassignment, creator/identity changes, direct cover-path changes and session edits beneath a deleted parent? Are privilege-bearing functions unexposed/restricted with fixed search paths?
3. Does restore always return draft, with deleted/archived parents hiding children? Distinguish actual device evidence from SQL fixtures and planned student UI.
4. Are exact integer-piaster prices, session numbering uniqueness, pagination bounds and server-returned write confirmations correct? Inspect timeout/lost-response behavior before recommending a retry.
5. Can a reserved immutable cover be overwritten, attached after retirement, deleted while referenced, or claimed by another admin? Trace attach/cleanup serialization, idempotency, expiry and retained tombstones. Identify untested concurrency assumptions explicitly.
6. Does the system picker expose only the selected file, bound input before decoding, reject unsupported/animated/oversized images, discard interrupted selections safely, and revalidate access after returning? Do backgrounding, disposal, role/session changes and delayed callbacks clear protected previews and prevent stale UI installation?
7. Do replacement/removal/cleanup handle uncertain outcomes safely without deleting a possibly attached file? Does cleanup remain bounded and explicit, and preserve unrelated unsaved work on failure?
8. Are private image downloads JWT-authenticated rather than public/signed bearer URLs? Check cache lifetime and preview eviction. Do not infer paid-material access from cover visibility/free-preview flags.
9. Are native permissions/purpose strings minimal and dependencies pinned/locked? Check small-screen, large-font, keyboard, loading/error/cancel behavior and process death. Do not claim iOS acceptance from source inspection.

## Evidence and limits

Subsequent main checkpoint: administrator cover binary workflow accepted on Huawei; materials schema deployed to development and 163 material assertions plus the prior 267 database assertions passed (430 total), with fixture cleanup confirmed. Initial material client brought app tests to 285 with clean analysis and configured Android build (55.0s); originating-actor retry correction remains subject to fresh tests. Use latest status for post-correction results, not this historical count.

The pre-picker checkpoint passed 171 app tests, clean analysis, configured debug Android build, and 267 hosted rollback assertions (84 identity, 130 content, 53 covers). Fresh picker UI totals belong in PROJECT_STATUS.md; historical counts are not proof of new code. Physical Huawei administrator metadata/lifecycle acceptance used explicitly authorized temporary draft content and final recoverable deletion, with exact price and audit readback. It was never published.

SQL suites seed object metadata only; they do not establish actual binary upload/download/delete. Look for separately recorded real Storage/phone evidence. Existing known limits include last-write-wins metadata edits, untested complete concurrency interleavings, open identity email/recovery/device gates, no iOS runtime test, disabled leaked-password protection on the selected free tier, and no release-signed distribution acceptance. PDFs, payment receipts, assignments and paid video remain outside current cover access grants.

## Report format

For each actionable issue provide severity, verified file/line, concrete source-to-effect path, exploit/reproduction prerequisites, impact, minimal recommended fix and regression test. Separate demonstrated issues, hypotheses requiring runtime checks, and nonblocking improvements. Do not silently rewrite implementation or broaden permissions. Never request or print secrets, contact data, session tokens or full OAuth URLs. Codex will triage findings, implement justified fixes, run regressions and update status before requesting fresh push approval.
