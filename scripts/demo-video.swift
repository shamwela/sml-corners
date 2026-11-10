// Renders the SML Corners demo video entirely in code (no screen recording),
// with music and sound effects that are also synthesized here, so there is no licensed audio.
//
//   swiftc -O scripts/demo-video.swift -o build/demo-video
//   build/demo-video media/sml-corners-demo.mp4           # full video with audio
//   build/demo-video --frames DIR 1.5,5.2,6.8              # PNG stills at given story seconds
//
// Output: 1080x1080, 30 fps, H.264 + AAC. Square plays well in the LinkedIn feed.

import AppKit
import AVFoundation

let W = 1080.0, H = 1080.0, FPS = 30.0

// MARK: - Timing
//
// Animations are written on a 15 s "story" clock. Playback is slowed by SLOW and paused at
// `holds` (story time, real seconds) so every caption stays on screen long enough to read.

let STORY = 15.0
let SLOW = 1.25
let holds: [(at: Double, seconds: Double)] = [
    (1.95, 1.4),   // all four keys + "Four keys. Every time."
    (3.45, 1.0),   // "Now it's one press."
    (4.35, 0.5),   // "Press the top-right corner", before the finger moves
    (7.95, 1.2),   // "Copied. Ready to paste."
    (11.45, 0.9),  // "Top left? Open any app."
    (15.0, 2.0),   // end card
]
let DURATION = STORY * SLOW + holds.reduce(0) { $0 + $1.seconds }

/// Real playback time -> story time.
func storyTime(_ real: Double) -> Double {
    var realCursor = 0.0, storyCursor = 0.0
    for hold in holds {
        let segment = (hold.at - storyCursor) * SLOW
        if real < realCursor + segment { return storyCursor + (real - realCursor) / SLOW }
        realCursor += segment
        if real < realCursor + hold.seconds { return hold.at }
        realCursor += hold.seconds
        storyCursor = hold.at
    }
    return min(storyCursor + (real - realCursor) / SLOW, STORY)
}

/// Story time -> real playback time (for placing sound effects).
func realTime(_ story: Double) -> Double {
    story * SLOW + holds.filter { $0.at < story }.reduce(0) { $0 + $1.seconds }
}

// MARK: - Helpers

func rgb(_ hex: UInt32, _ alpha: Double = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

let background = rgb(0x0B0D12)
let accent = rgb(0x3B82F6)
let white = rgb(0xFFFFFF)
let muted = rgb(0x9AA3B2)

func clamp01(_ x: Double) -> Double { min(max(x, 0), 1) }
func prog(_ t: Double, _ a: Double, _ b: Double) -> Double { clamp01((t - a) / (b - a)) }
func ease(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
func easeOutBack(_ x: Double) -> Double {
    let c1 = 1.70158, c3 = c1 + 1
    return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
}
func lerp(_ a: CGPoint, _ b: CGPoint, _ p: Double) -> CGPoint {
    CGPoint(x: a.x + (b.x - a.x) * p, y: a.y + (b.y - a.y) * p)
}
/// 0 before `a`, fades to 1, holds, fades back to 0 by `b`.
func visible(_ t: Double, _ a: Double, _ b: Double, fade: Double = 0.3) -> Double {
    min(prog(t, a, a + fade), 1 - prog(t, b - fade, b))
}

var c: CGContext!

func roundPath(_ r: CGRect, _ radius: Double) -> CGPath {
    let radius = min(radius, r.width / 2, r.height / 2)
    return CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func fill(_ r: CGRect, radius: Double = 0, _ color: NSColor, alpha: Double = 1) {
    c.saveGState()
    c.setAlpha(alpha)
    c.setFillColor(color.cgColor)
    c.addPath(roundPath(r, radius))
    c.fillPath()
    c.restoreGState()
}

func stroke(_ r: CGRect, radius: Double = 0, _ color: NSColor, width: Double, alpha: Double = 1, dash: [CGFloat] = []) {
    c.saveGState()
    c.setAlpha(alpha)
    c.setStrokeColor(color.cgColor)
    c.setLineWidth(width)
    if !dash.isEmpty { c.setLineDash(phase: 0, lengths: dash) }
    c.addPath(roundPath(r, radius))
    c.strokePath()
    c.restoreGState()
}

func circle(_ center: CGPoint, _ r: Double, fill color: NSColor? = nil, stroke strokeColor: NSColor? = nil,
            width: Double = 2, alpha: Double = 1) {
    let rect = CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)
    c.saveGState()
    c.setAlpha(alpha)
    if let color { c.setFillColor(color.cgColor); c.fillEllipse(in: rect) }
    if let strokeColor { c.setStrokeColor(strokeColor.cgColor); c.setLineWidth(width); c.strokeEllipse(in: rect) }
    c.restoreGState()
}

func withShadow(blur: Double, y: Double = 6, alpha: Double = 0.45, _ draw: () -> Void) {
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -y), blur: blur, color: NSColor.black.withAlphaComponent(alpha).cgColor)
    draw()
    c.restoreGState()
}

