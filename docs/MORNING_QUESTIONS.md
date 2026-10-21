# Questions held for the morning — 2026-10-21

Owner asked to continue independent work overnight and defer questions. No answers are assumed here. Bundle membership edits, no automatic access expiry, direct Android first, screenshot/manual payment verification, full/partial discretionary refunds and explicit refund access decisions are already settled; do not ask them again.

## Before enabling orders/checkout

1. If a student already has an unpaid request for the same course/session, should a new attempt reopen that request or create a separate request? What should happen if they already own it through another purchase?
2. If a course/session price changes after the request was created, should an admin honor that request's recorded price or require a new reviewed request?
3. If purchased content becomes unavailable before payment approval, should the request remain on hold or be rejected and handled through the manual refund process when money was received?
4. Can administrator accounts also make purchases? If yes, may the same admin approve their own payment, or must another admin review it?
5. When a refund decision explicitly revokes access, should it revoke only that purchase's access source, or also other overlapping grants to the same content? The current separate refund/access decision must remain explicit either way.

These choices gate actual creation/checkout and approval/refund transitions. A staged order-intent schema and tests may be prepared with creation execution closed to client roles. A pending intent is not payment received, approval or learning access.

## At the appropriate later milestones

- At 3.2, collect only the public receiving InstaPay address and Vodafone Cash receiving number plus the display name/instructions; never request PINs, OTPs, passwords or account keys in chat.
- For populated native testing, use the existing authorized synthetic-content scope where it actually applies; never republish owner-modified content or alter the owner's role/session just to make a test possible. Actual student sign-in must be owner-controlled.
- Production signing, package identity, download/update hosting and release approval remain Phase 8, not the debug app's current readiness.

No new push is authorized by overnight continuation. The last approved push is b97aba4; every subsequent milestone needs fresh approval after testing.
