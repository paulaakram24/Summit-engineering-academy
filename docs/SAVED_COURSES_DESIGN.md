# Saved courses — implementation and acceptance

2026-10-20. Backend Architect implemented the database boundary; Mobile App Builder implemented the Flutter transport/UI/tests; Mobile Release Engineer reviewed the patch read-only. Main integrated and verified the work. Development migration `20261020132830_phase2_bookmarks` is deployed and runtime injection is enabled locally. This is a partially accepted development feature, not completion of bookmarks, My Learning or commerce. The existing published catalog remains authoritative.

## Scope

Save/remove course references and list them under Saved courses. Initial scope is courses, not session timestamps or playback positions. Explain: “Saved for later—not purchased or enrolled.” Never merge bookmarks into My Learning ownership or use them to grant protected delivery. Course-only scope is the proposed first increment, not a claim that all bookmark features are complete.

## Implementation sequence

1. Freeze a typed contract and denial matrix, then implement and verify the server boundary.
2. Implement actor-bound client transport and strict projection parsing against the verified contract.
3. Add detail save/remove control and a paginated Saved courses view, then wire existing authenticated navigation.
4. Run existing regressions and new backend/client/widget checks, build the debug artifact and perform authorized native acceptance. Request fresh approval before pushing that future milestone.

Do not build a local-only save switch pretending to synchronize, or call an undeployed endpoint from the current app. Keep the public catalog projection unchanged and avoid new packages or native configuration unless necessary and reviewed.

## Frozen implementation contract — acceptance pending

The implementation keeps references when a course becomes unavailable, as a non-destructive technical default. Only currently published, nondeleted metadata may be returned; keeping a reference never preserves hidden descriptions, covers or paid access. The server supports removal with a previously known revision, including when unavailable. Hidden-reference management after restart is not yet implemented: get/list hide the reference and its revision, so the current UI cannot recover it for removal. Keep a future metadata-free management/recovery flow open; never guess revisions or weaken visibility/CAS to fill this gap. No purchase/grant state is involved.

RPC shapes agreed between the Backend Architect and Mobile App Builder:

- `get_course_bookmark(p_course_id uuid)` returns exactly `{course_id, saved, revision}`, or null for unavailable/missing courses, including for admins. A published course with no prior state returns false/revision 0.
- `set_course_bookmark(p_course_id uuid, p_saved boolean, p_expected_revision integer)` returns exactly `{course_id, saved, revision}`. Saving requires a published nondeleted course. Removing is owner-scoped and writes a false tombstone even for hidden/missing UUIDs without revealing existence. A successful request advances the current revision (integer 0..2147483647); compare-and-set rejects a stale expected revision. Requests are desired-state operations, not toggle or automatic retry. A duplicate stale request may conflict, but cannot duplicate or resurrect a save.
- `list_saved_courses(p_after_position integer, p_after_id uuid, p_limit integer)` returns the existing strict catalog course page shape, ordered by catalog position/UUID, default 20/max 50.
- Failures: `42501/bookmark_access_required`, `22023/invalid_bookmark_input`, `42501/bookmark_course_unavailable` and `42501/bookmark_state_conflict`. Conflict/uncertain outcome requires a fresh state read before another explicit user action. No endpoint accepts an owner ID as authority.

Versioning is required because a timed-out Save may still arrive after a later Remove. Serialize changes to each account/course row and compare the captured revision; retain false tombstones so returning to unsaved does not reset the revision (ABA). Do not grant clients DELETE on the tombstone store. Unknown UUID removals have the same state transitions as hidden UUID removals; therefore the tombstone course UUID intentionally has no course FK, while saved=true requires a currently published parent through both RPC and RLS checks. No orphan saved record can become metadata or access by itself. The owner FK remains constrained/indexed. This exception is a deliberate non-disclosure/concurrency boundary, not an omission of FK review.

Deployment and automated evidence are recorded below. Native populated and actual student acceptance remain separate gates.

- Derive the actor from the admitted authenticated session, never a client-supplied owner ID. Admin accounts may save for themselves but gain no cross-user bookmark visibility.
- Store one unique actor/course reference. Retain restrictive historical relationships and avoid cascading changes to purchase/grant records.
- Use explicit desired-state save/remove plus revision checks, not a retry-sensitive toggle. Duplicate identical requests must not create duplicate rows. A stale duplicate requires refetch, never an automatic write replay. No client writes to ownership/entitlements.
- List only published, nondeleted catalog metadata, with default 20/max 50 rows and stable keyset ordering. Filter availability before pagination/lookahead; no hidden title, description, cover path or outline in bookmark projections.
- Suggested first sort is the catalog's position/UUID ordering, reusing its cursor/parser invariants. It is not a fabricated “recently saved” or purchase-date sort.
- Retaining an unavailable course's bookmark must not preserve a client-side metadata snapshot or override publication checks. Any later visibility follows current catalog availability and is never paid-access restoration. Retain only the reference under the non-destructive technical default above; no content or access entitlement is retained by bookmarking.
- An exact-course save state read returns only the current actor's state under the same availability/admission boundary. Removal of the actor's own retained reference must remain possible without exposing hidden metadata.
- Keep storage privileges private and RLS/admission checks explicit. Public wrappers must not weaken existing catalog, material or Storage policies. Use the project's existing narrow privilege conventions and review any privileged helper independently.

