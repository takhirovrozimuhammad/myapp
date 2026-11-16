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
    @Published var intent: String = ""
    @Published var emotion: String = "neutral"
    @Published var pendingMusic = false
    @Published var humming = false
    @Published var transcript = ""
    @Published var syllablePulse: Double = 0
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
            // Fix V4: use the device's supported input rate, prepare the file,
            // and record() rather than record(forDuration:), which failed on some phones.
            try session.setPreferredSampleRate(44100)
            let deviceRate = session.sampleRate >= 8000 ? session.sampleRate : 44100
            let newRecorder = try AVAudioRecorder(url: audioFile, settings: [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: deviceRate,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64000,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
            ])
            newRecorder.isMeteringEnabled = true
            guard newRecorder.prepareToRecord() && newRecorder.record() else {
                throw NSError(domain: "RoboPet", code: 1, userInfo: [NSLocalizedDescriptionKey: "Audio sessiya yozishni boshlamadi. Bluetooth qurilmani uzib, qayta sinang."])
            }
            recorder = newRecorder
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
            struct Response: Decodable {
                let reply: String
                let error: String?
                let intent: String?
                let emotion: String?
                let transcript: String?
            }
            let result = try JSONDecoder().decode(Response.self, from: responseData)
            guard (200...299).contains(http.statusCode) else {
                throw NSError(domain:"RoboPet",code:http.statusCode,
                              userInfo:[NSLocalizedDescriptionKey:result.error ?? "Mac server xatosi"])
            }
            guard !result.reply.isEmpty else { throw NSError(domain:"RoboPet",code:3,userInfo:[NSLocalizedDescriptionKey:"AI bo‘sh javob berdi."]) }
            transcript = result.transcript ?? ""
            intent = result.intent ?? ""
            emotion = result.emotion ?? "neutral"
            pendingMusic = intent == "music"
            if pendingMusic {
                speak("Musiqani qayerda qo‘yaman? Mac yoki iPhone?")
            } else {
                speak(result.reply)
            }
        } catch {
            phase = .idle
            errorText = "Ulanish: \(error.localizedDescription)"
        }
    }

    func chooseMusic(on target: String, server: String, code: String) {
        pendingMusic = false
        intent = ""
        if target == "iphone" {
            guard let url = URL(string: "music://") else { return }
            UIApplication.shared.open(url) { success in
                DispatchQueue.main.async {
                    if !success { self.errorText = "iPhone’da Music ilovasi ochilmadi." }
                }
            }
            return
        }
        let normalized = server.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = normalized.hasPrefix("http") ? normalized : "http://" + normalized
        guard let url = URL(string: base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/music") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue(code, forHTTPHeaderField: "X-RoboPet-Code")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["action": "play"])
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 500
                if code == 200 {
                    humming = true
                    emotion = "singing"
                    speak("Mac’da musiqa boshlandi.")
                } else {
                    let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                    errorText = obj?["error"] as? String ?? "Mac’da Music ilovasi ishlamadi."
                }
            } catch {
                errorText = "Musiqa: " + error.localizedDescription
            }
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

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                        willSpeakRangeOfSpeechString characterRange: NSRange,
                                        utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.syllablePulse = Double((characterRange.location % 7) + 2) / 10.0
        }
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
    @State private var pairStatus = "Mac bilan ulanish tekshirilmagan."
    @StateObject private var faceTracker = RoboPetFaceTracker()
    @StateObject private var weather = RoboPetWeather()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("RoboPet.cameraEnabled") private var cameraEnabled = true
    @AppStorage("RoboPet.customBG") private var customBG = "#FCE8E0"
    @AppStorage("RoboPet.customEye") private var customEye = "#57362F"
    @AppStorage("RoboPet.customNose") private var customNose = "#E897A6"
    @AppStorage("RoboPet.customMouth") private var customMouth = "#57362F"
    @State private var showCustomTheme = false
    @State private var editorBG: Color = .white
    @State private var editorEye: Color = .brown
    @State private var editorNose: Color = .pink
    @State private var editorMouth: Color = .brown
    @State private var sleeping = false
    @State private var infoPanel: String = ""

    private var themes: [CatPalette] {
        let custom = CatPalette(
            background: Color(robopetHex: customBG),
            eye: Color(robopetHex: customEye),
            eyeHighlight: Color(robopetHex: customEye),
            nose: Color(robopetHex: customNose),
            mouth: Color(robopetHex: customMouth),
            sparkle: .white
        )
        return CatPalette.all + [custom]
    }
    private var currentIndex: Int { min(max(paletteIndex, 0), themes.count - 1) }

    var body: some View {
        ZStack {
            if sleeping {
                sleepClock
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.35)) { sleeping = false }
                        if cameraEnabled { faceTracker.start() }
                    }
            } else {
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        faceCanvas(index: currentIndex)
                            .frame(width: infoPanel.isEmpty ? geo.size.width : geo.size.width * 0.5,
                                   height: geo.size.height)
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
                        if !infoPanel.isEmpty {
                            infoCard
                                .frame(width: geo.size.width * 0.5, height: geo.size.height)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                }
            }

            if !sleeping && themeGallery {
                themeGalleryView
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }

            if !sleeping && voice.pendingMusic && !themeGallery {
                musicChoice
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }

            if !sleeping && !themeGallery && !voice.pendingMusic, let message = voice.errorText {
                VStack {
                    Spacer()
                    Text(message)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.78), in: Capsule())
                        .onTapGesture { voice.errorText = nil }
                        .padding(.bottom, 10)
                }
                .allowsHitTesting(true)
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            if cameraEnabled { faceTracker.start() }
            verifyMac()
        }
        .onDisappear {
            faceTracker.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                UIApplication.shared.isIdleTimerDisabled = true
                if cameraEnabled && !sleeping { faceTracker.start() }
            } else {
                faceTracker.stop()
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
        .onChange(of: sleeping) { value in
            if value { faceTracker.stop() }
            else if cameraEnabled { faceTracker.start() }
        }
        .onChange(of: cameraEnabled) { enabled in
            if enabled && !sleeping { faceTracker.start() }
            else { faceTracker.stop() }
        }
        .onChange(of: voice.intent) { value in
            if value == "time" || value == "weather" {
                withAnimation(.spring(response: 0.52, dampingFraction: 0.86)) { infoPanel = value }
                if value == "weather" { weather.refresh() }
            } else if value == "music" {
                infoPanel = ""
            } else if value == "none" || value == "chat" {
                withAnimation { infoPanel = "" }
            }
        }
        .onReceive(Timer.publish(every: 12, on: .main, in: .common).autoconnect()) { _ in
            if !showMacSettings { verifyMac(silent: true) }
        }
        .onChange(of: showMacSettings) { open in
            if !open { verifyMac() }
        }
        .background(themes[currentIndex].background.ignoresSafeArea())
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
                    Section("Ulanish") {
                        Button("Ulanishni tekshirish") { verifyMac() }
                        Text(pairStatus).font(.footnote)
                    }
                    Section("Reaksiyalar") {
                        Toggle("Kamera orqali menga qarasin", isOn: $cameraEnabled)
                        Text(faceTracker.permission)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("Kamera tasvirlari telefonning o‘zida tahlil qilinadi va saqlanmaydi.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Section("Boshqarish") {
                        Text("Bir marta bosing: mikrofonni boshlash yoki yuborish. Uch soniya bosish: theme tanlash, Sleep Mode va sozlamalar.")
                            .font(.footnote)
                    }
                }
                .navigationTitle("RoboPet sozlamalari")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Tayyor") { showMacSettings = false }
                    }
                }
            }
        }
        .sheet(isPresented: $showCustomTheme) {
            NavigationStack {
                Form {
                    Section("O‘z theme’ingni yarat") {
                        ColorPicker("Fon", selection: $editorBG, supportsOpacity: false)
                        ColorPicker("Ko‘zlar", selection: $editorEye, supportsOpacity: false)
                        ColorPicker("Burun", selection: $editorNose, supportsOpacity: false)
                        ColorPicker("Og‘iz", selection: $editorMouth, supportsOpacity: false)
                    }
                    Section {
                        Text("Ranglar telefonda saqlanadi. Custom theme'ni istalgan payt o‘zgartirishing mumkin.")
                            .font(.footnote)
                    }
                }
                .navigationTitle("Custom theme")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Bekor qilish") { showCustomTheme = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Saqlash") {
                            customBG = editorBG.robopetHex
                            customEye = editorEye.robopetHex
                            customNose = editorNose.robopetHex
                            customMouth = editorMouth.robopetHex
                            paletteIndex = themes.count - 1
                            selectedTheme = paletteIndex
                            showCustomTheme = false
                            withAnimation { themeGallery = false }
                        }
                    }
                }
            }
        }
    }

    private var sleepClock: some View {
        TimelineView(.periodic(from: .now, by: 1)) { tick in
            GeometryReader { geo in
                ZStack {
                    Color(red: 0.026, green: 0.033, blue: 0.047)
                    VStack(spacing: 4) {
                        Text(tick.date, format: .dateTime.hour().minute())
                            .font(.system(size: min(geo.size.height * 0.56, geo.size.width * 0.3),
                                          weight: .ultraLight, design: .rounded))
                            .monospacedDigit()
                            .minimumScaleFactor(0.7)
                            .foregroundStyle(.white.opacity(0.94))
                        Text(tick.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.white.opacity(0.56))
                    }
                    .offset(x: sin(tick.date.timeIntervalSinceReferenceDate / 55) * 6,
                            y: cos(tick.date.timeIntervalSinceReferenceDate / 64) * 4)
                    VStack {
                        HStack {
                            Spacer()
                            Text("ROBO PET · SLEEP")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .tracking(2)
                                .foregroundStyle(.white.opacity(0.27))
                                .padding(25)
                        }
                        Spacer()
                        Text("Uyg‘otish uchun teging")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.30))
                            .padding(.bottom, 20)
                    }
                }
            }
        }
        .ignoresSafeArea()
    }

    private var infoCard: some View {
        ZStack {
            Color(red: 0.105, green: 0.11, blue: 0.14)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(infoPanel == "time" ? "SOAT" : "OB-HAVO")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.55))
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { infoPanel = "" }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 31, height: 31)
                            .background(.white.opacity(0.12), in: Circle())
                    }
                }
                Spacer(minLength: 0)
                if infoPanel == "time" {
                    TimelineView(.periodic(from: .now, by: 1)) { tick in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(tick.date, format: .dateTime.hour().minute())
                                .font(.system(size: 65, weight: .light, design: .rounded))
                                .monospacedDigit()
                                .minimumScaleFactor(0.7)
                                .lineLimit(1)
                                .foregroundStyle(.white)
                            Text(tick.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.white.opacity(0.65))
                        }
                    }
                } else {
                    Text(weather.temperature)
                        .font(.system(size: 68, weight: .light, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.7)
                    Text(weather.condition)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                    Text(weather.details)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                    if weather.loading {
                        ProgressView().tint(.white)
                    }
                }
                Spacer(minLength: 0)
                if infoPanel == "weather" {
                    Button {
                        weather.refresh()
                    } label: {
                        Label("Yangilash", systemImage: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
            }
            .padding(.vertical, 23)
            .padding(.horizontal, 24)
        }
    }

    private var musicChoice: some View {
        ZStack {
            Color.black.opacity(0.70).ignoresSafeArea()
            VStack(spacing: 13) {
                Text("♫ Musiqani qayerda qo‘yamiz?")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Mac’da Music ilovasini boshqarish yoki iPhone’da ochish")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.70))
                    .multilineTextAlignment(.center)
                HStack(spacing: 13) {
                    Button {
                        voice.chooseMusic(on: "mac", server: macServer, code: pairCode)
                    } label: {
                        Label("Mac", systemImage: "laptopcomputer")
                    }
                    .buttonStyle(PetCapsuleStyle(filled: true))
                    Button {
                        voice.chooseMusic(on: "iphone", server: macServer, code: pairCode)
                    } label: {
                        Label("iPhone", systemImage: "iphone")
                    }
                    .buttonStyle(PetCapsuleStyle(filled: true))
                }
                Button("Bekor qilish") {
                    voice.pendingMusic = false
                    voice.intent = ""
                }
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.75))
            }
            .padding(25)
            .frame(maxWidth: 470)
            .background(Color(red: 0.15, green: 0.16, blue: 0.20),
                        in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        }
    }

    private func openThemeEditor() {
        editorBG = Color(robopetHex: customBG)
        editorEye = Color(robopetHex: customEye)
        editorNose = Color(robopetHex: customNose)
        editorMouth = Color(robopetHex: customMouth)
        showCustomTheme = true
    }

    private func verifyMac(silent: Bool = false) {
        let address = macServer.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = pairCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty, !code.isEmpty else {
            if !silent { pairStatus = "Mac saytida ko‘rsatilgan IP va kodni kiriting." }
            return
        }
        let base = address.hasPrefix("http") ? address : "http://" + address
        guard let url = URL(string: base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/pair") else {
            if !silent { pairStatus = "IP manzil noto‘g‘ri." }
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 6
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "code": code, "device": "RoboPet iPhone"
        ])
        Task {
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    pairStatus = "Ulandi! Mac boshqaruv saytida ham ko‘rinadi."
                } else {
                    pairStatus = "Ulanmadi. Saytdagi kodni qayta tekshiring."
                }
            } catch {
                if !silent {
                    pairStatus = "Mac server topilmadi. Bir xil Wi-Fi va IP manzilini tekshiring."
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
                         catPalette: themes[index],
                         gazeX: faceTracker.gazeX,
                         gazeY: faceTracker.gazeY,
                         emotion: voice.emotion,
                         humming: voice.humming,
                         pulse: voice.syllablePulse)
            }
            .background(themes[index].background)
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
                    ForEach(themes.indices, id: \.self) { idx in
                        VStack(spacing: 9) {
                            faceCanvas(index: idx)
                                .frame(width: 430, height: 185)
                                .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 23).stroke(.white.opacity(0.25), lineWidth: 1))
                                .shadow(color: .black.opacity(0.35), radius: 15, y: 8)
                            Text(idx == 5 ? "Custom" : CatPalette.themeNames[idx])
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        .tag(idx)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .frame(maxWidth: .infinity, maxHeight: 240)

                HStack(spacing: 10) {
                    Button {
                        openThemeEditor()
                    } label: {
                        Label("Yangi theme", systemImage: "paintpalette")
                    }
                    .buttonStyle(PetCapsuleStyle(filled: false))

                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            themeGallery = false
                            sleeping = true
                        }
                    } label: {
                        Label("Sleep", systemImage: "moon.zzz")
                    }
                    .buttonStyle(PetCapsuleStyle(filled: false))

                    Button {
                        showMacSettings = true
                    } label: {
                        Label("Mac ulanishi", systemImage: "laptopcomputer")
                            .frame(minWidth: 87)
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

    private func drawFace(context: inout GraphicsContext, t: Double, happy: Bool, speaking: Bool, catPalette: CatPalette,
                          gazeX: CGFloat, gazeY: CGFloat, emotion: String, humming: Bool, pulse: Double) {
        let p = catPalette
        let blinkPhase = t.truncatingRemainder(dividingBy: 4.6)
        let blink: Double = blinkPhase < 0.18
            ? max(0.065, abs(blinkPhase - 0.09) / 0.09)
            : 1.0
        let expression: Double = (happy || emotion == "happy" || emotion == "excited") ? 0.69 :
            (emotion == "sleepy" ? 0.38 : emotion == "thinking" ? 0.82 : 1.0)
        let eyeShiftX = Double(gazeX) * 31 + sin(t * 0.72) * (abs(gazeX) < 0.03 ? 3.5 : 0.5)
        let eyeShiftY = -Double(gazeY) * 18 + sin(t * 0.47 + 0.6) * (abs(gazeY) < 0.03 ? 2.5 : 0.4)
        let bounce = sin(t * 1.43) * (humming ? 3.4 : 1.8)

        for left in [204.0, 516.0] {
            let eyeH = 140.0 * blink * expression
            let x = left + eyeShiftX
            let y = 79.0 + bounce + (140.0 - eyeH) / 2 + eyeShiftY
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

        if speaking || humming {
            let beat = humming ? 5.0 : 13.7
            let mouthSize = 7.0 + abs(sin(t * beat)) * (humming ? 13.0 : 19.0) * max(0.7, pulse)
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
