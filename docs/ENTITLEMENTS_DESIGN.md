# Entitlements and access states — milestone 3.1 design

2026-10-20. Proposed implementation contract for later 2.4.3/2.5 and phase 3 integration. **Documentation only: no entitlement schema, API, client behavior or deployment is delivered here.** Existing catalog reads and admin-only material boundaries remain authoritative. The reported catalog/database/app/device passes establish their respective existing features, not payment or entitlement acceptance. Pending permission to publish temporary acceptance content is not granted by this document.

## Authority and fixed rules

`REQUIREMENTS_CORRECTIONS.md` overrides the older expiry wording in `MASTER_BUILD_PROMPT.md`. Follow ROADMAP 3.1–3.6 and `docs/STUDENT_EXPERIENCE.md`:

- One-time EGP purchases support a whole course or an individual session. Money remains integer piasters, consistent with existing course/session prices. No subscription, wallet, simulated balance, Stripe or automatic gateway confirmation is introduced.
- Purchased access begins at the **server-recorded administrator payment approval**, not order creation, receipt upload, transfer reference, first playback or a client clock. It has **no automatic time expiry** and remains usable while the session is available, until authorized removal.
- An active whole-course grant covers existing and future sessions belonging to that course when they are published and otherwise available. Resolve membership dynamically through the existing immutable session `course_id`; do not freeze the session list at purchase or issue duplicate grants whenever a session publishes.
- A session grant covers exactly its immutable session UUID. It creates no course enrollment/full-course ownership and grants no sibling or future-session access. Replacing removed content with a new session UUID does not silently transfer an individual-session purchase.
- Owner clarified 2026-10-20: bundles have editable admin/instructor-selected sessions and one EGP price. Membership additions/removals apply to both existing buyers and new buyers; future sessions are excluded until explicitly selected. Preserve immutable purchase-time membership/price snapshots and audited membership revisions. Resolve current bundle coverage from current membership, not only the purchase snapshot. A membership removal ends only that bundle's coverage; independent valid grants remain separately evaluated. Additions cannot bypass availability or post-removal admin-regrant requirements. Admins currently perform instructor duties; no new role is introduced.
- Owner confirmed 2026-10-20: admins review and record refunds; money is returned manually outside SEA through InstaPay/Vodafone Cash. No automatic funds movement. Eligibility, partial amounts and access consequences remain separate unresolved transitions.
- Content removal, grant revocation and purchase history are separate facts. Archiving/soft deletion must preserve orders, decisions and grants. Restoring course/session content returns it to draft; restoration alone never makes it student-available.
- Roles remain **Admin** and **Student**. Admins currently perform instructor duties; no Instructor role or new authorization claim is added. Admin authoring privileges do not imply personal ownership in the student library.

## Separate grant, availability and delivery

For a requested session, evaluate these dimensions independently using server state:

| Dimension | Required meaning |
| --- | --- |
| Identity/admission | Existing `private.is_active()`: confirmed, enabled, nonanonymous account, valid Auth session, active application admission and unrevoked device. JWT user metadata is not role authority. |
| Grant coverage | An issued, nonrevoked course/session/bundle grant covering this session, with server approval start reached, and any required post-removal admin regrant satisfied. No business `expires_at`, duration or renewal rule is inferred. |
| Availability | Course and session are published and nondeleted. Later material resolution also checks material/resource lifecycle. A valid grant cannot override a hidden parent. |
| Delivery readiness | Protected asset is configured, clean/ready, permitted for the requested action, and its delivery integration exists. Ownership does not make an unimplemented player or placeholder deliverable. |

Paid delivery requires **all four**, rechecked by the server for each capability request. Technical Auth/capability expiration is separate from the absence of business expiry. Free previews are a separate explicit server-authorized route: zero price or `is_free_preview` alone never grants paid access. Until preview/delivery policy is implemented, metadata may describe the authored preview designation but cannot promise playback.

