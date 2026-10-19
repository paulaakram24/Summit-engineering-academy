# Phase 2 private course covers — database regression

Suite: `supabase/tests/phase2_covers.sql`. Migration: `supabase/migrations/20261019015308_phase2_private_covers.sql`, following identity and content core. This increment tests the cover service/database boundary; it does not deliver a picker or cover UI.

Subsequent integration checkpoint, 2026-10-19: picker/private-preview UI is now implemented and administrator real-binary selection/restart/replacement/removal/cleanup passed on Huawei. See PHASE2_DEVICE_ACCEPTANCE.md for scoped evidence and cleanup. Historical suite results below are unchanged; they do not independently establish the physical result.

## Verification evidence

On 2026-10-19, main reported combined hosted atomic rollback preflight results: **covers PASS 53/53, identity PASS 84/84, content PASS 130/130**. Main then applied the cover migration as hosted version `20261019015308` and aligned its local filename. Final deployed runs also passed **covers 53/53, identity 84/84 and content 130/130**. Main independently read back zero reserved fixture users, zero courses, zero cover assets and zero cover objects against the known globally empty catalog/bucket baseline; this cleanup evidence does not depend on joining objects to deleted course fixtures. An anonymous HTTP prepare RPC request returned **401**. These runtime and HTTP results were executed and reported by main, not the suite author.

The suite author performed static review only: 53 unique assertion names, 53 paired embedded-query delimiters, transaction boundaries and diff checks. The reserved-course cleanup readback was strengthened to use fixed object prefixes rather than looking up course rows after rollback. Main owns execution and final cleanup confirmation; no external database writes, deployment or owner-state changes were performed by the suite author.

Main also reported 171 Flutter tests passed, clean analysis, format verification across 25 Dart files with zero changes, and an Android build pass (36.5 seconds). Those results are separate application evidence, not proof of binary upload/download/deletion, picker behavior or physical cover acceptance. Main reported five intentional private-schema informational notices plus the existing disabled Auth leaked-password-protection warning. No paid setting or policy was changed to suppress it.

## Run and interpret

Run the suite on development through one privileged connection as one complete query. Do not submit role changes, fixture setup or assertions as independent calls. The script starts with `BEGIN`, sets local statement/lock timeouts and RLS, clears legacy JWT claim settings, and supplies fictional claims under `SET LOCAL ROLE authenticated` or `anon` for the operations under test. Privileged setup/readback uses `RESET ROLE`.

Require `phase2_covers_report` immediately before `ROLLBACK`, with `status=PASS`, `passed=53`, `expected=53` and all named results. An empty result or absence of an error is not a pass. Some tools expose only the last SELECT: submit through `ROLLBACK;` to retrieve the report, then run the post-rollback cleanup SELECT separately. Never remove rollback or commit fixtures to obtain the report.

For migration preflight, main combines one outer `BEGIN`, the new migration body and the suite body after its opening `BEGIN`, ending at `ROLLBACK`. This rolls back schema and fixtures together. The cleanup SELECT references only pre-existing tables and remains valid after the cover migration is rolled back. Run all three suites as independent transactions; the identity/content suite temporary helpers need not coexist with this suite's helpers.

If a test fails, record the exception as failure. A persistent client that stops processing after an error must issue `ROLLBACK` on that same connection or disconnect before reuse. Do not commit partially completed fixtures.

## Coverage and expected outcomes

- Bucket configuration is private, PNG-only, maximum 3,145,728 bytes. The reservation ledger records course-scoped UUID PNG paths, fixture creator and upload state. Five simultaneous unexpired reservations cap preparation.
- Storage has exactly the three named `course_covers_read`, `course_covers_insert` and `course_covers_delete` policies, limited to authenticated callers, the cover bucket and their corresponding helper actions. There is no UPDATE policy. An authenticated UPDATE of a visible fixture object returns zero rows; no overwrite/upsert authorization is inferred from INSERT alone.
- Only the active reservation owner administrator is insert-authorized. Unreserved paths, another active administrator and students fail INSERT. All five RPCs reject students despite forged user metadata, and the anonymous role lacks EXECUTE grants. Direct reservation-ledger reads and course cover-path updates are denied.
- Missing object metadata, JPEG MIME and an oversized PNG cannot attach. Valid PNG metadata at one byte and at the maximum attaches. These are seeded database metadata rows, not evidence that image bytes are valid or Storage HTTP MIME/size enforcement was exercised.
- Students read only the current attached cover of a published, nondeleted course; draft, unattached and retired objects stay hidden. Replacement uses compare-and-swap: a stale expected reference raises `40001 / cover_changed`, and a correct expected reference attaches the replacement.
- Retrying the same attachment with the original expected NULL succeeds without another content mutation/audit. Abandoning an attached asset leaves it attached and creates no abandonment event. Actual abandonment and cleanup completion each audit only once on repeated calls.
- Abandoned, retired and cleaned reservations cannot attach again. Retirement removes upload authorization. Cleanup completion fails while object metadata remains. A late object seeded at a cleaned tombstone is relisted and delete-authorized, but stays non-uploadable and non-attachable.
- Expired uploading reservations lose insertion rights, are retired by cleanup listing and receive one expiry event. Listing is asserted bounded to 20 entries; this fixture tests one expired reservation, not exhaustion of a 21-plus-item stale batch.
- Real fixture Auth-session expiration and device revocation remove all read/insert/delete helper permissions and hide the objects; preparation then raises `42501 / admin_required`. Clearing a course reference retires its previous cover and protects no longer attached objects for cleanup.