func withAlpha(_ alpha: Double, _ draw: () -> Void) {
    guard alpha > 0.001 else { return }
    c.saveGState()
    c.setAlpha(alpha)
    c.beginTransparencyLayer(auxiliaryInfo: nil)
    draw()
    c.endTransparencyLayer()
    c.restoreGState()
}

func scaled(_ s: Double, around p: CGPoint, _ draw: () -> Void) {
    c.saveGState()
    c.translateBy(x: p.x, y: p.y)
    c.scaleBy(x: s, y: s)
    c.translateBy(x: -p.x, y: -p.y)
    draw()
    c.restoreGState()
}

enum Align { case left, center, right }

func text(_ parts: [(String, NSColor)], at p: CGPoint, size: Double, weight: NSFont.Weight = .semibold,
          align: Align = .center, mono: Bool = false, alpha: Double = 1) {
    guard alpha > 0.001 else { return }
    let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        : NSFont.systemFont(ofSize: size, weight: weight)
    let string = NSMutableAttributedString()
    for (s, color) in parts {
        string.append(NSAttributedString(string: s, attributes: [
            .font: font, .foregroundColor: color.withAlphaComponent(color.alphaComponent * alpha),
        ]))
    }
    let size = string.size()
    let x: Double
    switch align {
    case .left: x = p.x
    case .center: x = p.x - size.width / 2
    case .right: x = p.x - size.width
    }
    string.draw(at: CGPoint(x: x, y: p.y - size.height / 2))
}

func text(_ s: String, at p: CGPoint, size: Double, weight: NSFont.Weight = .semibold, color: NSColor = white,
          align: Align = .center, mono: Bool = false, alpha: Double = 1) {
    text([(s, color)], at: p, size: size, weight: weight, align: align, mono: mono, alpha: alpha)
}

func symbol(_ name: String, in rect: CGRect, color: NSColor) {
    let config = NSImage.SymbolConfiguration(pointSize: rect.height, weight: .semibold)
        .applying(.init(paletteColors: [color]))
    guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(config) else { return }
    image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
}

// MARK: - Layout

enum Corner: CaseIterable { case topLeft, topRight, bottomLeft, bottomRight }

let screen = CGRect(x: 150, y: 200, width: 780, height: 470)
let pad = CGRect(x: 330, y: 738, width: 420, height: 262)
let doc = CGRect(x: 205, y: 250, width: 440, height: 350)
let browser = CGRect(x: 290, y: 250, width: 580, height: 385)
let selection = CGRect(x: 226, y: 408, width: 390, height: 176)
let zoneFraction = 0.15

func zone(_ corner: Corner, of r: CGRect) -> CGRect {
    let w = r.width * zoneFraction, h = r.height * zoneFraction
    switch corner {
    case .topLeft: return CGRect(x: r.minX, y: r.minY, width: w, height: h)
    case .topRight: return CGRect(x: r.maxX - w, y: r.minY, width: w, height: h)
    case .bottomLeft: return CGRect(x: r.minX, y: r.maxY - h, width: w, height: h)
    case .bottomRight: return CGRect(x: r.maxX - w, y: r.maxY - h, width: w, height: h)
    }
}

/// Trackpad point -> screen point (absolute positioning, like the real trackpad mapping in the demo).
func toScreen(_ p: CGPoint) -> CGPoint {
    CGPoint(x: screen.minX + (p.x - pad.minX) / pad.width * screen.width,
            y: screen.minY + (p.y - pad.minY) / pad.height * screen.height)
}
func toPad(_ p: CGPoint) -> CGPoint {
    CGPoint(x: pad.minX + (p.x - screen.minX) / screen.width * pad.width,
            y: pad.minY + (p.y - screen.minY) / screen.height * pad.height)
}

// MARK: - Pieces

func drawTrackpad(_ r: CGRect, radius: Double, glow: (Corner) -> Double) {
    fill(r, radius: radius, rgb(0x1B1F27))
    c.saveGState()
    c.addPath(roundPath(r, radius))
    c.clip()
    for corner in Corner.allCases {
        fill(zone(corner, of: r), accent, alpha: 0.18 + 0.82 * glow(corner))
    }
    c.restoreGState()
    stroke(r, radius: radius, rgb(0x3A404C), width: 2)
}

func trafficLights(_ origin: CGPoint) {
    for (i, color) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
        circle(CGPoint(x: origin.x + Double(i) * 18, y: origin.y), 6, fill: rgb(UInt32(color)))
    }
}

