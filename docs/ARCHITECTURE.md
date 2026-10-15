# Architecture decision — Flutter foundation

Status: accepted for implementation by user; 2026-10-14.

## Decision
One Flutter/Dart application targets Android and iOS with Student and Admin experiences. Mobile administration is intentional. Phase 0 provides a standalone welcome shell requiring no backend credentials. The Flutter stable version used for verification is 3.47.7; Dart is bundled.

## Structure
- app/lib: Flutter application source; split into feature modules as authentication/catalog features arrive.
- app/test: widget and later domain tests.
- app/android and app/ios: platform hosts.
- assets: supplied brand source; app/assets: bundled copy.
- scripts: local verification.
- .github/workflows: automated verification pending approved push.
- docs: decisions, development setup and milestone evidence.

## Boundaries
Later phases use Supabase for identity, database and server-authorized actions. Mobile UI visibility is not authorization. Payment approval, device limits and video access require server enforcement. Private media does not become available offline merely because the app shell supports offline rendering.

## Delivery
Android debug build and emulator smoke test verify the local foundation. Windows cannot establish iOS build validity; iOS host verification remains an explicit release dependency. Production signing and store distribution are phase 8 work.

## Agent guidance
Agency Agents Mobile App Builder informs platform-aware layout and device verification.
Agency Agents Mobile Release Engineer informs repeatable build checks and separation of development artifacts from signed release verification.
