# Course/session contracts — milestone 2.0

2026-10-18. Metadata foundation for mobile-only administration. This document does not certify uploads, purchases or playback.

## Data and workflow

All enabled administrators with an admitted active device/session manage the shared academy catalog. A course has title, description, instructor display name, category, level/year, EGP price, display position and lifecycle state. A session belongs to one immutable course and adds a positive session number and a free-preview flag. Session numbers remain unique within their course, including soft-deleted sessions: restore preserves identity and numbering.

Prices use integer piasters, never floating-point money. UI accepts at most two decimal places; database integer bounds apply. Position is a nonnegative sort key, with UUID as deterministic tie-breaker. Lists use pages of 20 rather than a fixed business limit on courses/sessions. Concurrent edits currently use last-write-wins; optimistic version checks are a future improvement.

States: draft, published, archived. Soft deletion archives the item. Restore always returns it to draft, requiring deliberate publication. Deleting/archiving a course immediately hides its sessions from students without rewriting those sessions. Editing sessions of a deleted course is blocked until the course is restored. Permanent deletion is not granted to app clients.

## Security boundary

New tables have RLS and explicit column-level INSERT/UPDATE grants. Identity, creator, timestamps and session parent cannot be reassigned by clients. Server checks require an actual valid Auth session, enabled account, admitted active session and unrevoked registered installation; user-editable JWT metadata never grants admin rights. Only active students see published, nondeleted course/session metadata, with parent publication checked for sessions. Anonymous, disabled, revoked and ended-session access is denied.

Every content insert/update is audited atomically in the existing private event ledger. The audit records entity ID, action and lifecycle state, not descriptions, contact details or OAuth tokens. `private.is_admin` is an unexposed, restricted helper. Public table mutation remains subject to RLS.

No paid PDFs, attachments, private provider identifiers or playback URLs belong in these metadata tables. A zero price/free-preview flag alone does not grant material access. Future entitlements and playback endpoints must independently enforce access.

## Upload boundary / later milestones

The initial metadata increment constrained cover paths to NULL. The subsequent 2026-10-19 cover backend/service increment adds reserved course-scoped immutable PNG paths, active-admin upload policies, published-cover reads and bounded orphan cleanup (docs/COURSE_COVER_DESIGN.md). Attachments are server-validated; clients still cannot directly write cover_path. Storage checks MIME/size, while the client validates/normalizes decoded images; no server-side hostile image scanning is claimed. There is still no picker/preview/upload UI. Existing course-materials/payment-receipts/assignment-submissions buckets stay closed. No public bucket or arbitrary remote image URL is introduced.

## Exit checks

Database regression must prove admin CRUD/lifecycle/audit, student draft/archived/parent-hidden denial, student write/role escalation denial, anonymous and ended/revoked-session denial, exact prices/constraints and rollback fixture cleanup. Flutter checks cover validation, pagination, write errors and access-gate changes. Physical acceptance is separate from automated tests. Phase 1 email/recovery/logout/new-device acceptance stays open while these independent content steps progress.

Deployment evidence, 2026-10-18: hosted migration `20261018154932_phase2_content_core` applied successfully and mirrored locally. Content regression passed 130/130, identity regression 84/84; fixture cleanup confirmed. Local database is not running, so local migration-list verification was unavailable; hosted migration listing confirmed all three versions. No actual academy courses were seeded.

Security advisor retained four intentional private-table RLS/no-policy informational notices and reported leaked-password protection disabled in Auth. [Supabase documents that feature as Pro-plan-or-above](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection); no upgrade was authorized or performed. Record this limitation for release review.

Initial editor verification: 117 Flutter tests, analysis, locked dependency resolution, formatting (23 files, 0 changes), and configured Android debug APK build (32.4s) passed. The following lifecycle increment adds mobile recoverable delete/restore confirmation: deleted entries can be restored but not edited; restoration must return draft. Latest 146 app tests passed, covering lifecycle payload allowlists, returned-row checks, cancellation, access loss during confirmation/request, sanitized failures and narrow-phone layout. Cover uploads remain outside this increment. Physical Huawei editor/lifecycle acceptance is pending reconnection. An anonymous development REST request to courses returned 401; the SQL fixture suite is not a substitute for a signed-in user's real API/UI flow.

Performance advisor reported only [unused-index informational notices](https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index) for the new course/session order indexes on an empty catalog; retained for intended paginated access, not dropped merely because no production content exists yet.
