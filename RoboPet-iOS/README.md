# RoboPet iPhone (native SwiftUI demo)

Real iOS landscape app. Full-screen peach cat face with brown rounded eyes, pink kitten nose and omega mouth.

- **Tap:** cute happy expression
- **Double tap:** cycle peach / cream / lavender / mint
- **Press and hold:** talking mouth animation
- Idle gaze and periodic blinking at approximately 60 FPS
- iPhone landscape only, with status bar hidden
- Bundle ID: `com.ridzhan.robopet`

## Building on GitHub
This branch contains `.github/workflows/build-robopet-ipa.yml`. A push triggers macOS Xcode build and saves `RoboPet-unsigned.ipa` in the **Actions → Artifacts** section.

**Important:** The artifact is an **unsigned IPA**. It cannot be directly installed by tapping on iPhone. A normal iPhone install requires signing with an Apple ID (e.g., using AltStore/Sideloadly) or Apple Developer certificates. This workflow cannot sign the app without the user's credentials.

## What's included
This is specifically an app for **testing the RoboPet animated UI**. The Kimi AI and Mac server networking are present in the separate Expo source archive previously delivered, but are not yet integrated into this native SwiftUI preview.

For a signed device build on a Mac with Xcode and an Apple ID, open the generated project after running `xcodegen generate`, choose the personal development team in Signing & Capabilities, then Run on the iPhone.