## Client integration paths

- `app/lib/bookmarks/bookmark_repository.dart`: injected typed state/page/failure contract.
- `app/lib/bookmarks/supabase_bookmark_repository.dart`: pinned actor/token transport with strict response validation and safe failures.
- `app/lib/catalog/catalog_screen.dart` with `savedOnly: true`: reused accessible loading/error/empty/list/pagination and safe detail navigation; no separate saved_courses_screen.dart was needed.
- `app/lib/catalog/catalog_screen.dart`: save control only after verified state, with no invented success on timeout.
- `app/lib/main.dart` and `app/lib/auth/auth_panel.dart`: dependency construction and authenticated Saved courses entry.
- A CLI-generated migration and `supabase/tests/phase2_bookmarks.sql`: do not invent migration timestamps or mark deployment complete from a local file.

Use the existing catalog's account/lifecycle boundary patterns. Drop stale replies after account changes, background closure and disposal. An uncertain mutation result requires refetch before another action; do not silently queue or replay it under a different account. Clear cached saved metadata when access closes or publication withdrawal is confirmed.

## Required evidence before completion

- Backend: anonymous/inactive/cross-user denial, forged owner rejection, unique saves, duplicate stale revision rejection, explicit removals/false tombstones, delayed old-save versus newer-remove rejection, unpublished parent exclusion, pagination after availability filtering and fixture cleanup. Use rollback fixtures, not the owner's account. Sequential stale-revision tests are not evidence of real parallel transaction testing.
- Client: strict field/cursor validation, token pinning, old-account responses, timeout/uncertain result recovery, duplicate taps, disposal/background closure and hidden-course invalidation.
- UI: saved/not-saved semantics, loading/error/empty states, live status updates and narrow/large-text layouts. No payment or enrollment labels.
- Device: actual user-controlled login, save/remove, restart persistence, later-page navigation, withdrawal behavior and real accessibility checks within authorized synthetic-content scope. Never fabricate a student session or alter the owner's role for acceptance.

Full My Learning, owned-course/session grouping, payment states and protected learning still depend on Phase 3/4. This slice must not close their roadmap checkboxes.

## Verification checkpoint

- Exact migration SHA-256: BFDAEE308890EE2B65DBB4450635A7E9C5560C92B7F8287494D54D4D0CF432C3. CLI-generated local migration name was aligned with the actual hosted history version returned by deployment; no timestamp was invented.
- Baseline six hosted rollback suites passed 631 assertions. The exact additive migration then passed those same suites in schema-plus-fixture rollback trials, plus 84 new bookmark assertions with enforced expected-count guard: 715 total. After actual deployment, all seven suites passed again, 715 total. SQL fixtures rolled back; readback found zero reserved users/bookmarks/courses and zero published courses.
- The first composed preflight runner had a dollar-quoting replacement issue; it was corrected without schema deployment. The first new suite execution exposed an invalid nested data-modifying CTE; main moved it to query top level, enforced the independently derived 84-count guard and reran successfully. Negative client fixtures were corrected to isolate one malformed field rather than fail merely because revision was absent.
- Main full Flutter runs passed 561 tests (487 existing + 74 new). Agent focused evidence: 17 model, 33 transport and 24 widget tests; another 63 existing scoped regressions. Exact revision acknowledgment, stale account replies, uncertain mutation/refetch, hidden withdrawal, saved pagination, dependency changes, lifecycle closure and narrow/large-text semantics are covered in tests, not necessarily on a device.
- Initial configured Android build passed in 22.4s; final formatted-source verification passed analysis, 561 tests, 55-file zero-change formatting and debug build (40.8s). Final APK 189069343 bytes, SHA-256 8EC6FFE729A61094CEF6578E4B74CF7A18E3BB2F05F44A4275DF0FC7C8A04A2F, installed/hash-matched on emulator-5554. Existing Administrator home, Saved courses empty state, background clearing and fresh reopen accepted; no populated save/restart persistence claim. See PHASE2_DEVICE_ACCEPTANCE.md. No new dependency or native configuration was added. Runtime injection was enabled only after deployed backend checks passed.
- Anonymous real HTTP get_course_bookmark probe with the existing publishable key and no user session returned 401/42501 permission denied, as expected. No credential, key or token was printed.
- Security advisors match the prior baseline: seven intentionally closed private RLS-table INFO notices and the existing leaked-password protection WARN. Performance adds one unused new course-reference index INFO; retain it for indexed lookup rather than remove it to silence development telemetry. Existing material-payload composite-FK and unused-index INFO notices persist. See [RLS advisor explanation](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy), [password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection), [index advisor](https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index). No paid settings or unrelated grants/indexes were changed.
- Supabase/Postgres guidance shaped owner-scoped RLS, invoker functions, explicit privileges, narrow projections, indexed lookup and row-serialized revision checks. These are bounded engineering checks, not a full security audit.

Open: usable hidden-reference management after restart; real parallel-transaction race evidence (sequential stale-revision checks are not that); populated native save/remove/restart/student/TalkBack/Huawei/iOS/release acceptance; production signing/distribution. No new push has been approved for this increment.