func drawDocument() {
    withShadow(blur: 24, y: 10, alpha: 0.35) { fill(doc, radius: 10, rgb(0xF7F7F9)) }
    c.saveGState()
    c.addPath(roundPath(doc, 10))
    c.clip()
    fill(CGRect(x: doc.minX, y: doc.minY, width: doc.width, height: 30), rgb(0xE6E8EC))
    c.restoreGState()
    trafficLights(CGPoint(x: doc.minX + 18, y: doc.minY + 15))
    text("Q3 Report", at: CGPoint(x: doc.midX, y: doc.minY + 15), size: 13, color: rgb(0x4B5563))

    fill(CGRect(x: doc.minX + 28, y: doc.minY + 52, width: 200, height: 16), radius: 4, rgb(0x1F2937))
    for (i, w) in [360.0, 330, 250].enumerated() {
        fill(CGRect(x: doc.minX + 28, y: doc.minY + 84 + Double(i) * 20, width: w, height: 9), radius: 4.5, rgb(0xC9CDD4))
    }
    let baseline = doc.minY + 318
    for (i, h) in [60.0, 88, 72, 110, 96, 128, 118, 150].enumerated() {
        let bar = CGRect(x: doc.minX + 40 + Double(i) * 46, y: baseline - h, width: 28, height: h)
        fill(bar, radius: 4, i.isMultiple(of: 2) ? accent : rgb(0x60A5FA))
    }
    fill(CGRect(x: doc.minX + 28, y: baseline, width: doc.width - 56, height: 2), rgb(0xD1D5DB))
}

func drawBrowser() {
    let r = browser
    withShadow(blur: 30, y: 12, alpha: 0.45) { fill(r, radius: 12, white) }
    c.saveGState()
    c.addPath(roundPath(r, 12))
    c.clip()
    fill(CGRect(x: r.minX, y: r.minY, width: r.width, height: 74), rgb(0xE9EAEE))
    c.restoreGState()
    trafficLights(CGPoint(x: r.minX + 20, y: r.minY + 20))
    let tab = CGRect(x: r.minX + 88, y: r.minY + 8, width: 190, height: 26)
    fill(tab, radius: 7, white)
    text("SML Corners", at: CGPoint(x: tab.minX + 14, y: tab.midY), size: 12, color: rgb(0x374151), align: .left)
    let address = CGRect(x: r.minX + 18, y: r.minY + 42, width: r.width - 36, height: 24)
    fill(address, radius: 7, white)
    text("github.com/shamwela/sml-corners", at: CGPoint(x: address.minX + 14, y: address.midY),
         size: 12, weight: .regular, color: rgb(0x6B7280), align: .left)

    text("SML Corners", at: CGPoint(x: r.minX + 40, y: r.minY + 122), size: 30, weight: .bold,
         color: rgb(0x111827), align: .left)
    text("Press a corner of your trackpad to start an action.", at: CGPoint(x: r.minX + 40, y: r.minY + 162),
         size: 16, weight: .regular, color: rgb(0x4B5563), align: .left)
    for (i, w) in [470.0, 430, 380, 300].enumerated() {
        fill(CGRect(x: r.minX + 40, y: r.minY + 200 + Double(i) * 22, width: w, height: 10), radius: 5, rgb(0xE5E7EB))
    }
    let button = CGRect(x: r.minX + 40, y: r.maxY - 70, width: 150, height: 40)
    fill(button, radius: 9, accent)
    text("Download", at: CGPoint(x: button.midX, y: button.midY), size: 16, color: white)
}

func drawFinger(_ p: CGPoint, pressed: Double) {
    let r = 30 - 5 * pressed
    withShadow(blur: 18, y: 8, alpha: 0.55) { circle(p, r, fill: rgb(0xE8EAEE)) }
    circle(p, r - 7, fill: rgb(0xD5D9DF))
    circle(p, r + 3, stroke: accent, width: 4, alpha: pressed)
}

func ripple(_ p: CGPoint, start: Double, _ t: Double) {
    let q = prog(t, start, start + 0.6)
    guard q > 0, q < 1 else { return }
    circle(p, 30 + 55 * easeOut(q), stroke: accent, width: 4, alpha: 0.8 * (1 - q))
}

func crosshair(_ p: CGPoint) {
    for (dx, dy) in [(1.0, 0.0), (-1, 0), (0, 1), (0, -1)] {
        let a = CGPoint(x: p.x + dx * 4, y: p.y + dy * 4), b = CGPoint(x: p.x + dx * 15, y: p.y + dy * 15)
        for (color, width) in [(NSColor.black.withAlphaComponent(0.6), 4.0), (white, 2.0)] {
            c.setStrokeColor(color.cgColor)
            c.setLineWidth(width)
            c.move(to: a)
            c.addLine(to: b)
            c.strokePath()
        }
    }
}