Removal immediately makes subsequent authorization checks unavailable without deleting the grant. Hidden content is absent from catalog/discovery; only its purchaser's minimal historical snapshot may remain in their library/history. Do not reveal newly authored draft descriptions, hidden outlines or material payloads through purchase history. Owner rejected automatic reactivation on 2026-10-20: explicit republication of the same UUID does not resume old paid access. A fresh explicit, audited administrator grant is required for the affected content. Preserve the original purchase/source history; no second purchase/payment is implied. Existing course, session or bundle grants cannot bypass this restoration gate. The future implementation must distinguish first publication (including a newly added course session) from republication after removal, and record the relevant removal/regrant scope durably. This is a resolver invariant, not an implemented generation/regrant schema.

## Proposed persistence and access boundary

Names are proposals for phase 3, not existing tables or migrations. Prefer private-schema storage with RLS and revoked client table privileges; expose purpose-specific, allowlisted projections. Do not weaken existing catalog/material RLS to read commerce data.

| Proposed record | Minimum invariant |
| --- | --- |
| Order + immutable items | Buyer UUID, one-time EGP amount, server price/title snapshot and exact course/session/bundle scope; session item retains validated parent course. Bundle item retains original membership snapshot/revision for history, not frozen ongoing coverage. No client-set price, approval, buyer reassignment or arbitrary product URL. |
| Bundle + membership revisions | Stable bundle identity, authorized admin-selected session membership and audited additions/removals. Current membership determines bundle coverage for existing and new buyers; immutable purchase snapshots remain intact. Membership edits must be atomic and trigger access-state refresh/revalidation. |
| Payment submission | Order FK, submitting owner, review state, private evidence reference and protected transfer details. Screenshot/reference is evidence to inspect, never proof that money arrived. |
| Payment decision | Order/submission, authorized admin, approved/rejected outcome, server decision time and protected note; immutable terminal decision history. Resubmission/reopening rules require a defined transition before implementation. |
| Access grant | Beneficiary, exactly one course, session or bundle target, immutable source item/decision, `starts_at=approved_at`, nullable revocation time/actor/reason. Bundle coverage resolves current membership; do not materialize permanent session grants that survive membership removal. Source provenance distinguishes purchase, later cash record and explicit manual grant. |
| Operation ledger + security audit | Actor-scoped operation UUID and request digest, unique transition identity, safe result IDs; audit retains actor, target, decision, scope and timestamps without receipt paths, transfer details or secrets. |

Use restrictive FKs/soft deletion for history, not cascading purchase deletion when content disappears. Enforce exactly-one scope and source consistency in constraints plus the approval transaction. A unique source-item-to-purchase-grant relation prevents duplicate issuance; do not impose one-ever-purchase-per-user/session without a duplicate-purchase business rule. Index buyer/history ordering, grant beneficiary/target/revocation lookups and all relevant FK paths. Bound paginated history reads; no fixed business course/session cap.

Students can read only their own safe order/payment status and library projection under active admission. Internal notes, reconciliation evidence and other students' receipts stay private. Admin review requires `private.is_admin()`. Public wrappers should use SECURITY INVOKER; any required privileged transaction/projection helper stays private, has an empty search path, fully qualified references, explicit authorization and narrowly granted execution. Revoke default PUBLIC/anonymous function execution. Do not replace permission failures with broad grants or use a default definer view.

Suggested later API responsibilities: server-priced order creation for the current buyer; private evidence submission; admin approve/reject; own order/history/library reads; batched own session access-state reads; explicit audited grant/revoke/manual-cash operations. These are responsibilities, not agreed consumer signatures. A student endpoint derives the beneficiary from `auth.uid()`; an admin-only endpoint may accept a beneficiary after authorization. Reads return no playback URLs, private link targets, assignment bodies or storage/provider identifiers.

## Approval transaction: one committed decision and audit

