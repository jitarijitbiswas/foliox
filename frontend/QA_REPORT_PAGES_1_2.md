# PaperTrade QA Report
## Pages 1 & 2

## 1. Executive Summary

The Android app is implemented in Flutter, not Kotlin/Compose. Page 1 is the local onboarding screen (`/onboarding`); Page 2 is the local account sign-up/log-in screen (`/auth`). Two defects were fixed: reversible navigation and password verification. Focused automated tests were added, but their final execution result is blocked by the Flutter test compiler not completing in the available terminal window.

## 2. Application Version / Commit

Version `1.0.0+1`; commit `409ddc8` before this QA change.

## 3. Environment

- Flutter project: `frontend`
- Android Gradle Plugin: `9.0.1`; Kotlin: `2.3.20`; Gradle: `9.1.0`
- Android min SDK: 24; compile/target SDK: Flutter tool defaults (not pinned in the project)
- UI: Flutter Material widgets; navigation: `go_router`; state/DI: Riverpod
- Persistence: Hive (`foliox_settings` and `foliox_account`)
- Networking: Dio; test framework: `flutter_test`
- Android SDK platform tools (`adb`) are not available on PATH, so instrumentation, lifecycle, rotation, font-scale, screen-size, screenshot, Logcat, cold-start, and ANR validation are blocked.

## 4. Page 1 Scope

`/onboarding` → `OnboardingScreen`; no ViewModel/repository. It renders artwork, marketing copy, **Get Started**, and **Log In**. Both CTAs now push `/auth` with a mode argument.

## 5. Page 2 Scope

`/auth` → `AuthScreen`; no ViewModel/repository. It validates local account forms, stores account metadata in Hive, activates the selected local profile, and navigates to `/home`. The related OAuth `AuthController`/`AuthRepository` exists but is not wired to this screen.

## 6. Test Strategy

Added `test/onboarding_auth_flow_test.dart`: password-hash and email/phone identifier coverage plus Page 1 rendering/navigation, Page 2 validation, successful persistence/navigation, correct/incorrect-password handling, and Android Back regression coverage. The tests use deterministic fake identities and isolated temporary Hive storage.

## 7. Automated Tests

Eight focused tests were authored. Final status is **BLOCKED**, not passed: the test process remained compiling/running without test result output in the terminal window. No test result has been fabricated.

## 8. Integration Tests

The valid sign-up test exercises Page 2 + Hive + navigation to a stub Home route. Its execution remains blocked as above.

## 9. UI Tests

Widget assertions cover visible labels, form errors, error messaging, and navigation. Device-level UI testing is blocked by no attached emulator/device.

## 10. E2E Tests

The Page 1 → Page 2 → Home path is included in the widget suite; execution pending.

## 11. Accessibility

Positive static findings: password visibility has tooltips; text fields use visible labels; `SafeArea` and a scroll view reduce keyboard/viewport risk; primary CTA is 54dp high. Not executed: TalkBack, focus order, contrast instrumentation, 1.3/1.5 font scales, physical touch target measurements.

## 12. Security Review

No `print`, `debugPrint`, `Log.*`, or stack-trace calls were found around these flows. P2 credentials are now salted and one-way hashed before Hive persistence; plaintext passwords are not stored. Remaining concern: the app stores profile/auth state locally in Hive without platform-backed encryption, so it should not be represented as production-grade authentication. OAuth token handling is outside the wired Page 1/2 journey and should receive a separate secure-storage review.

## 13. Performance Review

No measurable on-device startup/render metrics were available. The local workflow intentionally has a 900ms loading delay; the submit button is disabled while it runs. No recomposition or memory-leak issue was demonstrated by static review.

## 14. Test Results

| Area | Status |
|---|---|
| Build | BLOCKED — not completed in terminal window |
| Unit/widget suite | BLOCKED — Flutter test runner did not complete |
| Integration | BLOCKED — embedded in focused widget suite |
| UI instrumentation | BLOCKED — no device/emulator |
| E2E | BLOCKED — embedded in focused widget suite |
| Lint | BLOCKED — execution not completed |

## 15. Defects

Four findings: three fixed (one P0, one P1, one P2) and one remaining P2 policy-link issue. See `DEFECT_REPORT_PAGES_1_2.md`.

## 16. Coverage

No coverage reporter is configured. Six targeted automated tests were added; no coverage percentage is claimed.

## 17. Blocked Tests

The Flutter test process did not emit a completion result within the command execution window. Android instrumentation also cannot run without a connected device/emulator.

## 18. Recommendations

Make policy links actionable; move real session credentials to platform secure storage; add CI with Flutter widget tests and an Android emulator lane.

## 19. Final QA Verdict

**BLOCKED** — fixed code and tests are present, but the full evidence required for a PASS/PASS WITH WARNINGS verdict could not be obtained in this environment.