func caption(_ s: String, _ alpha: Double) {
    text(s, at: CGPoint(x: W / 2, y: 112), size: 50, weight: .bold, alpha: alpha)
}

// MARK: - Scenes

func sceneProblem(_ t: Double) {
    text("Screenshot to clipboard on a Mac:", at: CGPoint(x: W / 2, y: 330), size: 50, weight: .bold,
         alpha: prog(t, 0, 0.35))
    let keys = [("⌃", "control"), ("⇧", "shift"), ("⌘", "command"), ("4", "")]
    let size = 140.0, gap = 60.0
    let startX = (W - (4 * size + 3 * gap)) / 2
    for (i, key) in keys.enumerated() {
        let appear = prog(t, 0.45 + Double(i) * 0.22, 0.75 + Double(i) * 0.22)
        let rect = CGRect(x: startX + Double(i) * (size + gap), y: 470, width: size, height: size)
        withAlpha(appear) {
            scaled(0.6 + 0.4 * easeOutBack(appear), around: CGPoint(x: rect.midX, y: rect.midY)) {
                fill(rect.offsetBy(dx: 0, dy: 7), radius: 22, rgb(0x050608))
                fill(rect, radius: 22, rgb(0x1F232B))
                stroke(rect, radius: 22, rgb(0x3A404C), width: 2)
                text(key.0, at: CGPoint(x: rect.midX, y: rect.midY - (key.1.isEmpty ? 0 : 12)), size: 62,
                     weight: .medium)
                if !key.1.isEmpty {
                    text(key.1, at: CGPoint(x: rect.midX, y: rect.maxY - 26), size: 18, weight: .medium, color: muted)
                }
            }
        }
        if i < 3 {
            text("+", at: CGPoint(x: rect.maxX + gap / 2, y: rect.midY), size: 44, weight: .light, color: muted,
                 alpha: prog(t, 0.6 + Double(i) * 0.22, 0.9 + Double(i) * 0.22))
        }
    }
    text("Four keys. Every time.", at: CGPoint(x: W / 2, y: 740), size: 46, weight: .semibold, color: muted,
         alpha: prog(t, 1.55, 1.9))
}

func sceneOnePress(_ t: Double) {
    let a = prog(t, 2.75, 3.05)
    scaled(0.94 + 0.06 * easeOut(a), around: CGPoint(x: W / 2, y: 520)) {
        text([("Now it's ", white), ("one press.", accent)], at: CGPoint(x: W / 2, y: 520), size: 84,
             weight: .bold, alpha: a)
    }
    text("SML Corners for macOS", at: CGPoint(x: W / 2, y: 615), size: 34, weight: .medium, color: muted,
         alpha: prog(t, 3.1, 3.4))
}

// Finger keyframes on the trackpad.
let fingerHome = CGPoint(x: pad.midX, y: pad.midY)
let fingerTopRight = CGPoint(x: pad.maxX - 27, y: pad.minY + 21)
let fingerTopLeft = CGPoint(x: pad.minX + 27, y: pad.minY + 21)
let dragStart = toPad(CGPoint(x: selection.minX, y: selection.minY))
let dragEnd = toPad(CGPoint(x: selection.maxX, y: selection.maxY))

func finger(_ t: Double) -> (CGPoint, Double) {
    switch t {
    case ..<4.4: return (fingerHome, 0)
    case ..<5.0: return (lerp(fingerHome, fingerTopRight, ease(prog(t, 4.4, 5.0))), 0)
    case ..<5.35: return (fingerTopRight, prog(t, 5.0, 5.06))
    case ..<6.0: return (lerp(fingerTopRight, dragStart, ease(prog(t, 5.5, 5.95))), 0)
    case ..<7.3: return (lerp(dragStart, dragEnd, ease(prog(t, 6.05, 7.25))), prog(t, 6.0, 6.06))
    case ..<9.5: return (lerp(dragEnd, fingerHome, ease(prog(t, 8.0, 8.8))), 0)
    case ..<10.1: return (lerp(fingerHome, fingerTopLeft, ease(prog(t, 9.5, 10.1))), 0)
    case ..<10.45: return (fingerTopLeft, prog(t, 10.1, 10.16))
    default: return (lerp(fingerTopLeft, fingerHome, ease(prog(t, 10.8, 11.4))), 0)
    }
}

func pressGlow(_ t: Double, _ down: Double, _ up: Double) -> Double {
    t < down ? 0 : t < up ? prog(t, down, down + 0.08) : 1 - prog(t, up, up + 0.7)
}

