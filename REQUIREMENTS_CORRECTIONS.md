# Requirements reconciliation

These corrections take precedence over omissions in earlier generated planning documents.

- Flutter/Dart replaces Expo/React Native. Android work is authorized now; iOS testing is a later gate requiring macOS access.
- Support assignment grading/results, private student/admin messaging, session bundles and light/dark themes.
- Individual-session purchase does not create course enrollment. Course purchase includes future sessions while its grant remains valid.
- Support manual completion separately from 90% watched completion; do not display course completion counts by default (original Q41).
- Google sign-in is required alongside email/password.
- PDFs are view-only; other attachment downloads follow explicit file permissions.
- No fixed business cap on sessions; paginate large courses. Include course category, level/year, instructor, image, description and price; include session numbering.
- Include Recent Materials, material search, total/active students, revenue, sales by course/session, most-watched courses, video completion and registrations. Target 100–1,000 students.
- Cloudflare Stream is the selected video provider. Identify the user's existing WhatsApp provider before implementing it.
- Owner clarified 2026-10-19: purchased access begins on administrator approval and has no automatic time expiry; it remains usable while the session is available, until an authorized admin/instructor removes it. This supersedes the earlier generic expiring-access requirement. Session removal/restoration and individual access-revocation behavior must be distinguished; refunds and bundle details remain unspecified.
- Lost-device recovery is admin-only after verifying the student's identity: revoke the lost device so a replacement login can proceed. Revocation must invalidate that installation's application access and release its active-session admission, without logging in as the student or automatically replacing an active session during ordinary login. The two-device limit remains.
- Manual payment instructions inside store apps require current platform billing-policy review before release. A competitor listing does not establish eligibility.
- Keep payment destination details pending until roadmap milestone 3.2; do not invent them.
- Owner authorized useful Q Academy-inspired improvements on 2026-10-19: searchable/filterable course discovery, explicit access states, full-course versus individual-session library views, useful empty states, resume and accessible support. See docs/STUDENT_EXPERIENCE.md for acceptance criteria and boundaries. Existing category/level fields take precedence over unapproved semester/major schema additions. This does not override hidden-by-default completion counts, view-only PDFs, approval-based manual payments, no automatic expiry or mobile-only scope; no competitor code-redemption/refund model is adopted.

Independent agent review completed 2026-10-14. Remaining business choices do not block the Flutter foundation.
