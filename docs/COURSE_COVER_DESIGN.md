# Private course covers — implementation boundary

2026-10-19. Backend/storage, client service and system-picker/private-preview UI are integrated. Administrator physical binary workflow accepted on Huawei; see PHASE2_DEVICE_ACCEPTANCE.md. Student/iOS/release and concurrency acceptance remain separate. Historical backend regression evidence belongs in PHASE2_COVERS.md.

## Object lifecycle

Each upload reserves a fresh `course UUID/object UUID.png` path in an unexposed asset ledger. Objects are immutable: no overwrite, move or storage UPDATE policy. The reservation belongs to its preparing administrator and expires after one hour. A maximum of five recent pending reservations per course limits abandoned upload bursts; it is not a business cap on courses or sessions.

The lifecycle is `uploading → attached → retired → cleaned`. Uploads may also go directly from uploading to retired through abandonment/expiry. Retirement is irreversible. Cleaned tombstones are retained, preventing re-upload/re-attachment of a path after cleanup. If a late object appears at a cleaned path, the next cleanup pass lists it again. Never reset or reuse these paths.

Attachment locks the course and checks its expected previous cover, preventing a stale editor from replacing a newer cover. Repeating an already completed attachment is idempotent. The new object must exist with PNG MIME metadata and a size between 1 byte and 3 MiB. The previous cover becomes retired in the same transaction as the course update/audit. An abandon request after a lost attach response cannot retire an attached asset.

## Access and validation

The bucket is private. Active admitted administrators may reserve/upload/attach, view reservations and clean retired objects. Active students can download only the currently attached cover of a published, nondeleted course. Draft, unreferenced, retired, disabled-account and revoked-session access stays denied. The app never writes cover_path directly or introduces public image URLs/signed bearer URLs; downloads carry the user's JWT and undergo Storage RLS.

Storage enforces MIME/size restrictions, not arbitrary hostile image-content scanning. The client accepts PNG/JPEG/WebP inputs up to 5 MiB, checks dimensions before allocating decoded pixels (4096 maximum per edge and 16 million pixels), rejects animation, decodes, and re-encodes PNG with metadata removed. Output is capped at 3 MiB. Downloads are also bounded and decoded before use. This does not claim that Storage independently performs image decoding or malware scanning; malicious administrators and compromised clients remain a separate threat boundary. No HTML/SVG renderer or arbitrary remote URL input is introduced.

## Cleanup and failure handling

Cleanup is explicit and bounded: at most 20 stale reservations are expired and 20 retired/orphan paths returned per pass. Deletion is allowed only for retired/cleaned objects that are not referenced by any course. Successful removal is confirmed server-side before marking the tombstone cleaned. Failures remain retryable; no direct SQL deletion of Storage rows is used.

A failed/timed-out attachment can already have committed. The client first abandons the reservation, then asks the server for retired paths. It attempts removal only when its prepared path appears in that result. Failure, uncertainty, or omission leaves the object alone for later cleanup. Server retirement rules and delete policies remain authoritative even if a client is stale or compromised. The client never deletes the previous cover directly.

No background scheduler is configured in this increment. The integrated UI exposes confirmed bounded cleanup/results, cancellation and failures. Main accepted actual Storage upload/private readback/replacement/removal/cleanup and system-picker selection/cancel/restart on Huawei; SQL object fixtures and mocks were not used as substitutes. Process-death interruption mid-mutation and concurrent clients remain separate failure-case gates.

Existing course-materials, payment-receipts and assignment-submissions buckets remain closed. This cover design grants no access to paid materials or videos.
