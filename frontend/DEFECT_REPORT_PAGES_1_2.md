# Defect Report — Pages 1 & 2

## P1P2-001

**Page:** Page 1 → Page 2  
**Severity / Priority:** High / P1  
**Title:** Onboarding CTAs prevented Android Back from returning to onboarding.  
**Preconditions:** Fresh launch at `/onboarding`.  
**Steps:** Tap **Get Started** or **Log In**, then use Android Back.  
**Expected:** Return to Page 1.  
**Actual:** The `go()` navigation replaced the route, so Back could exit instead.  
**Root cause:** Declarative route replacement was used for a forward, reversible journey.  
**Evidence:** `onboarding_screen.dart` prior implementation.  
**Recommended fix:** Push the auth route.  
**Fixed:** Yes — CTAs now use `context.push`.  
**Regression test:** `Android back from Page 2 returns to Page 1`.

## P1P2-002

**Page:** Page 2  
**Severity / Priority:** Critical / P0  
**Title:** Any syntactically valid password could log in to an existing local account.  
**Preconditions:** A local account exists.  
**Steps:** Enter its email and any six-character password.  
**Expected:** Authentication succeeds only with the account’s password.  
**Actual:** The original account record did not store or compare credentials.  
**Root cause:** Login only checked for existence of the email key.  
**Evidence:** `AuthScreen._submit` prior implementation.  
**Recommended fix:** Store a salted one-way password hash and verify it before activating the profile.  
**Fixed:** Yes — salted SHA-256 local-profile credential verification added.  
**Regression test:** `incorrect local password remains on Page 2 and shows a safe error`.

## P1P2-003

**Page:** Page 2  
**Severity / Priority:** Medium / P2  
**Title:** Social-provider controls are displayed but do nothing.  
**Preconditions:** Open Page 2.  
**Steps:** Tap Google, Apple, or Email.  
**Expected:** Begin the labelled sign-in journey or show that it is unavailable.  
**Actual:** Each button has an empty callback.  
**Root cause:** Placeholder controls were shipped as enabled actions.  
**Evidence:** `auth_screen.dart`, social `OutlinedButton.icon` callbacks.  
**Recommended fix:** Implement each provider or disable and label as unavailable.  
**Fixed:** Yes — the inactive provider controls were removed from the MVP.

## P1P2-004

**Page:** Page 2  
**Severity / Priority:** Medium / P2  
**Title:** Terms and Privacy Policy are presented as non-interactive text.  
**Expected:** Links open the appropriate policy or are not styled/presented as an agreement.  
**Actual:** No links or route actions exist.  
**Fixed:** No.