func sceneDemo(_ t: Double) {
    // Laptop screen.
    let bezel = screen.insetBy(dx: -16, dy: -16)
    fill(bezel, radius: 28, rgb(0x15181E))
    stroke(bezel, radius: 28, rgb(0x2C313B), width: 2)

    c.saveGState()
    c.addPath(roundPath(screen, 10))
    c.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: [rgb(0x1E3A8A).cgColor, rgb(0x6D28D9).cgColor] as CFArray,
                              locations: [0, 1])!
    c.drawLinearGradient(gradient, start: CGPoint(x: screen.minX, y: screen.minY),
                         end: CGPoint(x: screen.maxX, y: screen.maxY), options: [])
    fill(CGRect(x: screen.minX, y: screen.minY, width: screen.width, height: 24), NSColor.black, alpha: 0.28)
    text("9:41", at: CGPoint(x: screen.maxX - 16, y: screen.minY + 12), size: 13, weight: .medium, align: .right)
    symbol("viewfinder", in: CGRect(x: screen.maxX - 68, y: screen.minY + 5, width: 14, height: 14), color: white)

    drawDocument()

    // Screenshot mode: dimmed screen with crosshair, then a selection.
    let (fingerPoint, pressed) = finger(t)
    if t >= 5.4 && t < 7.3 {
        let a = prog(t, 5.4, 5.55)
        let cursor = toScreen(fingerPoint)
        var hole = CGRect.null
        if t >= 6.0 {
            hole = CGRect(x: selection.minX, y: selection.minY, width: cursor.x - selection.minX,
                          height: cursor.y - selection.minY).standardized
        }
        c.saveGState()
        c.setAlpha(a)
        c.addRect(screen)
        if !hole.isNull { c.addRect(hole) }
        c.setFillColor(NSColor.black.withAlphaComponent(0.4).cgColor)
        c.fillPath(using: .evenOdd)
        c.restoreGState()
        if !hole.isNull {
            stroke(hole, white, width: 1.5)
            let label = "\(Int(hole.width * 2)) × \(Int(hole.height * 2))"
            let pill = CGRect(x: cursor.x + 14, y: cursor.y + 14, width: 96, height: 24)
            fill(pill, radius: 6, NSColor.black, alpha: 0.7)
            text(label, at: CGPoint(x: pill.midX, y: pill.midY), size: 12, weight: .medium, mono: true)
        }
        withAlpha(a) { crosshair(cursor) }
    }
    // Capture flash, thumbnail and toast.
    let flash = 1 - prog(t, 7.3, 7.6)
    if t >= 7.3 && flash > 0 { fill(screen, white, alpha: 0.75 * flash) }
    let thumbIn = easeOut(prog(t, 7.5, 7.9))
    let thumbAlpha = min(thumbIn, 1 - prog(t, 9.0, 9.4))
    if thumbAlpha > 0 {
        let w = 180.0, h = w * selection.height / selection.width
        let thumb = CGRect(x: screen.maxX - w - 20 + 230 * (1 - thumbIn), y: screen.maxY - h - 20, width: w, height: h)
        withAlpha(thumbAlpha) {
            withShadow(blur: 16, y: 6, alpha: 0.5) { fill(thumb.insetBy(dx: -4, dy: -4), radius: 6, white) }
            c.saveGState()
            c.clip(to: thumb)
            c.translateBy(x: thumb.minX, y: thumb.minY)
            c.scaleBy(x: w / selection.width, y: w / selection.width)
            c.translateBy(x: -selection.minX, y: -selection.minY)
            drawDocument()
            c.restoreGState()
        }
    }
    let toast = visible(t, 7.7, 9.3, fade: 0.25)
    if toast > 0 {
        let pill = CGRect(x: screen.maxX - 278, y: screen.minY + 44 - 8 * (1 - toast), width: 258, height: 46)
        withAlpha(toast) {
            fill(pill, radius: 23, NSColor.black, alpha: 0.72)
            symbol("checkmark.circle.fill", in: CGRect(x: pill.minX + 22, y: pill.midY - 10, width: 20, height: 20),
                   color: rgb(0x34D399))
            text("Copied to clipboard", at: CGPoint(x: pill.minX + 54, y: pill.midY), size: 18, weight: .semibold,
                 align: .left)
        }
    }
    // App opens.
    let open = prog(t, 10.5, 10.95)
    if open > 0 {
        withAlpha(open) {
            scaled(0.88 + 0.12 * easeOutBack(open), around: CGPoint(x: browser.midX, y: browser.midY)) { drawBrowser() }
        }
    }
    c.restoreGState()

    // Trackpad and finger.
    drawTrackpad(pad, radius: 22) { corner in
        switch corner {
        case .topRight: return pressGlow(t, 5.0, 5.35)
        case .topLeft: return pressGlow(t, 10.1, 10.45)
        default: return 0
        }
    }
    ripple(fingerTopRight, start: 5.0, t)
    ripple(fingerTopLeft, start: 10.1, t)
    drawFinger(fingerPoint, pressed: pressed)

    // Captions.
    caption("Press the top-right corner", visible(t, 4.0, 5.95, fade: 0.25))
    caption("Drag to pick an area", visible(t, 5.95, 7.55, fade: 0.25))
    caption("Copied. Ready to paste.", visible(t, 7.55, 9.45, fade: 0.25))
    caption("Top left? Open any app.", visible(t, 9.45, 12.1, fade: 0.25))
}

