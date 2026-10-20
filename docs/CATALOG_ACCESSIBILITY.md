# Catalog accessibility checkpoint — 2026-10-20

Accessibility follow-up after documentation commit 9b4e8de. Owner approved pushing this milestone on 2026-10-20; actual push/CI outcomes are recorded in PROJECT_STATUS.md. No backend, entitlement or role changes in this patch; later owner-controlled publication and final archive are recorded below.

## Reproduced and corrected

Four delayed-result regressions failed because catalog error/no-results and detail error/unavailable messages lacked live-region semantics. Main added Semantics(liveRegion: true) around sanitized result messages; closed-access and empty-outline messages use the same behavior. These are semantic flags, not evidence of actual spoken announcements on a device.

An expanded long category option at 320 logical pixels/3x text genuinely exceeded its two-line limit. Menu items now wrap without ellipsis and use variable heights. The closed dropdown stays bounded to two lines, retains its complete semantic label and reveals full text with a long-press tooltip. This avoids an unselected long option making even the All selection taller than the viewport. Tooltip semantics are excluded to avoid duplicating the Text label. Filter values, query behavior and actor/lifecycle checks are unchanged.

## Verification

Main passed all 21 new tests in app/test/catalog_accessibility_test.dart, then full configured verification: 487 tests, clean analysis, locked dependencies, formatting 50 files/zero changes and Android debug build (18.3s). Scope includes 320/360x640 surfaces at 2x/3x text; long course/session labels; errors/retry/empty states; actual expanded-menu paragraphs; visible menu taps that prove repository filter selection; compact label bounds/full semantics and rendered full-text long-press tooltip. Tests run labeled, Android and iOS tap-target guidelines; they are not native iOS acceptance. Four delayed-result tests inspect the live-region flag. Main and Mobile App Builder both passed the focused suite; Mobile Release Engineer reviewed runtime and test assertions read-only with no remaining concrete issue.

The first unbounded-dropdown trial made closed fields too tall; the compact selected-item builder resolved it. Oversized menu tests tap a verified visible intersection rather than an offscreen text center. No hit-test warnings were silenced and the final tests still require actual filter changes and complete popup/tooltip text.

Verified local APK: 189056818 bytes, SHA-256 FF6BC235590E75EF2A9CDCE24989D905838B7A90ED1FAB23E24443973303FEEA. Installation outcome is recorded in PROJECT_STATUS.md; do not attribute earlier native checks to this new artifact.

Owner subsequently requested showing the virtual phone. Main reopened the same existing AVD without wiping data, verified boot_completed=1, installed this APK with -r and matched the device base.apk hash. Computer Use activated the uniquely observed emulator window and displayed SEA's signed-out form/Google button. No user authentication or session recovery was automated; authenticated acceptance on this artifact is not claimed.

Subsequent owner-controlled login and direct screen inspection now accept Administrator home, force-stop/relaunch identity restoration and positive card/detail cover rendering on this artifact. Owner-confirmed republished test content was archived afterward as requested, preserving its cover and material row; final catalog empty. This supersedes authenticated-acceptance-pending above only within that scope. It does not establish actual TalkBack speech or native long-menu/tooltip behavior. See docs/PHASE2_DEVICE_ACCEPTANCE.md.

## Native probe and limits

The pre-fix installed emulator build rendered catalog controls at 840x1680 physical pixels/420 dpi (320 logical width), font_scale 2.0, with Search/Clear filters/Refresh wrapping into separate rows. ADB UI hierarchy identified Browse courses after the configuration-triggered activity recreation; no guessed target or account reset. Original 1080x2400/no size override and font_scale 1.0 were restored in finally and read back. Captures outside Git: E:/Android-prerequisites-Summit/sea-small-large-text.png and sea-native-large-text-catalog.png. This checks control layout only, not all card/detail states or text visibility below the captured viewport.

Actual TalkBack navigation/speech, contrast/reading-order audit, student account, native long-menu/tooltip interaction, later-page native matches, Huawei/iOS and signed-release acceptance remain open. Positive cover rendering on the current emulator/admin artifact was accepted in the subsequent checkpoint above; this does not establish student/anonymous cover denial. Owner-republished synthetic content was archived after testing with the owner's permission, preserving the cover and material.
