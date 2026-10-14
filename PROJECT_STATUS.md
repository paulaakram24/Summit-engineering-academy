# Summit Engineering Academy — Project Status

## Product
Mobile-only learning and commerce app for Summit Engineering Academy. Roles: Student and Admin. Currency: EGP. Language: English. Visual direction: colorful, student-focused. Admins are currently the instructors and manage all content.

## Locked decisions
- Flutter + Dart mobile app for both roles.
- Supabase Auth, PostgreSQL, Storage, Row Level Security, and Edge Functions.
- Private video streaming through Mux or Cloudflare Stream with signed playback URLs.
- InstaPay and Vodafone Cash manual payment verification with receipt uploads.
- One-time purchases for individual sessions and complete courses.
- Course purchases unlock future sessions added to that course.
- Maximum two registered devices per account; simultaneous-login protection is required.
- Access expires according to the configured purchase/access expiry policy.
- Content states: Draft, Published, Archived.
- Assignments support submission, grading and feedback/results; quizzes are excluded.
- Notifications: in-app, email, WhatsApp, and push where provider support is available.
- Admins can manually grant/revoke access, create cash purchases, and view audit logs.

## Delivery phases
- [ ] Phase 0 — Repository inspection, architecture decision record, project bootstrap
- [ ] Phase 1 — Supabase schema, migrations, RLS, seed data, authentication
- [ ] Phase 2 — Student registration, login, profile, device registration
- [ ] Phase 3 — Admin course/session/content management
- [ ] Phase 4 — Course catalog, enrollment, session access, progress tracking
- [ ] Phase 5 — Manual payments, receipt review, approvals, refunds/revocations
- [ ] Phase 6 — Secure video/files, watermarking, signed URLs, download controls
- [ ] Phase 7 — Assignments, notifications, search, bookmarks, analytics
- [ ] Phase 8 — Security audit, testing, accessibility, performance, release

## Completed
- [ ] Requirements reconciled; expiry duration and provider details remain open
- [x] Master build prompt prepared
- [x] Official SEA logo added to project assets
- [x] Public Leader_Academy reference reviewed and documented
- [x] Framework reassessed: Flutter/Dart selected instead of React Native/Expo
- [x] Local prerequisite audit started

## In progress
- [ ] Flutter/Dart SDK installation and `flutter doctor` verification
- [ ] Flutter project shell
- [ ] Supabase project creation and authentication setup

## Known constraints
- No payment gateway auto-confirmation is required initially.
- Mobile-only administration is intentional for the current release.
- Digital-content protection reduces casual sharing but cannot guarantee prevention of screenshots or screen recording on every device.
- Windows PC has Git, Android Studio, OpenJDK 17, VS Code, and GitHub CLI available; Android SDK folders are present.
- Flutter repository checkout was started at `C:\src\flutter`, but the bundled Dart SDK bootstrap stalled before `flutter --version` could complete. No application code was created.
- iOS builds require access to a Mac with Xcode; the user currently has no Mac.
- Chosen providers for planning: Cloudflare Stream for private video and Meta WhatsApp Cloud API for WhatsApp. Provider credentials are still required.
- Gmail/SMTP credentials and Supabase account/project credentials are still required before live integrations can be verified.

## Required update rule
The coding agent must update this file after every meaningful feature, schema change, security decision, test milestone, or deployment change. Never claim a checkbox is complete without evidence.

## Next step
Implementation is authorized. Follow ROADMAP.md, beginning with phase 0. Android development proceeds independently of pending iOS build access. Keep sources/ read-only.

## Current session — 2026-10-14
- Created ROADMAP.md with phases 0–8, subphases and measurable exit checks.
- Independent requirements agent review completed; identified missing bundles, assignment grades, private messaging, themes and enrollment distinctions.
- Flutter 3.47.7 / Dart 3.13.5 verified at C:/src/flutter. Android doctor check passed, including licenses. Android/iOS starter generated under app/ (75 files).
- Two Flutter installations detected: C:/src/flutter and C:/Users/Paula/develop/flutter. Commands use the explicit verified path until consolidated. Windows desktop compiler missing but outside mobile scope.
- Phase 0 active: branded welcome screen and System/Light/Dark selection implemented. Android build/device verification remains pending. No business feature is implemented yet.
- Validation: flutter analyze passed with no issues; two widget tests passed (branding/theme selection and small-screen large-text layout). iOS storyboard XML parsed; native iOS runtime untested.
- Android debug build progressed past Gradle download; NDK installation remains pending with SDK version/duplicate-folder warnings. No APK confirmed.
- User approved pushing this tested foundation on 2026-10-14 with the build limitation disclosed. Future milestones still require approval before push.
- Payment destination details will be requested at phase 3.2. The existing WhatsApp provider must be identified before integration; Meta is a proposal, not a confirmed replacement.
