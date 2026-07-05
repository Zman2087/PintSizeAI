# PintSize AI — release / submission checklist

## Already done (in the codebase)
- [x] Real bundle identifier: `com.pintsize.ai`
- [x] Privacy manifest `ios/Runner/PrivacyInfo.xcprivacy` (added to Runner resources)
- [x] `ITSAppUsesNonExemptEncryption = false` in Info.plist
- [x] All permission usage strings present (camera, mic, speech, photo library)
- [x] App icon (all sizes) — brain mark
- [x] Display name "PintSize AI"
- [x] 0 analyzer errors; app code warning-free; 60 unit tests pass

## Before you submit
- [ ] **Host a privacy policy** at a public URL and put it in App Store Connect.
      (The text exists in-app under Settings ▸ Legal ▸ Privacy Policy — publish
      it, e.g. GitHub Pages, and link it.)
- [ ] **Paid Apple Developer account** ($99/yr) — required to ship, and to enable
      the coded-but-gated features (Share Extension, Home-screen Widget, iCloud).
- [ ] **Bump version** for each submission: edit `version:` in pubspec.yaml
      (e.g. `1.0.0+1` → `1.0.1+2`). The `+N` build number must increase every
      upload.
- [ ] (Optional) Disable debug diagnostics: `DiagLog` writes a small capped log;
      fine to leave, or make `DiagLog.log` a no-op for the store build.
- [ ] **Screenshots** (required per device size). Capture on a 6.7" and 6.5"
      iPhone (and 5.5" if supporting older): the chat screen, Voice Mode, the
      Models/Discover screen, and an image-generation result. 3–10 each.
- [ ] Fill App Privacy = "No data collected" (see PRIVACY_AND_DATA.md).
- [ ] Set age rating (see APP_STORE_LISTING.md — 17+ recommended because users
      can download uncensored community models).
- [ ] Paste listing copy from APP_STORE_LISTING.md.

## Build & upload
```
# clean signed archive for the App Store
flutter build ipa --release
# then open the archive in Xcode Organizer (or use Transporter) to upload,
# or: xcrun altool / notarytool per current Apple tooling.
open build/ios/archive/Runner.xcarchive   # if produced
```
Alternatively archive from Xcode: open `ios/Runner.xcworkspace` ▸ Product ▸
Archive ▸ Distribute App ▸ App Store Connect.

## Nice-to-have before 1.0 (not blockers)
- [ ] Verify LLaVA vision on-device with a downloaded vision model
- [ ] Test light mode on-device across all screens
- [ ] TestFlight beta round
