import SwiftUI
import AVFoundation

// RoboPet — native iPhone landscape face
// Tap: start/stop recording • 3-second hold: iOS-style theme gallery
@main
struct RoboPetApp: App {
    var body: some Scene {
        WindowGroup {
            RoboPetFace()
                .statusBarHidden()
                .persistentSystemOverlays(.hidden)
        }
    }
}

struct CatPalette {
    let background: Color
    let eye: Color
    let eyeHighlight: Color
    let nose: Color
    let mouth: Color
    let sparkle: Color
    static let themeNames = ["Peach", "Cream", "Lavender", "Mint", "Midnight"]
    static let all: [CatPalette] = [
        .init(background: Color(red: 1.00, green: 0.918, blue: 0.865),
              eye: Color(red: 0.31, green: 0.17, blue: 0.13),
              eyeHighlight: Color(red: 0.52, green: 0.32, blue: 0.23),
              nose: Color(red: 0.92, green: 0.61, blue: 0.59),
              mouth: Color(red: 0.34, green: 0.21, blue: 0.17),
              sparkle: .white),
        .init(background: Color(red: 1.00, green: 0.961, blue: 0.909),
              eye: Color(red: 0.31, green: 0.25, blue: 0.20),
              eyeHighlight: Color(red: 0.50, green: 0.39, blue: 0.30),
              nose: Color(red: 0.91, green: 0.67, blue: 0.66),
              mouth: Color(red: 0.32, green: 0.25, blue: 0.22),
              sparkle: .white),
        .init(background: Color(red: 0.914, green: 0.874, blue: 0.992),
              eye: Color(red: 0.35, green: 0.26, blue: 0.47),
              eyeHighlight: Color(red: 0.55, green: 0.43, blue: 0.68),
              nose: Color(red: 0.86, green: 0.63, blue: 0.73),
              mouth: Color(red: 0.35, green: 0.26, blue: 0.47),
              sparkle: .white),
        .init(background: Color(red: 0.878, green: 0.949, blue: 0.909),
              eye: Color(red: 0.20, green: 0.35, blue: 0.30),
              eyeHighlight: Color(red: 0.38, green: 0.54, blue: 0.43),
              nose: Color(red: 0.86, green: 0.62, blue: 0.63),
              mouth: Color(red: 0.20, green: 0.35, blue: 0.30),
              sparkle: .white),
        .init(background: Color(red: 0.032, green: 0.039, blue: 0.056),
              eye: Color(red: 0.92, green: 0.89, blue: 0.84),
              eyeHighlight: Color(red: 1.0, green: 0.98, blue: 0.94),
              nose: Color(red: 0.94, green: 0.62, blue: 0.66),
              mouth: Color(red: 0.94, green: 0.89, blue: 0.84),
              sparkle: Color(red: 1.0, green: 1.0, blue: 1.0))
    ]
}


enum VoicePhase: Equatable { case idle, recording, thinking, speaking }

