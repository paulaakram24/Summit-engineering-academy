# Questions held for the morning — 2026-10-21

Owner asked to defer questions overnight and answered the main choices on 2026-10-21. The original questions below are retained for history, not unresolved decisions. See REQUIREMENTS_CORRECTIONS.md for the authoritative new decisions.

## Deferred nonurgent follow-up — 2026-10-24

- Scanner-isolation preparation: Docker files are installed, but the fresh Linux-engine check fails and WSL reports not installed. Before changing Windows features/installing WSL or arranging a reboot, agree a convenient maintenance window or an alternative disposable Linux host. No change was attempted; independent local/app work can continue. See docs/MATERIAL_WORKER_ISOLATION_ACCEPTANCE.md. This does not authorize a paid host or weaken the validation gate.

- During read-only process-restart acceptance, the synthetic194-byte TXT had two distinct uploaded assets/operations. The second was created around2026-10-24T00:03UTC, before that continuation; no attribution is established. When convenient: did you intentionally upload the synthetic file again? No urgent action is required. Preserve both private quarantine objects and do not infer cleanup approval or a retry defect. The app still grants no validation/attachment/publication from either upload. Current inventory2objects/388declared-observed bytes is tracked in docs/MATERIAL_UPLOAD_BINARY_ACCEPTANCE.md.

## Answers received — 2026-10-21

1. Reuse/reopen the existing unpaid request for the same target; block purchasing content already covered by current valid access.
2. Honor the request's recorded price.
3. Reject content unavailable before approval; grant no access and arrange a manual refund when funds were received. Track actual return separately.
4. Admins access all content without buying or approval; do not create orders/enrollment to emulate this role privilege.
5. Explicit refund revocation affects only that purchase source, preserving independent valid grants and availability/regrant barriers.
6. Receiving details are per course instructor: their phone number for an InstaPay bank-account transfer, with optional Vodafone Cash at the same number. Instructor chooses InstaPay only or both.

## Follow-up answers received — 2026-10-21

- One assigned authenticated instructor/Admin per course; sessions inherit it. Instructors manage their own receiving details. Existing free-text names/creator IDs do not establish this association.
- Bundles contain only sessions from the same course, hence one instructor/receiver. No cross-course bundles or split transfers.
- Only receiving number and recipient name, plus method selection; no bank-name field. Actual values can be entered through the future app setup.
- Changed receiving details pause existing unpaid requests for instructor review before new instructions. Preserve destination/transfer history and original price.

No further answer to these four setup questions is needed. Order creation and transfer instructions stay closed until the setup, snapshot/review transitions and required code/tests are implemented. Operational reconciliation and partial-overlap bundle behavior must not be guessed when those later transitions are implemented.

## Original morning questions — answered, historical

1. If a student already has an unpaid request for the same course/session, should a new attempt reopen that request or create a separate request? What should happen if they already own it through another purchase?
2. If a course/session price changes after the request was created, should an admin honor that request's recorded price or require a new reviewed request?
3. If purchased content becomes unavailable before payment approval, should the request remain on hold or be rejected and handled through the manual refund process when money was received?
4. Can administrator accounts also make purchases? If yes, may the same admin approve their own payment, or must another admin review it?
5. When a refund decision explicitly revokes access, should it revoke only that purchase's access source, or also other overlapping grants to the same content? The current separate refund/access decision must remain explicit either way.

These choices gate actual creation/checkout and approval/refund transitions. A staged order-intent schema and tests may be prepared with creation execution closed to client roles. A pending intent is not payment received, approval or learning access.

## At the appropriate later milestones

- At 3.2, let instructors enter their receiving phone and recipient name plus InstaPay-only/both-method selection through approved setup; no bank-name field or bank credentials. Never request PINs, OTPs, passwords or account keys in chat.
- For populated native testing, use the existing authorized synthetic-content scope where it actually applies; never republish owner-modified content or alter the owner's role/session just to make a test possible. Actual student sign-in must be owner-controlled.
- Production signing, package identity, download/update hosting and release approval remain Phase 8, not the debug app's current readiness.

Overnight continuation alone does not authorize a push. The owner later explicitly approved the cleanup/closed-order milestone, pushed as bb617fa on 2026-10-21; both GitHub workflows passed. Appearance/documentation work after that push remains unapproved for push. Every subsequent milestone needs fresh approval after testing.