The helpers are SECURITY INVOKER. `check_true` requires exactly one boolean result with `INTO STRICT` and rejects false or NULL. `expect_error` catches only the tested statement, then compares SQLSTATE and the complete message outside the handler. Helper-generated failures cannot be swallowed as expected errors. Void RPC calls used for setup are followed by state/audit assertions; a successful void return alone is not treated as a state assertion.

## Storage DELETE boundary

Supabase's platform `storage.protect_delete()` rejects direct SQL DELETE. This suite does not bypass it, disable triggers, change Storage configuration flags or pretend that SQL deletion exercises the Storage API. Cover cleanup authorization is proved by policy inspection and `private.cover_storage_allowed(path,'delete')`: attached/current or uploading paths are false, and unreferenced retired/cleaned paths are true for an active admin. Students and invalid sessions get false.

Actual object deletion through the Storage API remains a separate integration gate. The SQL suite seeds object metadata only under the privileged role inside the transaction, before attachment validation or as an explicitly simulated late arrival at a cleaned tombstone. It never deletes object rows or uploads binary files.

## Fixture isolation and cleanup

Reserved fictional users use prefix `f2c0e200-0000-4000-8000-` with suffixes `000000000001`, `000000000002`, `000000000003`; Auth sessions end in `000000000101`–`000000000103`. Server role grants affect only fixture administrators 1 and 3; fixture 2 remains a student. Emails use `example.invalid`. Plain INSERT aborts on a collision; there are no identity upserts.

Fixture courses use the fixed reserved IDs ending `000000000201` and `000000000202`. They are inserted only during privileged fixture setup, retaining admitted fixture-admin JWT claims for the content audit trigger. Generated cover paths are mapped in a temporary table and always use those course prefixes. Auth/session/device changes target only reserved fixtures. The owner account is never selected for mutation.

Rollback removes all inserted fixture rows, reservations, audits, helpers and temporary tables. The final read-only query checks reserved users, Auth sessions, courses, audit actors and Storage object prefixes. The object check uses the fixed course UUID prefixes directly, so it does not become vacuously zero after course rows disappear. Require all returned counts to be zero. After deployment main can additionally inspect the private cover ledger by the reserved creator IDs; that new table does not exist after a migration preflight rollback. Main may also compare whole-catalog/bucket counts to its known empty baseline.

Audit identity sequences can advance despite rollback; gaps are expected and must not be reset. Existing external trigger/webhook effects, if any, require runner review. This suite neither cleans unrelated objects nor certifies a general orphan-cleanup service.

## Existing-suite compatibility and remaining gates

Only the no-policy assertions in `phase1_identity.sql` and `phase2_content.sql` were changed: they reject every Storage object policy except the three named cover policies. Identity's original private course-materials, payment-receipts and assignment-submissions SELECT/UPDATE/INSERT denials and platform DELETE denials remain unchanged. Existing assertion totals remain 84 and 130. The new cover suite separately requires all three policies with the expected scope and command; allowing names in older suites is not permission to broaden their definitions.

No actionable migration defect was identified in this scoped static review. This is regression correctness/RLS verification, not a full security scan. Binary image validation, Storage HTTP upload/download/delete, signed URL behavior, policy concurrency interleavings, UI/picker flows and physical acceptance are not certified. Supabase/Postgres guidance informed role isolation, metadata-role rejection, grant-versus-RLS checks and the no-upsert boundary. Reference: [Supabase Storage access control](https://supabase.com/docs/guides/storage/security/access-control).