func sceneEnd(_ t: Double) {
    text("SML Corners", at: CGPoint(x: W / 2, y: 175), size: 88, weight: .bold, alpha: prog(t, 12.1, 12.45))
    text("Give every trackpad corner a job", at: CGPoint(x: W / 2, y: 262), size: 36, weight: .medium,
         color: muted, alpha: prog(t, 12.25, 12.6))

    let big = CGRect(x: 290, y: 420, width: 500, height: 310)
    let order: [Corner] = [.topRight, .topLeft, .bottomLeft, .bottomRight]
    drawTrackpad(big, radius: 26) { corner in
        let i = Double(order.firstIndex(of: corner)!)
        return prog(t, 12.4 + i * 0.18, 12.6 + i * 0.18)
    }
    let labels: [(Corner, String, CGPoint, Align)] = [
        (.topLeft, "Open an app", CGPoint(x: big.minX, y: big.minY - 32), .left),
        (.topRight, "Screenshot", CGPoint(x: big.maxX, y: big.minY - 32), .right),
        (.bottomLeft, "Open a website", CGPoint(x: big.minX, y: big.maxY + 34), .left),
        (.bottomRight, "Keyboard shortcut", CGPoint(x: big.maxX, y: big.maxY + 34), .right),
    ]
    for (corner, label, point, align) in labels {
        let i = Double(order.firstIndex(of: corner)!)
        text(label, at: point, size: 28, weight: .semibold, align: align, alpha: prog(t, 12.45 + i * 0.18, 12.75 + i * 0.18))
    }
    text("Free and open source", at: CGPoint(x: W / 2, y: 900), size: 30, weight: .medium, color: muted,
         alpha: prog(t, 13.3, 13.6))
    text("github.com/shamwela/sml-corners", at: CGPoint(x: W / 2, y: 950), size: 32, weight: .semibold,
         color: accent, alpha: prog(t, 13.4, 13.7))
}

func render(_ t: Double, into context: CGContext) {
    c = context
    c.translateBy(x: 0, y: H)
    c.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: true)
    c.setFillColor(background.cgColor)
    c.fill(CGRect(x: 0, y: 0, width: W, height: H))
    let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                          colors: [accent.withAlphaComponent(0.16).cgColor, accent.withAlphaComponent(0).cgColor] as CFArray,
                          locations: [0, 1])!
    c.drawRadialGradient(glow, startCenter: CGPoint(x: W / 2, y: 0), startRadius: 0,
                         endCenter: CGPoint(x: W / 2, y: 0), endRadius: 700, options: [])

    withAlpha(1 - prog(t, 2.4, 2.7)) { sceneProblem(t) }
    withAlpha(visible(t, 2.7, 4.05)) { sceneOnePress(t) }
    withAlpha(visible(t, 4.0, 12.1)) { sceneDemo(t) }
    withAlpha(prog(t, 12.0, 12.3)) { sceneEnd(t) }
    NSGraphicsContext.current = nil
}

// MARK: - Output

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

func writePNGs(dir: String, times: [Double]) throws {
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    for t in times {
        let ctx = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: bitmapInfo)!
        render(t, into: ctx)
        let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
        try rep.representation(using: .png, properties: [:])!
            .write(to: URL(fileURLWithPath: "\(dir)/frame-\(String(format: "%05.2f", t)).png"))
    }
}

func writeVideo(to path: String) throws {
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.removeItem(at: url)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: Int(W),
        AVVideoHeightKey: Int(H),
        AVVideoCompressionPropertiesKey: [
            AVVideoAverageBitRateKey: 8_000_000,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        ],
        AVVideoColorPropertiesKey: [
            AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
            AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
            AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
        ],
    ])
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: Int(W),
        kCVPixelBufferHeightKey as String: Int(H),
    ])
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)

    let frames = Int(DURATION * FPS)
    for i in 0..<frames {
        while !input.isReadyForMoreMediaData { usleep(2000) }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
        guard let buffer else { fatalError("no pixel buffer") }
        CVPixelBufferLockBaseAddress(buffer, [])
        let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: Int(W), height: Int(H),
                            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                            space: space, bitmapInfo: bitmapInfo)!
        render(storyTime(Double(i) / FPS), into: ctx)
        CVPixelBufferUnlockBaseAddress(buffer, [])
        adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: CMTimeScale(FPS)))
    }
    input.markAsFinished()
    let done = DispatchSemaphore(value: 0)
    writer.finishWriting { done.signal() }
    done.wait()
    if writer.status != .completed { throw writer.error ?? NSError(domain: "demo-video", code: 1) }
}

