# RoboPet — iPhone 12 cat-face AI assistant 🐱

Native SwiftUI app for iOS 16+ and landscape iPhone screens.

## Controls

- **Tap once:** start recording an audio message (microphone permission required).
- **Tap again:** stop recording, send audio to the Mac AI server, and hear an AI answer through the iPhone speaker.
- **Hold the screen for 3 seconds:** open the **iPhone Lock Screen–style theme gallery**.
- **Swipe horizontally:** browse **Peach / Cream / Lavender / Mint / Midnight (black background)**.
- **Tap Tanlash:** apply and save the selected theme.
- **Mac ulanishi** in the gallery: enter the Mac's local IP, port and pairing code.

The face remains full-screen with only the eyes, pink kitten nose, and omega mouth when idle. Eyes blink and move. When listening it reacts; the mouth animates while speaking.

## Connect free Gemini AI through your Mac (Python 3 only)

1. Visit https://aistudio.google.com/apikey and create a Gemini API key (requires a supported account and region). Gemini **2.5 Flash** has a limited free-tier API quota; not unlimited.
2. Copy `.env.example` to `.env` and put the **key only inside this Mac file**:
   ```bash
   cd RoboPet-iOS
   cp .env.example .env
   # edit .env and set GEMINI_API_KEY=...
   bash start_mac.command
   ```
3. In Terminal, you will see the local Mac IP:port and generated pairing code.
4. Connect iPhone and Mac to the **same Wi-Fi network**.
5. Open RoboPet on iPhone, press the face for 3 seconds, tap **Mac ulanishi**, enter the IP:port and pairing code, tap **Tayyor**, then **Tanlash**.
6. Tap the face to record, and tap again to send the message. The Mac sends audio directly to Gemini to transcribe/understand it and return an answer; the iPhone says the answer using its **built-in voice**.

**No API key is stored in the iPhone app or in GitHub.** The audio is sent over your local Wi-Fi to the Mac and from there to Google's Gemini API. Use a trusted home Wi-Fi; local HTTP is enabled for development.

### Note about speech voice quality
The AI understands Uzbek audio (capability depends on speech quality and model support), but the app uses Apple's `AVSpeechSynthesizer` for spoken output. The system may not have a built-in Uzbek voice. In that case the app falls back to Turkish and then English voices, which can pronounce Uzbek imperfectly. A higher-quality Uzbek TTS service is a later enhancement. Continuous hands-free wake-word listening is **not** included in this version.

## GitHub IPA

GitHub Actions on a public repository uses `macos-latest` to compile SwiftUI with Xcode and produces **RoboPet-unsigned.ipa** as an Actions artifact.
- An unsigned IPA is **not installable directly**; it must be signed with your Apple ID using the usual iOS deployment/sideloading tools, or by Xcode with a development team.
- We do not store Apple signing identities in the repo.

This app is a prototype for UI and voice chat. Music, room lighting, reminders, real-time weather and other Mac tools are **not yet implemented**, and the model is not allowed to claim they were executed.

## Safety and privacy

Never paste `GEMINI_API_KEY` into a public repository. The local pairing code should be kept private. There is currently no HTTPS on the local network; only use a network you trust.
