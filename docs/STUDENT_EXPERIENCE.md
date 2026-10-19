# SEA student experience — adopted reference ideas

Approved direction: owner authorized adopting useful Q Academy ideas on 2026-10-19. This document turns that direction into SEA-specific requirements, not copied design/code. Implementation and runtime acceptance remain open in ROADMAP.md.

## 1. Discover courses — milestone 2.4

- Readable mobile course cards show cover (or accessible fallback), title, instructor, category, level/year and server-supplied EGP price. Do not fabricate ratings, enrollment figures, discounts, video counts or durations.
- Search title, instructor and category; filter by existing category and level/year. Use SEA's current fields first. Separate semester/major fields require a later content-taxonomy decision rather than guessing a university structure.
- Search/filter the authorized catalog on the server before pagination. Do not filter only the currently loaded 20 items and claim global results. Use stable ordering, reset pagination when criteria change, and discard stale responses after a newer query or account change.
- Include loading, retryable error, no-published-courses and no-matches states; offer Clear filters for no matches. Preserve search criteria when returning from course details.
- Course details show safe course/session descriptions, instructor, price and ordered outline without loading protected material payloads or exposing private object paths.

Acceptance: matches outside the first page are discoverable; combined filters and clearing work; changing queries during a delayed request cannot show stale results. Student catalog excludes draft/archived/deleted content and never exposes admin actions. Test small screens, large text, keyboard scrolling and screen-reader labels.

## 2. Understand access — milestones 2.3, 2.4 and 3

- Use text plus an icon for Free preview, Locked, Payment pending, Available and Unavailable, as applicable. Color alone is insufficient.
- Derive ownership and access from server-authorized state. A zero price, a stored local flag or a visible button must never independently unlock content. Free-preview policy must be enforced by the delivery service as well as the UI.
- Locked content may reveal approved metadata and purchase options, never media URLs, assignment bodies or private file identifiers. Show per-session versus full-course options clearly.
- Approval unlocks the approved scope; pending/rejected payments do not. Access has no automatic time expiry under the owner's policy, but removed/unavailable content cannot be played. Do not invent expiry countdowns.
- Approval must be reflected after refresh/restart; unavailable content must not erase purchase history or be mislabeled as an expired purchase.
- Draft sessions are not student-visible coming-soon placeholders. Only introduce such placeholders later if explicitly authored through a separately defined publication contract. Immediate release remains the current requirement.
- If available lesson counts/durations are added, calculate from genuinely released authorized metadata; do not count planned placeholders as playable lessons.

Acceptance: verify each state with server fixtures and a real student session; direct navigation and replayed/stale client state cannot bypass entitlement checks. Loss of access clears protected previews and stops future delivery.

## 3. My Learning — milestone 2.5, integrated with Phase 3

- Distinguish full-course ownership from individually purchased sessions. Suggested labels: All learning, Full courses and Individual sessions. Do not label an individual-session buyer as enrolled in the entire course.
- Empty library explains that approved purchases appear here and offers Browse courses. Empty filtered tabs offer switching tabs rather than suggesting all purchases were lost.
- Approved learning and pending payment requests are visibly distinct. Rejected requests show their status without offering protected playback.
- Support stable recent/alphabetical sorting and return navigation. Do not fabricate purchase timestamps or duplicate a course because it has several purchased sessions. Preserve actual individual purchases and their access scope.
- Loading/error states must not briefly display No purchases or leak the previous user's library. Clear data on auth changes; protected actions re-check authorization.

Acceptance: cover empty, full-course-only, session-only, mixed and unavailable-content accounts, pagination/sorting and account changes. Partial ownership must stay partial. Future-session course grants follow the existing purchase contract; bundle/refund specifics remain an open business decision.

## 4. Continue learning — milestone 4.3

- Offer Continue learning when a valid server-authorized resume point exists. Manual completion and at-least-90%-watched completion remain distinct existing requirements.
- Persist progress safely across restart; do not treat seek position or merely selecting a lesson as proof of 90% watched. Validate duration and watched coverage server-side where possible; define the precise progress protocol before implementation.
- Older delayed updates must not overwrite newer saved progress. Distinguish pending local progress from confirmed synchronization; progress records can never grant access.
- Keep course-completion counts hidden by default, honoring the original requirement. Do not copy the competitor's completed-video counter as a new default.
- Do not expose inaccessible or removed media through a resume shortcut. Recheck access when resuming and handle interrupted networks with clear recovery.

Acceptance: interrupted playback/restart, seeking, manual completion, revoked/removed content, backgrounding and delayed progress updates; no completion inferred solely from opening a lesson.

## 5. Support, trust and materials — milestones 4.4, 5.2, 5.5 and 8.3

- Provide an easy-to-find Help entry with configured SEA email/WhatsApp contacts. Never reuse competitor contacts or invent the academy's missing support details. Do not open messaging apps or send messages without a student action.
- Explain SEA's payment approval and access/removal rules using its own terms. Pending refund/store-policy decisions must be resolved before final purchase copy/release.
- Keep PDFs view-only. Other attachments use explicit download permissions. A competitor's View / Download PDF button does not override SEA's rule.
- Maintain the supplied SEA logo and navy/teal/gold identity. No competitor artwork, videos, biographies, statistics, marketing text or copied desktop layout.
- Preserve protected delivery and identity-watermark requirements. A visible watermark is supplementary, not DRM or an entitlement check; minimize exposed personal information. Final watermark identifier remains a privacy/design choice.
- Support controls must not obscure player controls, purchase actions, dialogs or bottom navigation. Prefer an accessible Help location over an intrusive floating button.
- Returning from an external support app revalidates access and restores safe navigation context. Never automatically prefill tokens, receipts or full account details into external messages.

## Delivery boundaries

Finish the current content foundation and real cover-upload acceptance first. Then deliver 2.4 as a read-only catalog slice with search/filter tests, followed by 2.5 ownership-aware UI alongside Phase 3 entitlements. Integrate resume with actual protected playback in Phase 4, not mocked ownership or fake progress.

No access-code redemption, wallet, website, scheduled releases, paid service, new analytics tracker, competitor refund policy or discount system is added by this decision. No external writes, migration deployment or push is authorized solely by this document. Each milestone still requires tests, accurate status and fresh approval before pushing.

Mobile Release Engineer reviewed these criteria read-only on 2026-10-19; recommendations incorporated for large text, stale progress updates, purchase-history retention and safe return from support apps. This is a product-criteria review, not a runtime security audit or feature acceptance.
