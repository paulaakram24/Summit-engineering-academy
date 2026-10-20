# Phase 2 development-device acceptance — 2026-10-19

## Android Studio emulator alternative — 2026-10-20

Owner authorized switching while Huawei is disconnected. Reused the installed Medium_Phone_API_37.0 AVD; WHPX acceleration is usable, and boot_completed=1 / ADB online established successful startup. Runtime Android 17/API 37, 1080×2400. Launch used two cores and 2048 MiB with cold boot/no snapshot save, no data wipe and no Windows security/feature changes. Existing virtual data was preserved.

Latest configured APK installed successfully; hashing emulator base.apk matched local SHA-256 `7884B004D1C5BDE581DA70EE368935E327B8228E11B55ECBEC9EDA3EB9981FF6`. Settled capture `E:/Android-prerequisites-Summit/sea-emulator-latest.png` shows the SEA logo and signed-out form, including the Google logo/button. This confirms latest-artifact emulator startup, not authenticated catalog or physical Huawei acceptance. The emulator window is titled `Android Emulator - Medium_Phone_API_37.0:5554`.

Owner initially reported another-session admission block, then clarified admins must have unlimited devices/simultaneous sessions. Reviewed server policy deployed as 20261020102940; student limits remain unchanged. On the requested retry, owner confirmed **Administrator home appears**. This accepts the interactive emulator admin login without Huawei logout/reset; no new screenshot or hosted admission readback is claimed. Native independent restart/logout preservation across installations remains open. No credentials/codes, Huawei tokens or prior OAuth callbacks were reused; no manual admission reset, revocation, new role or account creation performed. The normal-logout/recovery requirement now applies to blocked student sessions, not enabled admin simultaneous admission. Temporary course/session publication and final archiving are approved, but have not started. Push still requires separate fresh approval.

## Latest catalog debug checkpoint — 2026-10-20

Owner has now approved temporary synthetic course/session publication for the populated check and final archiving (no payment/real learning material). However, the next read-only phone preflight reported USB charging at **0%**. No new APK installation, publication or populated test was attempted. That approval remains available after charging and does not authorize a push; prior physical evidence/artifact boundaries below are unchanged.

**Later local-only revision:** the withdrawal fix and expanded regressions passed 466 app tests and Android rebuild (9.2s), producing APK 189055852 bytes / SHA-256 `7884B004D1C5BDE581DA70EE368935E327B8228E11B55ECBEC9EDA3EB9981FF6`. It is not installed and has no new physical acceptance. The BF2CA024…31CED build below remains installed; read-only battery check still shows USB charging at 2%. Do not attribute the native evidence below to the later fix. No publication or account/device security changes were made in that follow-up.

Same Huawei, configured debug APK **189056031 bytes**, SHA-256 `BF2CA0241F57D5591312CC808D1C6C3C0DE2E2CE8BF164F7C1C0DE2CCDD31CED`. Main full verification: 453 app tests, clean analysis, 47-file zero-change format check, locked dependencies and Android build (53.9s). Separate fresh hosted regression total: 585 assertions, with reserved-fixture cleanup confirmed. No release-signed artifact acceptance implied.

Update installation succeeded and preserved owner login. Startup initially showed a white screen before eventually rendering; this is not a launch-performance pass. Scrolled to the new Browse courses entry on the administrator home. Catalog displayed Search courses, Category/Level All, Search/Clear filters/Refresh and **No published courses yet**. Hosted readback independently confirmed zero published/nondeleted courses; the previously authorized temporary parent remains archived/deleted, no cover and three draft materials retained. Catalog RPCs apply published-only filtering even for this administrator.

Entered synthetic search `SEA-TEMP` and submitted: settled screen showed **No courses match your search or filters**, with no leaked draft/deleted card. Clear filters reset text/counter and restored the honest empty message. Backgrounded via Android Home and returned to SEA: catalog workspace showed access closed, with no retained fields/cards; Android Back returned to the still-authenticated owner home. Reopened Browse courses after access revalidation and confirmed the settled empty catalog again (`sea-catalog-reopened.png`). This was not an owner logout, lost-device simulation, actual server revocation or separate student sign-in.

Local evidence outside Git in E:/Android-prerequisites-Summit/: `sea-catalog-ready.png`, `sea-catalog-entry.png`, `sea-catalog-empty.png`, `sea-catalog-no-matches.png`, `sea-catalog-cleared.png`, `sea-catalog-access-closed.png`, `sea-catalog-return-home.png`. Initial white/transition captures are not settled-success evidence. No course publication, purchase, payment, media upload or protected content access performed. Phone battery showed 2% despite charging, so the smoke test was bounded.

Open physical gates: populated cards/details/outline, combined filter choices and later-page search on real released content, actual student identity/HTTP denials, authenticated positive cover reads in the catalog, screen reader, iOS and signed release artifact. Widget tests cover 360-wide/2x-text layout, search/filter/page/detail navigation, stale responses, revocation/account/lifecycle closure and fallback. SQL fixtures cover publication/parent filtering, search before pagination and student material denial; neither is a substitute for the open native checks. Publishing a clearly labeled synthetic test course/session requires separate owner approval; it has been requested, not assumed. All follow-up code remains unpushed pending fresh approval.