// MARK: - Audio (synthesized: free to use, nothing downloaded)

let SR = 44100.0

func midi(_ note: Double) -> Double { 440 * pow(2, (note - 69) / 12) }

/// Deterministic noise so every render sounds the same.
var noiseState: UInt64 = 0x9E3779B97F4A7C15
func noise() -> Double {
    noiseState ^= noiseState << 13
    noiseState ^= noiseState >> 7
    noiseState ^= noiseState << 17
    return Double(noiseState % 20001) / 10000 - 1
}

final class Mix {
    var left: [Float], right: [Float]
    init(seconds: Double) {
        left = Array(repeating: 0, count: Int(seconds * SR))
        right = left
    }

    /// Adds `sample(localTime)` starting at `start`. `pan` is -1 (left) to 1 (right).
    func add(at start: Double, length: Double, gain: Double, pan: Double = 0, _ sample: (Double) -> Double) {
        let angle = (pan + 1) * .pi / 4
        let gl = cos(angle) * gain * sqrt(2), gr = sin(angle) * gain * sqrt(2)
        let first = Int(start * SR)
        for i in 0..<Int(length * SR) {
            let index = first + i
            guard index >= 0, index < left.count else { continue }
            let v = sample(Double(i) / SR)
            left[index] += Float(v * gl)
            right[index] += Float(v * gr)
        }
    }
}

func sine(_ f: Double, _ t: Double) -> Double { sin(2 * .pi * f * t) }

func music(_ mix: Mix, length: Double) {
    let bar = 2.5  // 96 bpm, 4/4
    let chords: [[Double]] = [
        [60, 64, 67, 71],  // Cmaj7
        [57, 60, 64, 67],  // Am7
        [53, 57, 60, 64],  // Fmaj7
        [55, 59, 62, 64],  // G6
    ]
    var start = 0.0, index = 0
    while start < length {
        let chord = chords[index % chords.count]
        // Warm pad, slightly detuned left and right.
        for note in chord {
            for (detune, pan) in [(0.998, -0.6), (1.002, 0.6)] {
                let f = midi(note) * detune
                let d = bar + 0.8
                mix.add(at: start, length: d, gain: 0.035, pan: pan) { t in
                    let env = min(t / 0.5, 1) * max(min((d - t) / 0.8, 1), 0)
                    return env * (sine(f, t) + 0.35 * sine(2 * f, t) + 0.12 * sine(3 * f, t))
                }
            }
        }
        // Soft bass on the root.
        let bass = midi(chord[0] - 24)
        mix.add(at: start, length: bar, gain: 0.11) { t in min(t / 0.02, 1) * exp(-1.2 * t) * sine(bass, t) }
        // Gentle plucked arpeggio in eighth notes.
        let pattern = [0, 1, 2, 3, 2, 1, 2, 3]
        for (step, i) in pattern.enumerated() {
            let f = midi(chord[i] + 12)
            mix.add(at: start + Double(step) * bar / 8, length: 0.9, gain: 0.04, pan: step.isMultiple(of: 2) ? -0.3 : 0.3) { t in
                min(t / 0.004, 1) * exp(-5 * t) * (sine(f, t) + 0.3 * exp(-8 * t) * sine(2 * f, t))
            }
        }
        start += bar
        index += 1
    }
}

func tick(_ mix: Mix, at t0: Double) {
    mix.add(at: t0, length: 0.08, gain: 0.22) { t in
        exp(-90 * t) * sine(1700, t) + 0.4 * exp(-220 * t) * noise()
    }
}

func trackpadClick(_ mix: Mix, at t0: Double, gain: Double = 0.5) {
    mix.add(at: t0, length: 0.15, gain: gain) { t in
        exp(-35 * t) * sine(150, t) + 0.5 * exp(-140 * t) * noise()
    }
}

func shutter(_ mix: Mix, at t0: Double) {
    for offset in [0.0, 0.075] {
        var low = 0.0
        mix.add(at: t0 + offset, length: 0.12, gain: 0.4) { t in
            low += 0.35 * (noise() - low)
            return exp(-45 * t) * low * 2
        }
    }
}

func whoosh(_ mix: Mix, at t0: Double) {
    var low = 0.0
    let d = 0.5
    mix.add(at: t0, length: d, gain: 0.3) { t in
        let cutoff = 0.04 + 0.25 * sin(.pi * t / d)
        low += cutoff * (noise() - low)
        return pow(sin(.pi * t / d), 2) * low * 2.5
    }
}

