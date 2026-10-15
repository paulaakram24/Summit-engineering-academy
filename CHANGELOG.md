# Changelog

All notable changes to Summit Engineering Academy are recorded here. Dates use `YYYY-MM-DD`.

## Unreleased

### Added
- Phase 0 local verification completed on physical Huawei Android 9; approval required before pushing remaining checks/docs and running hosted CI.
- 2026-10-15: Verified Android debug APK build and installation; documented E: tooling repair, local verification script and emulator runtime limitations.
- Local next-milestone change: GitHub workflow for locked dependencies, formatting, analysis and widget tests using Flutter 3.47.7 (remote execution pending approval).
- Branded Flutter welcome screen using the original logo, accessible scrolling layout, System/Light/Dark appearance selection, and two widget regression tests.
- 2026-10-14: Phased ROADMAP.md, independent requirements reconciliation, and generated Flutter Android/iOS starter in app/.
- Initial product requirements and implementation roadmap.
- Mobile-only Student and Admin scope.
- Mandatory project-status, README, changelog, audit, and security requirements.

### Decisions
- Supabase backend with PostgreSQL and Row Level Security.
- Private signed video streaming.
- Manual InstaPay/Vodafone Cash verification.
- Two-device account limit and simultaneous-login protection.
- Migrated the planned mobile framework from React Native + Expo + TypeScript to Flutter + Dart; application code is not yet changed.
