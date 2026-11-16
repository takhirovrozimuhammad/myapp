import Foundation
import SwiftUI
import UIKit
import Vision
import AVFoundation
import CoreLocation
import ImageIO

// No face images leave the phone. The camera feed is processed locally,
// and only the position of the largest detected face is retained in RAM.
final class RoboPetFaceTracker: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var gazeX: CGFloat = 0
    @Published var gazeY: CGFloat = 0
    @Published var permission: String = "Kamera ruxsati so‘ralmagan"
    private let session = AVCaptureSession()
    private let captureQueue = DispatchQueue(label: "robopet.camera.capture", qos: .utility)
    private let framesQueue = DispatchQueue(label: "robopet.camera.vision", qos: .utility)
    private var configured = false
    private var lastFrame: TimeInterval = 0

    func start() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .authorized {
            configureAndStart()
        } else if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.permission = granted ? "Kamera ishlayapti" : "Kamera ruxsati o‘chirilgan"
                }
                if granted { self?.configureAndStart() }
            }
        } else {
            DispatchQueue.main.async { self.permission = "Settings → RoboPet → Camera ruxsati kerak" }
        }
    }

    func stop() {
        captureQueue.async { [weak self] in
            guard let self = self else { return }
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    private func configureAndStart() {
        captureQueue.async { [weak self] in
            guard let self = self else { return }
            if !self.configured {
                guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
                    DispatchQueue.main.async { self.permission = "Old kamera topilmadi" }
                    return
                }
                do {
                    self.session.beginConfiguration()
                    self.session.sessionPreset = .low
                    let input = try AVCaptureDeviceInput(device: camera)
                    if self.session.canAddInput(input) { self.session.addInput(input) }
                    let output = AVCaptureVideoDataOutput()
                    output.alwaysDiscardsLateVideoFrames = true
                    output.setSampleBufferDelegate(self, queue: self.framesQueue)
                    if self.session.canAddOutput(output) { self.session.addOutput(output) }
                    self.session.commitConfiguration()
                    self.configured = true
                } catch {
                    self.session.commitConfiguration()
                    DispatchQueue.main.async { self.permission = "Kamera: " + error.localizedDescription }
                    return
                }
            }
            if !self.session.isRunning { self.session.startRunning() }
            DispatchQueue.main.async { self.permission = "Kamera ishlayapti" }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let t = ProcessInfo.processInfo.systemUptime
        guard t - lastFrame > 0.11 else { return } // ~9 fps, lower energy usage
        lastFrame = t
        guard let frame = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let req = VNDetectFaceRectanglesRequest()
        do {
            let handler = VNImageRequestHandler(cvPixelBuffer: frame, orientation: .leftMirrored, options: [:])
            try handler.perform([req])
            if let face = req.results?.max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }) {
                let x = (CGFloat(face.boundingBox.midX) - 0.5) * 2
                let y = (CGFloat(face.boundingBox.midY) - 0.5) * 2
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.2)) {
                        self.gazeX = min(max(x, -1), 1)
                        self.gazeY = min(max(y, -1), 1)
                    }
                }
            } else {
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 1.1)) {
                        self.gazeX = 0
                        self.gazeY = 0
                    }
                }
            }
        } catch {
            // A single dropped or undetected frame should not interrupt animations.
        }
    }
}

final class RoboPetWeather: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var temperature: String = "—"
    @Published var condition: String = "Ob-havo tekshirilmoqda..."
    @Published var details: String = ""
    @Published var loading = false
    private let location = CLLocationManager()

    override init() {
        super.init()
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func refresh() {
        loading = true
        switch location.authorizationStatus {
        case .notDetermined:
            location.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            location.requestLocation()
        default:
            loading = false
            condition = "Ob-havo uchun joylashuv ruxsatini yoqing."
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        } else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            DispatchQueue.main.async {
                self.loading = false
                self.condition = "Settings orqali Location ruxsatini yoqing."
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coord = locations.last?.coordinate else { return }
        let query = "https://api.open-meteo.com/v1/forecast?latitude=\(coord.latitude)&longitude=\(coord.longitude)&current=temperature_2m,relative_humidity_2m,weather_code&timezone=auto"
        guard let url = URL(string: query) else { return }
        URLSession.shared.dataTask(with: url) { data, _, error in
            DispatchQueue.main.async { self.loading = false }
            guard let data = data, error == nil else {
                DispatchQueue.main.async { self.condition = "Internet yoki ob-havo xizmati ishlamayapti." }
                return
            }
            struct Current: Decodable {
                let temperature_2m: Double
                let relative_humidity_2m: Double
                let weather_code: Int
            }
            struct Forecast: Decodable { let current: Current }
            guard let result = try? JSONDecoder().decode(Forecast.self, from: data) else {
                DispatchQueue.main.async { self.condition = "Ob-havo ma’lumotini o‘qib bo‘lmadi." }
                return
            }
            DispatchQueue.main.async {
                self.temperature = "\(Int(result.current.temperature_2m.rounded()))°"
                self.details = "Namlik \(Int(result.current.relative_humidity_2m))%"
                let code = result.current.weather_code
                switch code {
                case 0: self.condition = "Ochiq osmon"
                case 1...3: self.condition = "Bulutli"
                case 45,48: self.condition = "Tumanli"
                case 51...67: self.condition = "Yomg‘irli"
                case 71...77: self.condition = "Qorli"
                case 80...82: self.condition = "Yomg‘ir"
                case 95...99: self.condition = "Momaqaldiroq"
                default: self.condition = "Hozirgi ob-havo"
                }
            }
        }.resume()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.loading = false
            self.condition = "Joylashuvni aniqlab bo‘lmadi."
        }
    }
}

extension Color {
    init(robopetHex hex: String) {
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let number = Int(trimmed, radix: 16) ?? 0
        self.init(
            red: Double((number >> 16) & 255) / 255,
            green: Double((number >> 8) & 255) / 255,
            blue: Double(number & 255) / 255
        )
    }
    var robopetHex: String {
        let color = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else { return "#F9E9DA" }
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