@MainActor
final class RoboPetVoice: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var phase: VoicePhase = .idle
    @Published var errorText: String?
    private var recorder: AVAudioRecorder?
    private let synthesizer = AVSpeechSynthesizer()
    private let audioFile = FileManager.default.temporaryDirectory.appendingPathComponent("robopet-voice.m4a")

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func toggle(server: String, code: String) {
        switch phase {
        case .idle:
            guard !server.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                errorText = "3 soniya bosib turing → Mac sozlamalari orqali serverni ulang."
                return
            }
            AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                Task { @MainActor in
                    if allowed { self.beginRecording() }
                    else { self.errorText = "Settings → RoboPet → Microphone ruxsatini yoqing." }
                }
            }
        case .recording: finishRecording(server: server, code: code)
        case .speaking: synthesizer.stopSpeaking(at: .immediate); phase = .idle
        case .thinking: break
        }
    }

    private func beginRecording() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
            try? FileManager.default.removeItem(at: audioFile)
            recorder = try AVAudioRecorder(url: audioFile, settings: [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 16000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64000
            ])
            guard recorder?.record(forDuration: 30) == true else {
                throw NSError(domain: "RoboPet", code: 1, userInfo: [NSLocalizedDescriptionKey: "Mikrofonni boshlash imkonsiz."])
            }
            errorText = nil
            phase = .recording
        } catch {
            phase = .idle
            errorText = "Mikrofon xatosi: \(error.localizedDescription)"
        }
    }

    private func finishRecording(server: String, code: String) {
        recorder?.stop()
        recorder = nil
        do {
            let data = try Data(contentsOf: audioFile)
            guard data.count > 100 else {
                phase = .idle; errorText = "Ovoz yozilmadi. Qayta urinib ko‘ring."; return
            }
            phase = .thinking
            Task { await askMac(audio: data, server: server, code: code) }
        } catch {
            phase = .idle
            errorText = "Audio fayl o‘qilmadi: \(error.localizedDescription)"
        }
    }

    private func askMac(audio: Data, server: String, code: String) async {
        do {
            let normalized = server.trimmingCharacters(in: .whitespacesAndNewlines)
            let base = normalized.hasPrefix("http") ? normalized : "http://" + normalized
            guard let url = URL(string: base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/voice"),
                  ["http", "https"].contains(url.scheme ?? "") else {
                throw NSError(domain:"RoboPet",code:2,userInfo:[NSLocalizedDescriptionKey:"Mac IP manzili noto‘g‘ri."])
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 65
            request.setValue("audio/mp4", forHTTPHeaderField: "Content-Type")
            request.setValue(code, forHTTPHeaderField: "X-RoboPet-Code")
            request.httpBody = audio
            let (responseData, rawResponse) = try await URLSession.shared.data(for: request)
            guard let http = rawResponse as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            struct Response: Decodable { let reply: String; let error: String? }
            let result = try JSONDecoder().decode(Response.self, from: responseData)
            guard (200...299).contains(http.statusCode) else {
                throw NSError(domain:"RoboPet",code:http.statusCode,
                              userInfo:[NSLocalizedDescriptionKey:result.error ?? "Mac server xatosi"])
            }
            guard !result.reply.isEmpty else { throw NSError(domain:"RoboPet",code:3,userInfo:[NSLocalizedDescriptionKey:"AI bo‘sh javob berdi."]) }
            speak(result.reply)
        } catch {
            phase = .idle
            errorText = "Ulanish: \(error.localizedDescription)"
        }
    }

    private func speak(_ answer: String) {
        let utterance = AVSpeechUtterance(string: answer)
        // Native Uzbek voice depends on iOS voice availability.
        utterance.voice = AVSpeechSynthesisVoice(language: "uz-UZ")
            ?? AVSpeechSynthesisVoice(language: "tr-TR")
            ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.48
        utterance.pitchMultiplier = 1.05
        utterance.volume = 1.0
        phase = .speaking
        synthesizer.speak(utterance)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.phase = .idle }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.phase = .idle }
    }
}

struct RoboPetFace: View {
    @AppStorage("RoboPet.theme") private var paletteIndex = 0
    @AppStorage("RoboPet.macServer") private var macServer = ""
    @AppStorage("RoboPet.pairCode") private var pairCode = ""
    @StateObject private var voice = RoboPetVoice()
    @State private var themeGallery = false
    @State private var selectedTheme = 0
    @State private var showMacSettings = false

    private var currentIndex: Int { min(max(paletteIndex, 0), CatPalette.all.count - 1) }

