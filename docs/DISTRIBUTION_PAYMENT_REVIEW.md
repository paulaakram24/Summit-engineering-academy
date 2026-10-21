# Distribution and payment release gate

Reviewed 2026-10-20 against the official pages below. This is engineering release planning, not legal advice, an exemption determination or approval from a store. Recheck the exact storefront/program rules before submission. SEA has not enrolled in an alternative billing program in this task.

## Current requirement and conflict

SEA plans one-time EGP payments for recorded sessions, bundles and courses, manually verified by admins after InstaPay/Vodafone Cash transfers. These unlock digital learning content inside the mobile app. No checkout, transfer instruction or payment approval flow is currently enabled.

Apple's baseline in 3.1.1 requires in-app purchase for digital unlocks. Other-purchase rules and linking permissions depend on product type and storefront. Reader-app eligibility is not established for SEA's combined learning/assignment product. Recorded lessons are not the real-time one-to-one tutoring exception. Do not apply US-specific linking permissions globally or infer eligibility from a competitor. Source: [Apple App Review Guidelines, payments](https://developer.apple.com/app-store/review/guidelines/#payments).

Google's baseline requires Play billing for digital purchases in Play-distributed apps, subject to stated exceptions. Alternative billing or external offers require applicable regional eligibility, enrollment and terms. Transfer instructions, receipt submission or payment links must not be presumed compliant merely because verification is manual. Current source review does not establish SEA's eligibility. Source: [Google Play Payments policy, sections 2, 4, 8 and 9](https://support.google.com/googleplay/android-developer/answer/9858738).

## Owner decision — direct Android initially

Owner selected **direct Android installation initially** on 2026-10-20 after reconfirming method selection, transaction screenshot upload and manual admin verification/approval. This resolves the initial channel choice, not production readiness. Keep both Student and Admin workflows in the mobile app. Google Play/App Store and iPhone distribution are deferred; no store submission or store billing integration is selected. Preserve this review as the gate for a later store release.

Before distributing to students, verify a release-signed APK, stable application identity, secure signing-key backup/access, a trustworthy HTTPS download location, integrity/update procedures, privacy/support/refund terms, production backend and rollback/forward-fix acceptance. Keep debug/dev artifacts separate. Choose the hosting/update mechanism during release preparation; this decision does not authorize creating a website, buying services or publishing an artifact now.

Source inspection on 2026-10-20 confirms `app/android/app/build.gradle.kts` still uses `com.example.summit_academy` and assigns the debug signing configuration to its release build type. These are known development settings, not an approved production identity/signing chain. Do not distribute a build as production merely because its build mode is named release. Resolve these at ROADMAP 8.1/8.4 and verify the actual certificate/artifact before distribution; no identifier or signing-key change was made during this inspection.

## Options considered

1. **Direct Android first:** retain manual payment requirements for a directly distributed Android build. This is not Google Play publication and supplies no equivalent public iPhone distribution. Still requires signed artifacts, secure updates, privacy/refund terms, operational support and applicable legal review. Do not distribute a debug APK as production.
2. **Public stores first:** design compliant store billing or obtain explicit applicable program eligibility. This changes the planned payment integrations and refund/receipt verification architecture; do not silently replace the owner's manual-transfer requirement.
3. **Access-only store product, if eligible:** investigate a consumption-only product with no external purchase solicitation. This is an option to assess, not a proven workaround or owner-selected scope. Review the whole app, including admin screens, sign-up, copy and links. It may need separately scoped staff tooling and store review.

Record the selected Android and iOS channels, target storefronts, staff/payment UI boundaries and approved billing source before enabling checkout. Never hide prohibited flows from reviewers or use a remote switch to evade review. No developer enrollment, paid service, external payment, store submission or distribution change is authorized by this review.

## Safe work while pending

- Course bookmarks and catalog accessibility do not require checkout or purchased-access claims.
- Keep order/entitlement design provider-neutral; a payment screenshot is never evidence that funds arrived.
- Do not enable real transfers, grants or refunds before their business transitions, tests and release-channel gates are resolved.
- Preserve the existing mobile-only Student/Admin scope; admins currently perform instructor duties.

The initial channel is now direct Android. The owner also confirmed case-by-case full/partial refunds with explicit separately recorded access decisions. These describe the planned manual-payment branch; they do not override a future store's refund/billing requirements. Payment destinations remain deferred to ROADMAP 3.2. This decision does not complete ROADMAP 3.1's remaining commerce transitions or establish release readiness.
