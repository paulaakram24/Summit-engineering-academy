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
- Confirm expiry duration/start/renewal rules before production entitlements. Refund policy remains unspecified.
- Manual payment instructions inside store apps require current platform billing-policy review before release. A competitor listing does not establish eligibility.
- Keep payment destination details pending until roadmap milestone 3.2; do not invent them.

Independent agent review completed 2026-10-14. Remaining business choices do not block the Flutter foundation.