func chime(_ mix: Mix, at t0: Double, note: Double, gain: Double = 0.12) {
    let f = midi(note)
    mix.add(at: t0, length: 1.6, gain: gain) { t in
        min(t / 0.003, 1) * exp(-3 * t) * (sine(f, t) + 0.25 * exp(-6 * t) * sine(3 * f, t))
    }
}

func soundtrack(length: Double) -> Mix {
    let mix = Mix(seconds: length)
    music(mix, length: length)

    for i in 0..<4 { tick(mix, at: realTime(0.45 + Double(i) * 0.22)) }      // keycaps pop in
    for (i, note) in [79.0, 84].enumerated() { chime(mix, at: realTime(2.8) + Double(i) * 0.09, note: note) }
    trackpadClick(mix, at: realTime(5.0))                                    // top-right press
    trackpadClick(mix, at: realTime(5.35), gain: 0.25)                       // release
    trackpadClick(mix, at: realTime(6.0), gain: 0.3)                         // drag start
    shutter(mix, at: realTime(7.3))                                          // capture
    chime(mix, at: realTime(7.75), note: 88, gain: 0.09)                     // copied toast
    trackpadClick(mix, at: realTime(10.1))                                   // top-left press
    whoosh(mix, at: realTime(10.45))                                         // app opens
    for (i, note) in [72.0, 76, 79, 84].enumerated() {                       // end card corners
        chime(mix, at: realTime(12.4 + Double(i) * 0.18), note: note, gain: 0.1)
    }

    // Fade in and out, then normalise.
    let count = mix.left.count
    for i in 0..<count {
        let t = Double(i) / SR
        let fade = Float(min(t / 0.8, 1) * min((length - t) / 2.5, 1))
        mix.left[i] *= fade
        mix.right[i] *= fade
    }
    let peak = max(mix.left.map(abs).max() ?? 1, mix.right.map(abs).max() ?? 1)
    let scale = 0.65 / max(peak, 0.0001)  // headroom for AAC overshoot
    for i in 0..<count { mix.left[i] *= scale; mix.right[i] *= scale }
    return mix
}

func writeAudio(to url: URL, length: Double) throws {
    let mix = soundtrack(length: length)
    try? FileManager.default.removeItem(at: url)
    let file = try AVAudioFile(forWriting: url, settings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: SR,
        AVNumberOfChannelsKey: 2,
        AVEncoderBitRateKey: 192_000,
    ], commonFormat: .pcmFormatFloat32, interleaved: false)
    let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(mix.left.count))!
    buffer.frameLength = buffer.frameCapacity
    mix.left.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: $0.count) }
    mix.right.withUnsafeBufferPointer { buffer.floatChannelData![1].update(from: $0.baseAddress!, count: $0.count) }
    try file.write(from: buffer)
}

/// Combines the silent video and the soundtrack into one MP4 without re-encoding.
func mux(video: URL, audio: URL, to output: URL) throws {
    let videoAsset = AVURLAsset(url: video), audioAsset = AVURLAsset(url: audio)
    let composition = AVMutableComposition()
    let duration = videoAsset.duration
    let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
    try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration),
                                   of: videoAsset.tracks(withMediaType: .video)[0], at: .zero)
    let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
    try audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: CMTimeMinimum(duration, audioAsset.duration)),
                                   of: audioAsset.tracks(withMediaType: .audio)[0], at: .zero)

    try? FileManager.default.removeItem(at: output)
    let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough)!
    export.outputURL = output
    export.outputFileType = .mp4
    let done = DispatchSemaphore(value: 0)
    export.exportAsynchronously { done.signal() }
    done.wait()
    if export.status != .completed { throw export.error ?? NSError(domain: "demo-video", code: 2) }
}

let args = CommandLine.arguments
if args.count >= 4, args[1] == "--frames" {
    try writePNGs(dir: args[2], times: args[3].split(separator: ",").compactMap { Double($0) })
} else if args.count >= 2 {
    let output = URL(fileURLWithPath: args[1])
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent("sml-corners-demo-\(getpid())")
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temp) }
    let silent = temp.appendingPathComponent("video.mp4"), audio = temp.appendingPathComponent("audio.m4a")
    try writeVideo(to: silent.path)
    try writeAudio(to: audio, length: DURATION)
    try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
    try mux(video: silent, audio: audio, to: output)
    print(String(format: "Wrote %@ (%.1f s)", args[1], DURATION))
} else {
    print("usage: demo-video OUTPUT.mp4 | demo-video --frames DIR 1.5,5.2")
    exit(1)
}
