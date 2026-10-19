# Reference analysis — Leader_Academy and Q Academy

Reference: [Leader_Academy on the Egypt App Store](https://apps.apple.com/eg/app/leader-academy/id6796975812)

## Observed signals

- Education app focused on courses and lectures across colleges/fields.
- English-language listing, iPhone/iPad support, and EGP in-app purchase packages.
- A library-like experience is suggested by the listing description and wallet products.
- The release history shows frequent security, bug-fix, design, and screenshot-related updates.
- The listing reports a small installed package size and an age rating of 4+.

## What Summit should learn

- Keep the initial learning journey simple: browse → inspect course/session → pay → access → continue learning.
- Treat search, saved items, progress, and clear purchase/access status as core navigation concerns.
- Plan App Store metadata, privacy declarations, screenshot assets, and update/release discipline early.
- Test screenshot/screen-recording behavior and protected media on real iOS and Android devices.
- Keep Summit’s identity distinct through the supplied SEA logo, navy/teal/gold palette, engineering-focused catalog, manual Egypt payment workflow, and transparent access rules.

## Do not copy blindly

- Do not copy branding, text, screenshots, UI artwork, or proprietary behavior.
- Do not assume the reference’s wallet or payment model fits Summit’s session/course purchase model.
- Do not infer backend, security, or privacy practices from an App Store listing alone.

## First implementation decision

Use the reference only to validate the broad category and expected mobile flows. Begin Summit with a discovery/architecture checkpoint, then build the smallest vertical slice: registration → published course → pending manual payment → admin approval → protected session access.

## Additional public reference — Q Academy (2026-10-19)

Owner supplied [Q Academy](https://www.q-academy.org/) as a web-based competitor, not a request to add a SEA website.

Verified from the public homepage HTML: title “Q Academy | Online Courses & Expert Educators”; description presents video courses and free lessons. This supports comparing the public course-discovery/free-preview journey with SEA's existing planned free previews. Those statements are the site's description, not independently verified teaching quality or runtime acceptance.

Initial inspection limit: readable web extraction contained no rendered page body and browser inspection could not initialize. This limitation was partly resolved by the owner-authorized signed-in desktop review below; it is not the final coverage statement.

Candidate comparisons, not verified Q Academy features or new SEA requirements: course cards with instructor/level, clear locked versus free-preview states, course/session outlines, visible access terms, search/filter discoverability and a short path back to learning. Evaluate these against SEA's mobile touch targets, scrolling and small-screen navigation; do not copy desktop layouts directly.

SEA remains mobile-only with in-app administration, the supplied SEA branding, approval-based EGP purchases and the owner-confirmed access policy. Do not copy Q Academy branding, text, code or assets, infer its backend/security from marketing, or adopt a web checkout/payment flow as evidence of mobile-store compliance. No new implementation milestone or paid service is authorized merely by this reference.

## Q Academy signed-in desktop review — 2026-10-19

Method: owner explicitly authorized inspecting their existing signed-in Edge session. Used rendered screenshots and visible accessibility content through normal navigation only. No credentials, cookies, tokens, source code or private APIs were extracted. No purchase, code redemption, account edit, message, upload or download was performed. Do not commit account identifiers or screenshots containing personal details.

### Observed page inventory

| Page / state | Observed experience | Coverage limit |
| --- | --- | --- |
| [Home](https://www.q-academy.org/) | Engineering-focused hero, course carousel, guide-video embed, educator biographies and support/social links. | Marketing claims and educator credentials not independently verified; guide not played. |
| [Course catalog](https://www.q-academy.org/courses) | Six listed courses; semester and major filter controls; search field; cards show subject, instructor, lesson count, duration, displayed original/current EGP price and Enroll action. | Filter/search controls observed, not functionally tested. Six cards read, not every course/lesson opened. |
| [Digital Logic Design](https://www.q-academy.org/courses/330016) | Free first lesson; paused player with seek, volume, speed/fullscreen controls; account-email overlay; 14-item outline, priced locked lessons, coming-soon lessons, progress counter and full-course code entry point. | No playback-completion or paid-access test. An email overlay is visible deterrence, not proof of DRM or server authorization. |
| [Physics I](https://www.q-academy.org/courses/210016) | Same course/player pattern; 11-item outline; lesson prices, free/locked/coming-soon states and Course Notes View / Download PDF control. | Notes not opened/downloaded; entitlement behavior for notes unverified. |
| Locked Physics lesson / Unlock Video dialog | Selecting a priced lesson reveals an access-code prompt, redemption field and support link. | No code entered, redemption attempted or support link followed. Opening the lesson changed the selected lesson and a prior outline icon; persistence was not tested. |
| [My Courses](https://www.q-academy.org/student-courses) | Purchase counts; All Purchases, Full Courses and Single Videos tabs; Recent/A–Z controls; no-purchases state with Browse Courses action. | Account has no purchases; populated library, sorting behavior and paid learning journey not inspected. |
| [Profile](https://www.q-academy.org/profile) | Personal-information summary, enrollment date and password-change form. | Read only; no password controls or account settings changed. Personal values intentionally omitted. |
| [About Us](https://www.q-academy.org/about) | Background, vision/mission, statistics and policy sections covering content, conduct, privacy, enrollment/refunds and enforcement. | Statements are published claims, not verified operations, legal advice or policies SEA should automatically adopt. |

Main navigation exposes Home, Courses and About Us; account menu exposes Profile, My Courses and Logout. Footer has email and external social/support links, not an observed internal contact-page route. Did not log out, revisit authentication, browse unrelated tabs, contact support or attempt hidden/admin routes. This is coverage of the discovered student navigation and sampled course states, **not all possible pages or paid states**. No mobile-device or comprehensive responsive test was performed.

### Implications for SEA's existing roadmap

- **2.4 Catalog/discovery:** keep readable course cards, curriculum-relevant filters, a searchable catalog and an explicit empty result state. Semester/major taxonomy is a candidate requiring SEA content decisions, not silently added mandatory fields.
- **2.3 / 2.4 Session content:** distinguish free preview, paid/locked, unavailable and coming soon; show lesson metadata without exposing protected files. Show released versus planned lesson counts separately so future content does not inflate apparent available content.
- **Phase 3 purchases:** separate full-course and individual-session ownership in My Learning. SEA must retain its approved manual-payment flow and pending/approved/rejected status; do not substitute competitor access codes or copy its refund policy.
- **Protected learning:** retain server-side entitlements, private delivery and device rules. A watermark can complement those controls but cannot replace them; consider privacy-safe identifiers instead of displaying a full email everywhere.
- **Progress and usability:** make continuing a lesson easy, define completion explicitly using SEA's agreed 90% rule, and verify persistence rather than inferring it from checkmarks. Avoid excessive scrolling to reach the outline on mobile; test sticky headers and floating support controls against lesson actions.
- **Support/policies:** use SEA's own support contacts, accurate claims and clearly stated access/removal terms. Do not reuse competitor biographies, figures, artwork, text or legal statements.

This review informs existing work only. No feature implementation, roadmap acceptance checkbox, deployment, backend migration or push was completed by inspecting the competitor.

Follow-up owner decision (2026-10-19): adopt useful patterns for SEA. Concrete acceptance criteria and exclusions are now recorded in docs/STUDENT_EXPERIENCE.md and ROADMAP.md. Only the requirements checkpoint is complete; runtime features remain pending. Existing SEA requirements override conflicting competitor patterns.