1. Require an admitted enabled Admin. Independently verify the actual payment record through the authorized manual process; a receipt upload, client assertion or matching amount alone cannot approve. A trusted Edge Function may validate requests and orchestrate review, but database constraints/transaction remain authoritative. Keep reconciliation/network calls outside database locks.
2. Bind an operation UUID to actor and full request digest. Lock the operation, order, payment submission and affected grant/source rows in a documented consistent order. Recheck order beneficiary, immutable item scope/price snapshot, evidence association and allowed decision state after locks. Define content-unavailable-at-approval behavior before enabling approvals; never grant siblings or rewrite purchased scope to compensate.
3. Atomically record approval time, terminal decision, approved order state and exactly one purchase grant per item with that same start time. Record **one approval audit event per committed decision**, containing safe order/decision/grant IDs and actor. Any required subsidiary event must also have a unique transition key; retries cannot duplicate it. Failure of grant insertion or audit rolls back the entire decision.
4. Same operation/same input returns the original decision identity after current authorization checks; changed input fails. A different operation racing to approve an already approved order returns/conflicts against the existing decision without new grants/audit. Concurrent approve/reject allows one terminal outcome; no success response before commit. Reconcile an uncertain response by refetching current order/access state before new action.
5. Rejecting or leaving a request pending issues **zero** grants. Approval grants access but never claims a refund, external funds movement, receipt validity beyond actual review, or successful protected delivery. Notification delivery follows commit and is retryable/idempotent; notification failure cannot create or repeat approval.

Cash purchases and manual grants are authorized requirements but need separate admin-only commands with explicit source, beneficiary, reason and audit; they must not masquerade as student-submitted verified transfers. Their no-automatic-expiry behavior should reuse the same grant/availability resolver. Admin purchase eligibility and self-approval remain unresolved business choices; implement no implicit self-approval exception or new reviewer role.

## 2.4.3 state projection and 2.5 library

Return orthogonal safe facts such as `ownership_scope` (course/session/bundle/none), `content_available`, own `payment_state`, `preview_designated` and `delivery_ready`; derive paid eligibility server-side. A UI label is not a capability. While commerce is unimplemented, show no invented pending/approved/owned facts; missing backend state is an integration/error state, not evidence that the user has no purchases.

| Situation | Label / behavior |
| --- | --- |
| Valid grant + published content | Available by entitlement; enable a protected action only when its delivery service authorizes it. |
| No covering grant + own pending request | Payment pending; no paid access. If another valid grant already covers the item, pending must not replace its available state. |
| No grant and no pending request | Locked. Rejected payment may be shown in own order history; it does not unlock or erase an independent grant. |
| Published explicit preview designation | Free preview designation; actual preview action remains gated by implemented server preview policy. It does not imply whole-session ownership. |
| Historical purchase + removed/archived/draft parent | Unavailable; preserve purchase history, avoid expiry language, and expose no hidden current catalog details. |
| Historical purchase + republished content without fresh admin regrant | Access requires admin regrant; no paid delivery and no automatic new-payment demand. Republishing alone cannot revive old course/session/bundle coverage. |
| Invalid admission, other beneficiary or unknown private resource | Deny; clear stale account data. Do not convert authorization failure into an empty library or disclose whether another buyer has a grant. |

Library views distinguish Full courses and Individual sessions; an All learning grouping may group cards without promoting partial ownership or losing item-level provenance. Course ownership includes future published sessions dynamically. Multiple session purchases do not synthesize course enrollment. Overlapping course/session purchases retain both historical items but should not duplicate the same learning card. Pending orders are separate from approved learning; use server approval timestamps for recent sorting. Clear caches and discard delayed replies after account/admission changes; refresh after approval, restart, removal or revocation.

## Required denial and integrity matrix — future tests

No test below was implemented or executed for this document.

