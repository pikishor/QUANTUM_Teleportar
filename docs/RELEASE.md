# Release checklist (iOS + Android)

Things a developer account, a person or a legal review must do — none of these can be done from code.

## Accounts and identity
- [ ] Apple Developer Program membership (annual fee) and App Store Connect app record
- [ ] Google Play Console developer account (one-time fee) and app record
- [ ] Pick the final bundle/package id and set it in `capacitor.config.json` (`appId`) — it cannot change after publishing
- [ ] Trademark search for the final game name; do not use third-party game names, characters or assets

## Builds
- [ ] iOS: needs macOS + Xcode (or a macOS CI runner). `npx cap sync ios`, set the signing team, archive, upload
- [ ] Android: Android Studio / Gradle. Create an upload keystore (**back it up, never commit it**), build an AAB (`./gradlew bundleRelease`)
- [ ] App icons and splash screens for every density (`@capacitor/assets` can generate them from one source image)
- [ ] Test on real devices — low/mid-range Android especially; set a frame-rate and memory budget

## Store listing
- [ ] Privacy policy URL (required by both stores, even if no data is collected)
- [ ] Age-rating questionnaires (IARC for Google Play; Apple's rating form). Stylized robot violence rates much lower than human-on-human violence
- [ ] Screenshots and a trailer per device class; short and long description; keywords
- [ ] Apple "Data Collection" nutrition label and Google "Data safety" form

## Money
- [ ] Decide the model: paid upfront, free + in-app purchases/battle pass, or ads
- [ ] Payments need real IAP wiring (StoreKit / Google Play Billing, or a wrapper such as RevenueCat) and server-side receipt checks
- [ ] Tax/banking set-up in both consoles

## Quality gates before submission
- [ ] Crash reporting and analytics (and the matching privacy disclosures)
- [ ] Pause on background/interruptions, audio focus, notch/safe-area handling, landscape lock
- [ ] Beta via TestFlight and Play internal/closed testing