    var body: some View {
        ZStack {
            faceCanvas(index: currentIndex)
                .contentShape(Rectangle())
                .gesture(
                    ExclusiveGesture(
                        LongPressGesture(minimumDuration: 3.0, maximumDistance: 36),
                        TapGesture()
                    ).onEnded { gesture in
                        switch gesture {
                        case .first:
                            selectedTheme = currentIndex
                            withAnimation(.spring(response: 0.43, dampingFraction: 0.85)) {
                                themeGallery = true
                            }
                        case .second:
                            voice.toggle(server: macServer, code: pairCode)
                        }
                    }
                )

            if themeGallery {
                themeGalleryView
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }

            if !themeGallery, let message = voice.errorText {
                VStack {
                    Spacer()
                    Text(message)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.78), in: Capsule())
                        .onTapGesture { voice.errorText = nil }
                        .padding(.bottom, 14)
                }
                .allowsHitTesting(true)
            }
        }
        .background(CatPalette.all[currentIndex].background.ignoresSafeArea())
        .ignoresSafeArea()
        .preferredColorScheme(.light)
        .sheet(isPresented: $showMacSettings) {
            NavigationStack {
                Form {
                    Section("Mac — RoboPet AI") {
                        TextField("192.168.1.5:8765", text: $macServer)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("Pairing code", text: $pairCode)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    Section {
                        Text("Mac va iPhone bitta Wi-Fi tarmog‘ida bo‘lsin. Mac terminalida start_mac.command ishga tushiring. Unda ko‘rsatilgan IP va kodni kiriting.")
                            .font(.footnote)
                    }
                    Section {
                        Text("Mushukcha yuzida bir marta bosing: yozish boshlanadi. Qayta bosing: savol AI ga yuboriladi. 3 soniya bosish: theme galereyasi.")
                            .font(.footnote)
                    }
                }
                .navigationTitle("Mac ulanishi")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Tayyor") { showMacSettings = false }
                    }
                }
            }
        }
    }

    private func faceCanvas(index: Int) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { tick in
            Canvas(rendersAsynchronously: true) { graphics, size in
                var ctx = graphics
                let scale = min(size.width / 844, size.height / 390)
                ctx.translateBy(x: size.width / 2, y: size.height / 2)
                ctx.scaleBy(x: scale, y: scale)
                ctx.translateBy(x: -422, y: -195)
                let t = tick.date.timeIntervalSinceReferenceDate
                drawFace(context: &ctx,
                         t: t,
                         happy: voice.phase == .recording,
                         speaking: voice.phase == .speaking,
                         catPalette: CatPalette.all[index])
            }
            .background(CatPalette.all[index].background)
        }
    }

    private var themeGalleryView: some View {
        ZStack {
            Color(red: 0.10, green: 0.105, blue: 0.12).opacity(0.985).ignoresSafeArea()
            VStack(spacing: 5) {
                HStack(spacing: 8) {
                    Image(systemName: "square.on.square").font(.system(size: 12))
                    Text("ROBO PET THEMES")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .tracking(1.2)
                }
                .foregroundStyle(.white.opacity(0.72))
                .padding(.top, 12)

                TabView(selection: $selectedTheme) {
                    ForEach(CatPalette.all.indices, id: \.self) { idx in
                        VStack(spacing: 9) {
                            faceCanvas(index: idx)
                                .frame(width: 450, height: 205)
                                .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 23).stroke(.white.opacity(0.25), lineWidth: 1))
                                .shadow(color: .black.opacity(0.35), radius: 15, y: 8)
                            Text(CatPalette.themeNames[idx])
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        .tag(idx)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .frame(maxWidth: .infinity, maxHeight: 265)

                HStack(spacing: 12) {
                    Button {
                        showMacSettings = true
                    } label: {
                        Label("Mac ulanishi", systemImage: "laptopcomputer")
                            .frame(minWidth: 126)
                    }
                    .buttonStyle(PetCapsuleStyle(filled: false))

                    Button {
                        paletteIndex = selectedTheme
                        withAnimation(.spring(response: 0.36, dampingFraction: 0.9)) {
                            themeGallery = false
                        }
                    } label: {
                        Label("Tanlash", systemImage: "checkmark")
                            .frame(minWidth: 126)
                    }
                    .buttonStyle(PetCapsuleStyle(filled: true))
                }
                .padding(.bottom, 14)
            }
            .padding(.horizontal, 20)
        }
    }

    private func drawFace(context: inout GraphicsContext, t: Double, happy: Bool, speaking: Bool, catPalette: CatPalette) {
        let p = catPalette
        let blinkPhase = t.truncatingRemainder(dividingBy: 4.6)
        let blink: Double = blinkPhase < 0.18
            ? max(0.065, abs(blinkPhase - 0.09) / 0.09)
            : 1.0
        let expression: Double = happy ? 0.55 : 1.0
        let gazeX = sin(t * 0.72) * 4.5
        let gazeY = sin(t * 0.47 + 0.6) * 3.5
        let bounce = sin(t * 1.43) * 1.8

        for left in [204.0, 516.0] {
            let eyeH = 140.0 * blink * expression
            let x = left + gazeX
            let y = 79.0 + bounce + (140.0 - eyeH) / 2 + gazeY
            let eyeRect = CGRect(x: x, y: y, width: 125, height: max(eyeH, 3))
            let r = min(46, eyeH * 0.36)
            let eyePath = Path(roundedRect: eyeRect, cornerRadius: r)
            context.fill(eyePath, with: .linearGradient(
                Gradient(colors: [p.eyeHighlight, p.eye, p.eye]),
                startPoint: CGPoint(x: x + 5, y: y - 5),
                endPoint: CGPoint(x: x + 112, y: y + 140)))

            if blink > 0.35 && !happy {
                let highlight = Path(ellipseIn: CGRect(
                    x: x + 24, y: y + 17, width: 42, height: 34))
                context.fill(highlight, with: .color(p.sparkle.opacity(0.98)))
                let tiny = Path(ellipseIn: CGRect(
                    x: x + 99, y: y + eyeH - 39, width: 10, height: 10))
                context.fill(tiny, with: .color(p.sparkle.opacity(0.70)))
            }
        }

        // Tiny pink kitten nose.
        var nose = Path()
        nose.move(to: CGPoint(x: 410, y: 217))
        nose.addQuadCurve(to: CGPoint(x: 434, y: 217), control: CGPoint(x: 422, y: 213))
        nose.addQuadCurve(to: CGPoint(x: 425, y: 232), control: CGPoint(x: 438, y: 222))
        nose.addQuadCurve(to: CGPoint(x: 419, y: 232), control: CGPoint(x: 422, y: 235))
        nose.addQuadCurve(to: CGPoint(x: 410, y: 217), control: CGPoint(x: 406, y: 222))
        context.fill(nose, with: .color(p.nose))

        // Real kitten-style ω mouth.
        var mouth = Path()
        mouth.move(to: CGPoint(x: 422, y: 231))
        mouth.addCurve(to: CGPoint(x: 395, y: 248),
                       control1: CGPoint(x: 419, y: 249), control2: CGPoint(x: 401, y: 254))
        mouth.addQuadCurve(to: CGPoint(x: 392, y: 241),
                           control: CGPoint(x: 391, y: 247))
        mouth.move(to: CGPoint(x: 422, y: 231))
        mouth.addCurve(to: CGPoint(x: 449, y: 248),
                       control1: CGPoint(x: 425, y: 249), control2: CGPoint(x: 443, y: 254))
        mouth.addQuadCurve(to: CGPoint(x: 452, y: 241),
                           control: CGPoint(x: 453, y: 247))
        context.stroke(mouth, with: .color(p.mouth), style: StrokeStyle(lineWidth: 5.5, lineCap: .round))

        if speaking {
            let mouthSize = 8.0 + abs(sin(t * 13.7)) * 18.0
            let oval = Path(ellipseIn: CGRect(
                x: 422 - mouthSize * 0.55,
                y: 255,
                width: mouthSize * 1.1,
                height: mouthSize))
            context.fill(oval, with: .color(p.eye))
            let tongue = Path(ellipseIn: CGRect(
                x: 422 - mouthSize * 0.32,
                y: 255 + mouthSize * 0.54,
                width: mouthSize * 0.64,
                height: mouthSize * 0.35))
            context.fill(tongue, with: .color(p.nose))
        }
    }
}

struct PetCapsuleStyle: ButtonStyle {
    var filled: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(filled ? .black : .white)
            .padding(.horizontal, 17)
            .padding(.vertical, 10)
            .background(filled ? Color.white : Color.white.opacity(0.14), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