| Scenario | Required result |
| --- | --- |
| Anonymous, forged-role student, disabled/banned/unverified account, missing/expired Auth session, ended/revoked admission | Deny privileged review and protected delivery; active students can read only their own allowed projections. |
| Pending, uploaded receipt, rejected order, fabricated local approval, zero price | No purchase grant or paid capability. Existing independent grants remain unaffected. |
| Tampered amount/buyer/item, another order's evidence, reused transfer proof | Reject/hold under defined reconciliation rules; no unauthorized grant, no evidence leak. |
| Same approval retry; concurrent separate approval requests | One terminal approval, one grant per item, one approval audit; changed operation payload rejected. |
| Concurrent approve/reject; audit/grant insertion failure | One terminal result or complete rollback; no approved-without-grant / grant-without-decision state. |
| Individual-session purchase | Target only; no sibling, future session or course enrollment. |
| Course purchase followed by a newly published session | Same course grant covers it without a second payment/grant; draft/archived/deleted sessions stay unavailable. |
| Approval start and passage of time | Before approval deny; at approval grant starts. Advancing the business clock alone never expires the grant. Technical session expiry still denies until valid readmission. |
| Session/course removal; restore to draft; republication | Immediately deny new delivery; retain source/grant/history. Neither restore nor republication unlocks prior paid access. Fresh explicit audited admin grant is required; an old overlapping course/bundle/session grant must not bypass the removal barrier. |
| Editable bundle and later session creation/edit | For existing and new buyers alike, current bundle coverage includes explicitly added sessions and excludes removed members. Newly created unselected sessions stay excluded. Preserve immutable purchase membership/price snapshots and audited revisions. Independent valid grants survive membership removal; availability and post-removal admin-regrant gates still apply. |
| Refund review/history versus actual funds movement | Only authorized admins review/record decisions; no automatic transfer or fabricated returned-money claim. Gate refund eligibility, partial amounts and access changes until defined. |
| Grant revocation with overlapping course/session/manual sources | Enforce the selected source/scope precedence exactly; gate implementation until defined, never erase purchase history. |
| Another buyer's order/library/receipt ID; old-account response | Deny cross-user access and drop delayed responses; no private note/path/body/provider leakage through projections/errors/audits. |
| Replayed authorization state, unready/quarantined asset, preview flag, PDF export request | Recheck server state and deny unimplemented/unsafe delivery. PDFs remain view-only; no offline paid-material library or unrestricted download switch. |
| Lost-device recovery | After admin identity verification revoke only that installation and release its admission; preserve other devices/grants/history and the ordinary two-device/login policy. |

Use fictional rollback fixtures with collision-failing identifiers and exact-count reports/cleanup, plus real parallel transactions for concurrency claims. Later API/device tests must cover token lifetime, account changes and capabilities issued before revocation: short-lived capabilities may remain usable until their technical validity ends. No claim of instant byte recall, screenshot prevention or entitlement acceptance follows from current catalog tests.

## Decisions and release gates

- **Confirmed 2026-10-20:** editable admin/instructor-selected bundles/one EGP price, membership additions/removals applying to both existing and new buyers, manual external refund funds movement with admin review/record, and no automatic paid-access restoration after republication (fresh audited admin grant, no assumed second payment).
- **Still open:** refund eligibility/partial amounts/access consequences; repeat/overlapping purchases; transfer-reference uniqueness/reconciliation/resubmission; approval when content was removed or price changed; individual versus course-wide revocation/overlap precedence; eligibility for admin purchases/self-approval. Record choices before enabling affected transitions. No new role or invented default resolves them here. Bundle membership edit impact is no longer open.
- **3.2 only:** obtain InstaPay/Vodafone Cash destination details then. This design needs no secrets, destination values or receipt samples and creates no payment instructions.
- **Before store payment release:** complete the required current platform billing-policy review. Neither manual-transfer architecture nor a competitor listing establishes eligibility. No legal/payment-policy conclusion is made here.
- **Before 2.4.3/2.5 claims:** implement/review ownership and status projections with active-admission checks, private RLS/grants, atomic decisions and required regressions. Catalog metadata and safe labels can be designed first; production ownership must never be mocked.
- **Before protected delivery:** implement separate material readiness/scanning, Cloudflare Stream/private files, preview policy, signed capability lifetime/revocation handling and device checks. PDFs are view-only; paid materials have no offline library. Any explicit assignment-resource export remains separately permitted and cannot be recalled once downloaded.

Recommended sequence: settle the specific unresolved transition rules; implement the smallest private order/decision/grant foundation and denial tests; add server-derived access/library projections; integrate approval and paid delivery only after their owning milestones pass. Supabase/Postgres guidance informed private privilege separation, indexed ownership/FKs, short transactions and idempotent audit boundaries; it does not certify an implementation. References: [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security), [database functions](https://supabase.com/docs/guides/database/functions).
