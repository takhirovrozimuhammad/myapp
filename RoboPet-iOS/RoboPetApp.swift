import SwiftUI

// RoboPet — native iPhone landscape face
// Tap: smile • Double tap: palette • Hold: speaking animation
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
              sparkle: .white)
    ]
}

struct RoboPetFace: View {
    @State private var paletteIndex = 0
    @State private var happyUntil = Date.distantPast
    @State private var isSpeaking = false

    private var palette: CatPalette { CatPalette.all[paletteIndex] }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let happy = timeline.date < happyUntil

            GeometryReader { geo in
                Canvas(rendersAsynchronously: true) { graphics, size in
                    var context = graphics
                    let s = min(size.width / 844.0, size.height / 390.0)
                    context.translateBy(x: size.width / 2, y: size.height / 2)
                    context.scaleBy(x: s, y: s)
                    context.translateBy(x: -422, y: -195)
                    drawFace(context: &context, t: t, happy: happy, speaking: isSpeaking)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    paletteIndex = (paletteIndex + 1) % CatPalette.all.count
                }
                .onTapGesture {
                    happyUntil = Date().addingTimeInterval(1.35)
                }
                .onLongPressGesture(minimumDuration: 0.35, maximumDistance: 28,
                                    pressing: { pressed in isSpeaking = pressed },
                                    perform: {})
                .accessibilityLabel("RoboPet cat face. Tap to smile, double tap to change color, press and hold to talk.")
            }
        }
        .background(palette.background.ignoresSafeArea())
        .ignoresSafeArea()
        .preferredColorScheme(.light)
    }

    private func drawFace(context: inout GraphicsContext, t: Double, happy: Bool, speaking: Bool) {
        let p = palette
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
