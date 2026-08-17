# Page 1 & 2 Test Matrix

Page 1 is the `/onboarding` welcome screen. Page 2 is `/auth`, the local sign-up/log-in screen.

| ID | Priority | Requirement / scenario | Automated coverage | Result |
|---|---|---|---|---|
| P1-F01 | P0 | App entry renders onboarding when no active account exists | `Page 1 renders both routes...` | Pending execution |
| P1-F02 | P0 | Get Started opens sign-up | `Page 1 renders both routes...` | Pending execution |
| P1-F03 | P1 | Log In opens login | Code review; same route mode mapping | Pass (static) |
| P1-F04 | P1 | Back from Page 2 returns Page 1 | `Android back from Page 2...` | Pending execution |
| P1-A01 | P2 | Primary/secondary CTAs are named and full-width / visible | Widget structure review | Pass (static) |
| P2-F01 | P0 | Sign-up form validates required fields | `Page 2 shows form validation...` | Pending execution |
| P2-F02 | P1 | Password confirmation mismatch is rejected | `Page 2 shows form validation...` | Pending execution |
| P2-F03 | P0 | Valid sign-up persists profile and navigates to home | `valid sign-up stores...` | Pending execution |
| P2-F04 | P0 | Incorrect password cannot authenticate | `incorrect local password...` | Pending execution |
| P2-F07 | P0 | Correct password activates the matching account | `correct local password activates...` | Pending execution |
| P2-F08 | P1 | Phone number is accepted and normalized for lookup | `email and phone identifiers validate...` | Pending execution |
| P2-F05 | P1 | Duplicate email is rejected | Existing `AuthScreen._submit` branch | Pass (static) |
| P2-F06 | P1 | Submit disables during progress, preventing duplicate request | Existing `_isSubmitting` guard | Pass (static) |
| P2-S01 | P1 | Password is not persisted in clear text | `password hashing is deterministic...`; sign-up persistence test | Pending execution |
| E2E-01 | P0 | Page 1 → sign-up Page 2 → Home | `valid sign-up stores...` | Pending execution |
| NAV-01 | P1 | Direct `/auth` navigation has no prerequisite and does not crash | Router review | Pass (static) |

Not applicable: network failure, timeout, HTTP errors, third-party social sign-in, deep links, and external authentication are not implemented by these two screens. Placeholder social controls were removed from the MVP.
