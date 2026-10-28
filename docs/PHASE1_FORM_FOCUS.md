# Phase 1 form focus correction — 2026-10-25

The owner reported profile fields refreshing immediately on focus. Main
reproduced Phone briefly gaining then losing focus on the Android emulator.
Temporary debug-only lifecycle markers established one AuthPanel initialization,
then an inactive/resumed pair about168ms apart on the field tap, with no panel
disposal. The markers contained no account values and were removed before the
final build. A diagnostic-only APK built in9.8s and was temporarily installed
with data preserved; it is not the final accepted artifact.

The original AuthPanel observer treated every non-resumed event as suspension
and every resume as a fresh access check. That replaced the form with a checking
screen; returning to profile completion reloaded server values and lost focus.

## Correction and boundaries

Credential, verification, recovery and incomplete-profile entry forms now ignore
transient inactive/resumed focus cycles. Hidden/paused/detached states still
suspend, clear protected access and require revalidation on return. Protected
ready/checking/blocked workspaces keep the existing stricter inactive and
repeated-resume behavior, including picker-return admission checks. Account
events, epoch guards and server authorization are unchanged.

Full-SummitApp tests did not reproduce the loss from metrics/scroll alone and
retained the same panel/controllers in those scenarios. They exercise
focus/draft retention, transient lifecycle events, duplicate resume and real
background/revalidation denial. The initial broad lifecycle change failed four
existing picker/upload admission tests; scope was corrected rather than
weakening those tests. The unchanged four cases and new focus suite passed in
a25-test targeted run. Independent Authentication Reviewer found no blocker in
the revised scope.

The initial default-parallel full run exhausted host memory. Only this task's
Gradle daemon was stopped; no browser/user app was closed. Serial verification
then exposed the four assertions above, not memory failure. Final full serial
run/build and native typing results are recorded in PROJECT_STATUS.md.

No password, real profile value, token, content upload, role change, logout or
profile save is needed for this regression test. Native proof should use only
an unsaved synthetic draft and remove that draft before handing control back.

## Final acceptance

Main passed locked dependencies, clean analysis,85-file zero-change formatting
and all1,030app tests with concurrency1. The first Android attempt hit Windows
commit/paging error1455; task-only daemon/emulator shutdown released memory.
A retry with1Gradleworker,1.5GiBGradleheap and512MiBtoolheap passed105.5s.
These were subprocess-local limits; no Windows paging/security settings or
owner applications were changed.

Final APK165022735bytes, SHA256
E7DEFCA657D1C5C5C2342910091A7ADDDEC39FF08115212D3FEB9CA32D90D1E9.
Same AVD reopened withoutwipe; install-r succeeded and installed hash matched.
Phone remained focused with the keyboard after settling; unsaved123remained
visible, then was removed. No profile save, password action or logout occurred.
Phone/university were left empty for the owner. Native evidence remains outside
Git under E:/Android-prerequisites-Summit/sea-focus-final-*.png.
This closes the reproduced entry-form focus defect, not broader Phase1
acceptance, every platform or protected-editor keyboard acceptance.
