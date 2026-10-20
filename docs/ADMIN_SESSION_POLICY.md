# Administrator and student session policy

Owner clarification, 2026-10-20: enabled, server-authorized admins may use unlimited registered installations and simultaneous sessions. Students retain at most two unrevoked installations and one active application session; an ordinary new login cannot replace that session.

## Enforcement

The additive `admin_parallel_sessions` migration changes the existing private admission helpers without changing public RPC signatures or exposing private tables. Authorization uses the current `private.account_access.role`, not Google/Supabase user metadata or a client-supplied role. Each administrator context resolves the requesting JWT session's own admitted installation. An admin's older admission is not ended by another successful registration.

Both roles still require a confirmed, nonanonymous, unbanned user, a valid server Auth session, an enabled account, an admitted nonended application session and a nonrevoked installation. Ended sessions cannot register again. Ordinary app logout retains the existing server tombstone and `SignOutScope.local`, affecting only the calling session, including when two admin sessions share an installation.

Server-side admin-to-student demotion ends that user's existing admissions and clears the student pointer. It does not choose devices to revoke or erase their history. A former admin with more than two unrevoked installations needs explicit authorized device remediation before fresh student admission; role promotion does not resurrect ended sessions. Role/device-management UI is not implemented by this migration.

## Verification

Main runs each complete rollback suite with the reviewed migration inserted immediately after its BEGIN for atomic schema-and-fixture preflight. Rollback must remain intact. For the connector, trailing cleanup SELECTs are submitted separately so they do not hide the named test report. Fictional fixture setup is server-privileged; every client-boundary assertion switches to the authenticated/anonymous role as appropriate. No real owner's session or device is altered by these tests.

Main deployed `supabase/migrations/20261020102940_admin_parallel_sessions.sql` to development after atomic rollback preflight. Local version matches hosted history; reviewed SQL hash E6D008717CA3E79F90DF29E4B440DCE14F9834A8A91432F9DBBA9D3F64D74EFD. Both atomic preflight and fresh postdeployment runs passed identity/admin/content/covers/materials/catalog counts **84/46/130/53/163/155 = 631**. Every named assertion passed; administrator report required exactly 46 entries. Seven dedicated fixture cleanup counts were zero after both the corrected preflight and earlier failed attempt. Final postdeployment aggregate cleanup confirmed zero reserved users, Auth sessions, accounts, devices, admissions, profiles, security events, courses and course sessions. Existing owner remains enabled admin with its original one device/one admission. No admission reset or owner-role mutation performed.

The first preflight submission failed because JavaScript string replacement collapsed SQL dollar quotes; callback replacement corrected the submission. The first dedicated-suite run then exposed same-statement registration side effects combined with STABLE admission reads. Splitting mutations from subsequent read assertions resolved the failure without changing migration volatility or policy. Final suite SHA-256 A8816BC7D0C077B1BC944F8C20E7BF4601452B257F21F32FD87F8E92C36D86D1.

All 466 Flutter tests freshly passed, analysis clean, 49-file formatting unchanged. No Flutter runtime change/rebuild required for this server-only exception; latest verified APK remains installed on the emulator. Owner-controlled emulator retry was requested after deployment and is pending. No native multi-device success or concurrency proof is implied by sequential SQL assertions. CI references the new suite but has not run remotely; no new push approved/performed.

The material suite's missing-admission fixture now temporarily snapshots/removes/restores only its fictional admission row; clearing the student-only pointer is no longer an appropriate way to deny an admin. Its separate ended-admission test remains intact.

Owner subsequently confirmed the requested emulator Google retry reached Administrator home (2026-10-20). This supersedes the retry-pending state above and accepts that interactive admin login without a Huawei logout/reset. It is owner-reported evidence; independent two-installation restart/logout acceptance is still pending.

Supabase references checked for this implementation: [session validity and server session IDs](https://supabase.com/docs/guides/auth/sessions) and [local versus global logout](https://supabase.com/docs/guides/auth/signout). Current changelog review found no required API/signature change for these private SQL helpers; no Auth settings, packages or paid features were changed.

Postdeployment advisors retained seven intentional closed private-table RLS/no-policy informational notices and the existing [disabled leaked-password protection warning](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection). Performance notices are three [unused development indexes](https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index) and the existing [composite payload foreign-key index notice](https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys); material_id already has a unique primary-key index. No policy, paid setting or index changed to suppress notices. This is bounded verification, not a full security audit.