Device: owner-authorized Huawei ANE-LX1, Android 9/API 28. Installed configured **debug** APK, not a signed production release candidate. Previous local checkpoint: 171 Flutter tests, clean analysis, configured Android build passed in 36.5 seconds. Later cover UI changes require fresh checks and installation.

Device package readback: versionName 1.0.0, versionCode 1, minSdk 24, targetSdk 36, DEBUGGABLE flag. This development version is not a store submission identifier.

Metadata/lifecycle debug APK SHA-256 before the next cover build: `88fccfe0234cf0014b91d86a650b15a200261ff8981570b3da4a9b9e660c64f1`. Direct device `base.apk` hashing matched the local 188,765,114-byte artifact. This is a development artifact, not a pushed release.

Owner explicitly allowed temporary content. All physical writes used the normal administrator application and its authenticated API. Hosted checks below were read-only; no service-key bypass was used for phone operations.

## Accepted administrator flows

1. Empty course submission remains in editor with required-field errors.
2. Create `SEA-TEMP-20261019`, description `Temporary-device-test-not-for-sale`, instructor `SEA-Test`, category `Testing`, level `Acceptance`, position 0, price 123.45 EGP, draft.
3. Reopen editor and verify persisted description/metadata/price; append `-EDITED` to title and save. List shows edited title, unchanged exact price and draft status.
4. Create session 1 `TEMP-Session`, description `Temporary-session-test`, position 0, price 12.34 EGP, draft, free preview off. Reopen editor to inspect persisted values, append `-EDITED`, save and verify list.
5. Open session deletion confirmation and Cancel: session remains unchanged. Confirm deletion on a second attempt: absent from default list. Include deleted shows archived/Deleted, Edit disabled, Restore available. Restore confirmation explains explicit republication; restoring returns draft with edited title and price intact.
6. Delete parent course: Include deleted shows archived/Deleted with Edit course and Sessions disabled. Restore returns draft with title/price intact and editing/session controls enabled.
7. Final cleanup soft-deletes the same course again; all records remain recoverable. Its restored draft session remains under the deleted parent. Nothing was published or permanently deleted.

Read-only hosted readback independently confirmed exactly the designated course (`354b334e-72fb-437b-b430-08527c539a6a`) and session (`d92d2362-64be-459b-b1fb-346602707ccd`): course archived/deleted at final check, session draft/not individually deleted, prices 12345 and 1234 integer piasters. These identifiers refer only to explicitly authorized temporary development content, not fictional rollback fixtures.

Scoped audit readback: course one draft insert, two draft updates (edit/restore), two archived/deleted updates; session one draft insert, two draft updates (edit/restore), one archived/deleted update. No published event was present for either designated entity. Cancel generated no extra mutation.

## Private local screenshots

Stored outside Git under `E:/Android-prerequisites-Summit/`:

- `sea-temp-result.png`, `sea-temp-edit-ready.png`, `sea-temp-edited-list.png`: course create/read/edit.
- `sea-session-created.png`, `sea-session-edit.png`, `sea-session-edit-result.png`: session create/read/edit.
- `sea-session-confirm.png`, `sea-session-cancel.png`, `sea-session-deleted-ready.png`, `sea-session-deleted-visible.png`, `sea-session-restore-confirm.png`, `sea-session-restored.png`: cancellation, deletion and draft restoration.
- `sea-course-delete-confirm.png`, `sea-course-deleted-visible.png`, `sea-course-restore-confirm.png`, `sea-course-restored.png`, `sea-temp-final-deleted.png`: parent lifecycle and final recoverable state.
- `sea-temp-final-hidden.png`: final default list is empty with Include deleted off.

Screenshots during Saving/loading are transition evidence only, not successful completion. Final readback and settled screenshots establish the stated results.

## Remaining gates

- Physical student-side denial/visibility, explicit publication behavior and release-signed artifact acceptance.
- Student-side cover visibility/denial, iOS picker behavior and release-signed cover acceptance; administrator binary flow accepted below.
- System Back currently lacks an unsaved-change warning; use explicit Cancel/Back to courses deliberately.
- Price helper's earlier large-font truncation was addressed in the cover UI increment; other forms still require release-wide accessibility checks.
- No claim of live email/recovery, second-device, iOS, production readiness or hosted CI for unpushed changes.

Agency Agents Mobile Release Engineer guidance informed cancellation, restore-to-draft, exact-price readback and the distinction between debug acceptance and release acceptance. Push requires fresh owner approval.

## Private cover acceptance — 2026-10-19

Same authorized unpublished temporary course. Controlled picker input was only the repository logo copied to Download/SEA-TEMP-cover-test.png; personal files were not opened. Picker cancellation had already returned to the intact app without an upload.

