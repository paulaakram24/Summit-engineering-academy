# Published catalog — next implementation slice

Prepared 2026-10-19 after materials UI acceptance. Backend Architect performed read-only inspection of the existing schema and roadmap; no catalog implementation, deployment or tests are claimed here. Implements ROADMAP 2.4.1/.2 and docs/STUDENT_EXPERIENCE.md, not purchases/playback.

## Server boundary

Add read-only SECURITY INVOKER RPCs with empty search paths, fully qualified names and explicit column allowlists: list catalog courses, course detail, and ordered/paginated course-session outlines. Revoke default PUBLIC/anonymous execution; grant authenticated execution only. Preserve existing table RLS/grants and private material denial. Explicitly require active admitted application identity and published/nondeleted entities even for administrators, whose existing authoring RLS also permits drafts. Session outlines must require a published/nondeleted parent.

Return only safe IDs, title/description, instructor/category/level, integer-piaster EGP price, ordering and permitted cover reference; session numbering and preview designation are descriptors, not proof of ownership or playable content. No material payload joins, service-role client, public bucket, signed delivery capability or invented ownership label. Existing authenticated image-cover policy remains the image-only exception. Allowlists do not remove existing direct-table SELECT grants; any tightening is a separately reviewed admin-compatibility change.

## Query behavior

Apply visibility, bounded search across title/instructor/category and exact category/level filters before stable `(position,id)` cursor pagination, default 20. Escape wildcard `%`, `_` and backslash as literal user text; parameterize inputs. Derive filter options from the complete authorized published catalog, never only loaded cards. Define bounded query/cursor validation and page-size limits before implementation. Use existing category/level fields without guessing university-major/semester taxonomy.

## Client and acceptance

Use a dedicated typed catalog repository, not an admin projection. Distinct loading/error/empty states, authoritative prices, accessible cover fallback, clear/reset filters and preserved return state. Invalidate stale query/account/device/lifecycle responses. Add later-page search matches, combined filters, stable pagination, literal wildcards, hidden/deleted parent, admin draft exclusion, invalid/revoked admission and unchanged material-denial regressions. Run existing database/app suites before acceptance, followed by actual device inspection of authorized content or an honest empty catalog; do not publish temporary content without authority.

No migration or test exists for this design yet. Protected uploads/readiness, quarantine/scanner, Cloudflare Stream and entitlement-enforced delivery stay open under 2.3.4/Phases 3–4. A preview flag or zero price alone must not enable media access.