At resumption the app showed Cover saved; independent hosted readback confirmed one attached private PNG, 330203 bytes. Initial confirmation itself was not repeated or attributed to this resumed run. Force-stop/restart restored the administrator session; reopening Course cover fetched and displayed the persisted image without selecting it again.

Main then selected the same controlled logo again, confirmed Replace course cover, and verified two distinct immutable object paths: old retired, new attached/current, each 330203 bytes. Confirmed removal cleared the preview/reference and retired the second object. Before cleanup, a scoped ledger inventory confirmed only these two test assets were eligible; no unrelated assets existed. Confirmed bounded cleanup reported 2 cleaned, 0 failed, 2 attempted. Independent database readback confirmed cover_path NULL, two cleaned tombstones and zero matching storage.objects rows. Binary deletion used the app's Storage API, not SQL DELETE. Uploaded test copies are permanently removed; the original repository/phone input logo remains available.

Finally main soft-deleted the course again through its confirmation dialog. Settled default list showed no content; hosted readback confirmed archived, recoverably deleted and no cover. The course/session records remain recoverable, and no acceptance content was published. Owner login remained intact.

Evidence under E:/Android-prerequisites-Summit/: sea-cover-resume-current.png, sea-cover-restart-ready.png, sea-cover-restart-list.png, sea-cover-downloaded-restart.png, sea-cover-replace-picker.png, sea-cover-replace-selected.png, sea-cover-replace-confirm.png, sea-cover-replace-result.png, sea-cover-remove-confirm.png, sea-cover-removed.png, sea-cover-clean-confirm.png, sea-cover-clean-result.png, sea-cover-final-delete-confirm.png and sea-cover-final-hidden.png. Local screenshots are not committed.

This accepts the administrator debug-build binary workflow only, not student RLS over HTTP, iOS, concurrent edits, release signing or production readiness.

## Administrator materials acceptance — 2026-10-19

Final APK: 189013765 bytes, SHA-256 `932540DBECDE281CF0582BCB94E0F8242B6FA1B6442719CD078E14093E42D054`; all 355 Flutter tests, clean analysis/format and configured Android build passed before installation. Same authorized temporary course/session as above, restored to draft only during acceptance. This later UI increment is not in approved push 5fa6d4a.

1. Open Manage courses → Sessions → Materials. Create draft assignment `SEA-TEMP-assignment` with only synthetic plain-text instructions. Reopen private detail and append `-EDITED` to title; instructions remain loaded. Server revision advances 1 → 2.
2. Cancel deletion; list and hosted revision remain unchanged. Confirm deletion; hidden from default list. Include deleted shows archived/Deleted, disabled Edit and enabled Restore. Confirm restore; returns draft, revision 4, original 35-character instructions retained.
3. Create draft `SEA-TEMP-link`, target `https://example.invalid/sea-test`. It is inert editor text, not launched. Create draft `SEA-TEMP-video`; media placeholder warning explicitly states uploads/student delivery unavailable and cannot publish. No bytes selected/uploaded.
4. Force-stop/restart SEA. Owner administrator session persists; course/session/materials reopen with all three draft records. Reopen video metadata and private link detail; exact synthetic HTTPS target remains intact. Cancel untouched edit and use Android Back to return to session list.
5. Return to course list and confirm recoverable deletion of the temporary parent. Settled default list is empty. Hosted readback confirms course archived/deleted, cover NULL, draft session and three retained nondeleted draft materials beneath it. Nothing was published or permanently deleted; owner login is unchanged.

Actual development material identifiers: assignment `567d7346-6932-499a-b3ec-8ddd670aae72`, link `b2cbd7ce-3517-4dc1-b827-da8abb7aa723`, video `acedda21-b544-4adc-8f59-ab2c4cbcb159`. Scoped audit: three `material_create` draft/revision-1 events, one `material_update` draft/revision-2, one `material_delete` archived/revision-3, one `material_restore` draft/revision-4. No extra event for cancelled deletion, and no published event. Unlike rollback fixtures, these authorized synthetic records are intentionally retained/recoverable under the deleted parent.

Local evidence under E:/Android-prerequisites-Summit/: `sea-materials-assignment-ready.png`, `sea-materials-assignment-edit.png`, `sea-materials-delete-confirm.png`, `sea-materials-deleted-visible.png`, `sea-materials-restore-material-confirm.png`, `sea-materials-restored.png`, `sea-materials-link-saved.png`, `sea-materials-video-ready.png`, `sea-materials-reopened.png`, `sea-materials-video-reopened.png`, `sea-materials-link-reopened.png`, `sea-materials-close-result.png`, `sea-materials-cleanup-dialog.png`, `sea-materials-final-hidden.png`. Screenshots remain outside Git. Transition images do not establish successful saves. Slow startup eventually rendered; performance is not accepted by this smoke test.

Bounded debug administrator acceptance only. Student reads/entitlements, media assets/quarantine/Stream, iOS, release signing, real concurrency and full accessibility acceptance remain separate gates. Material-panel dirty navigation is tested; the older general course/session editor's system-Back limitation above is not thereby resolved.
