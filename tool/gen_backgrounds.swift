// Generates the reading background tiles in assets/backgrounds/.
//
//   swift tool/gen_backgrounds.swift
//
// Each design has a light and a dark variant. Tiles are 1024 px, seamless
// (motifs near an edge are also drawn on the opposite side) and shown at
// scale 2 (512 logical px). Motifs stay faint so long text remains easy to
// read. A fixed seed keeps the output identical between runs.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1
  ? CommandLine.arguments[1] : "assets/backgrounds")

// MARK: - Helpers

struct RNG {
  var state: UInt64
  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
  mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
  mutating func range(_ a: Double, _ b: Double) -> Double { a + (b - a) * unit() }
}

func rgb(_ hex: UInt32, _ alpha: Double = 1) -> CGColor {
  CGColor(
    red: CGFloat((hex >> 16) & 0xFF) / 255,
    green: CGFloat((hex >> 8) & 0xFF) / 255,
    blue: CGFloat(hex & 0xFF) / 255,
    alpha: CGFloat(alpha))
}

/// Draw `body` at (x, y) and at wrapped copies so the tile repeats seamlessly.
func wrapped(_ ctx: CGContext, x: Double, y: Double, margin: Double,
             _ body: (CGContext) -> Void) {
  let s = Double(size)
  for dx in [-s, 0, s] {
    for dy in [-s, 0, s] {
      let px = x + dx, py = y + dy
      if px < -margin || px > s + margin || py < -margin || py > s + margin { continue }
      ctx.saveGState()
      ctx.translateBy(x: px, y: py)
      body(ctx)
      ctx.restoreGState()
    }
  }
}

/// Evenly spread but irregular positions: one jittered point per grid cell.
func scatter(_ rng: inout RNG, cells: Int) -> [(Double, Double)] {
  let step = Double(size) / Double(cells)
  var pts: [(Double, Double)] = []
  for i in 0..<cells {
    for j in 0..<cells {
      pts.append((
        (Double(i) + rng.range(0.15, 0.85)) * step,
        (Double(j) + rng.range(0.15, 0.85)) * step))
    }
  }
  return pts
}

/// Fine paper grain: tiny light and dark specks.
func grain(_ ctx: CGContext, _ rng: inout RNG, dark: Bool, amount: Int = 5000) {
  for _ in 0..<amount {
    let x = rng.range(0, Double(size)), y = rng.range(0, Double(size))
    let r = rng.range(0.5, 1.3)
    let lighter = rng.unit() < 0.5
    let a = rng.range(0.015, dark ? 0.04 : 0.035)
    ctx.setFillColor(lighter ? rgb(0xFFFFFF, a) : rgb(0x000000, a))
    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
  }
}

// MARK: - Motifs (drawn around the origin)

func blossom(_ ctx: CGContext, r: Double, color: CGColor, center: CGColor) {
  ctx.setFillColor(color)
  for k in 0..<5 {
    let a = Double(k) * 2 * .pi / 5
    let cx = cos(a) * r * 0.55, cy = sin(a) * r * 0.55
    ctx.fillEllipse(in: CGRect(x: cx - r * 0.5, y: cy - r * 0.5, width: r, height: r))
  }
  ctx.setFillColor(center)
  ctx.fillEllipse(in: CGRect(x: -r * 0.18, y: -r * 0.18, width: r * 0.36, height: r * 0.36))
}

func leaf(_ ctx: CGContext, length: Double, width: Double, color: CGColor) {
  let p = CGMutablePath()
  p.move(to: .zero)
  p.addQuadCurve(to: CGPoint(x: length, y: 0), control: CGPoint(x: length * 0.45, y: width))
  p.addQuadCurve(to: .zero, control: CGPoint(x: length * 0.45, y: -width * 0.55))
  ctx.setFillColor(color)
  ctx.addPath(p)
  ctx.fillPath()
}

func petal(_ ctx: CGContext, r: Double, color: CGColor) {
  // Sakura petal: rounded teardrop with a small notch at the tip.
  let p = CGMutablePath()
  p.move(to: CGPoint(x: 0, y: -r))
  p.addCurve(to: CGPoint(x: r * 0.15, y: r * 0.95),
             control1: CGPoint(x: r * 0.95, y: -r * 0.6),
             control2: CGPoint(x: r * 0.85, y: r * 0.75))
  p.addLine(to: CGPoint(x: 0, y: r * 0.7))
  p.addLine(to: CGPoint(x: -r * 0.15, y: r * 0.95))
  p.addCurve(to: CGPoint(x: 0, y: -r),
             control1: CGPoint(x: -r * 0.85, y: r * 0.75),
             control2: CGPoint(x: -r * 0.95, y: -r * 0.6))
  ctx.setFillColor(color)
  ctx.addPath(p)
  ctx.fillPath()
}

func sparkle(_ ctx: CGContext, r: Double, color: CGColor) {
  let p = CGMutablePath()
  let w = r * 0.22
  p.move(to: CGPoint(x: 0, y: -r))
  p.addQuadCurve(to: CGPoint(x: r, y: 0), control: CGPoint(x: w, y: -w))
  p.addQuadCurve(to: CGPoint(x: 0, y: r), control: CGPoint(x: w, y: w))
  p.addQuadCurve(to: CGPoint(x: -r, y: 0), control: CGPoint(x: -w, y: w))
  p.addQuadCurve(to: CGPoint(x: 0, y: -r), control: CGPoint(x: -w, y: -w))
  ctx.setFillColor(color)
  ctx.addPath(p)
  ctx.fillPath()
}

func crescent(_ ctx: CGContext, r: Double, color: CGColor) {
  let p = CGMutablePath()
  p.addEllipse(in: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r))
  p.addEllipse(in: CGRect(x: -r * 0.55, y: -r * 1.15, width: 2 * r, height: 2 * r))
  ctx.setFillColor(color)
  ctx.addPath(p)
  ctx.fillPath(using: .evenOdd)
}

// MARK: - Designs

struct Palette {
  let base: UInt32
  let ink: UInt32
  let inkAlpha: Double
  let accent: UInt32
}

func xuan(_ ctx: CGContext, _ p: Palette, dark: Bool) {
  var rng = RNG(state: 11)
  grain(ctx, &rng, dark: dark, amount: 7000)
  // Long thin paper fibres.
  ctx.setLineCap(.round)
  for _ in 0..<260 {
    let x = rng.range(0, 1024), y = rng.range(0, 1024)
    let len = rng.range(18, 60), a = rng.range(0, .pi)
    let bend = rng.range(-8, 8)
    wrapped(ctx, x: x, y: y, margin: 70) { c in
      c.rotate(by: a)
      c.setStrokeColor(rgb(p.ink, rng.range(0.03, 0.06) * (dark ? 1.2 : 1)))
      c.setLineWidth(rng.range(0.8, 1.6))
      c.move(to: .zero)
      c.addQuadCurve(to: CGPoint(x: len, y: 0), control: CGPoint(x: len / 2, y: bend))
      c.strokePath()
    }
  }
  for (x, y) in scatter(&rng, cells: 4) {
    let r = rng.range(13, 19), rot = rng.range(0, 2 * .pi)
    wrapped(ctx, x: x, y: y, margin: 30) { c in
      c.rotate(by: rot)
      blossom(c, r: r, color: rgb(p.accent, p.inkAlpha), center: rgb(p.accent, p.inkAlpha * 1.6))
    }
    // A couple of fallen petals near each blossom.
    for _ in 0..<2 {
      let ox = rng.range(-60, 60), oy = rng.range(-60, 60), rr = rng.range(4, 6)
      wrapped(ctx, x: x + ox, y: y + oy, margin: 10) { c in
        c.setFillColor(rgb(p.accent, p.inkAlpha * 0.8))
        c.fillEllipse(in: CGRect(x: -rr, y: -rr, width: 2 * rr, height: 2 * rr))
      }
    }
  }
}

func bamboo(_ ctx: CGContext, _ p: Palette, dark: Bool) {
  var rng = RNG(state: 23)
  grain(ctx, &rng, dark: dark, amount: 4000)
  for (x, y) in scatter(&rng, cells: 4) {
    let rot = rng.range(-0.9, 0.9) - .pi / 2
    let len = rng.range(48, 66)
    wrapped(ctx, x: x, y: y, margin: 90) { c in
      c.rotate(by: rot)
      // Thin twig with three leaves fanning from its tip.
      c.setStrokeColor(rgb(p.accent, p.inkAlpha * 0.9))
      c.setLineWidth(1.6)
      c.move(to: CGPoint(x: -18, y: 0))
      c.addLine(to: .zero)
      c.strokePath()
      for (k, spread) in [-0.5, 0.05, 0.55].enumerated() {
        c.saveGState()
        c.rotate(by: spread)
        leaf(c, length: len * (k == 1 ? 1 : 0.82), width: len * 0.16,
             color: rgb(p.accent, p.inkAlpha * (k == 1 ? 1 : 0.8)))
        c.restoreGState()
      }
    }
  }
}

func wave(_ ctx: CGContext, _ p: Palette, dark: Bool) {
  var rng = RNG(state: 37)
  grain(ctx, &rng, dark: dark, amount: 3000)
  // 青海波: overlapping fans of concentric arcs, back rows first.
  let r = 128.0
  ctx.setLineWidth(2)
  var row = -2
  while Double(row) * r / 2 <= 1024 + r {
    let y = Double(row) * r / 2
    let shift = row % 2 == 0 ? 0 : r
    var x = -2 * r + shift
    while x <= 1024 + 2 * r {
      ctx.setFillColor(rgb(p.base))
      ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
      for f in [0.92, 0.7, 0.48, 0.26] {
        ctx.setStrokeColor(rgb(p.accent, p.inkAlpha))
        ctx.strokeEllipse(in: CGRect(x: x - r * f, y: y - r * f, width: 2 * r * f, height: 2 * r * f))
      }
      x += 2 * r
    }
    row += 1
  }
  // Grain again on top so the fills don't look flat.
  grain(ctx, &rng, dark: dark, amount: 3000)
}

func stars(_ ctx: CGContext, _ p: Palette, dark: Bool) {
  var rng = RNG(state: 41)
  grain(ctx, &rng, dark: dark, amount: 3000)
  for _ in 0..<170 {
    let x = rng.range(0, 1024), y = rng.range(0, 1024), rr = rng.range(1.2, 2.6)
    let a = p.inkAlpha * rng.range(0.4, 1.1)
    wrapped(ctx, x: x, y: y, margin: 4) { c in
      c.setFillColor(rgb(p.accent, a))
      c.fillEllipse(in: CGRect(x: -rr, y: -rr, width: 2 * rr, height: 2 * rr))
    }
  }
  for (x, y) in scatter(&rng, cells: 5) {
    let rr = rng.range(8, 15), rot = rng.range(-0.3, 0.3)
    wrapped(ctx, x: x, y: y, margin: 20) { c in
      c.rotate(by: rot)
      sparkle(c, r: rr, color: rgb(p.accent, p.inkAlpha * 1.2))
    }
  }
  for (x, y) in scatter(&rng, cells: 2) {
    let rr = rng.range(13, 17), rot = rng.range(-0.6, 0.2)
    wrapped(ctx, x: x, y: y, margin: 24) { c in
      c.rotate(by: rot)
      crescent(c, r: rr, color: rgb(p.accent, p.inkAlpha * 1.1))
    }
  }
}

func sakura(_ ctx: CGContext, _ p: Palette, dark: Bool) {
  var rng = RNG(state: 53)
  grain(ctx, &rng, dark: dark, amount: 4000)
  for (x, y) in scatter(&rng, cells: 6) {
    let rr = rng.range(10, 15), rot = rng.range(0, 2 * .pi)
    let a = p.inkAlpha * rng.range(0.7, 1.15)
    wrapped(ctx, x: x, y: y, margin: 16) { c in
      c.rotate(by: rot)
      c.scaleBy(x: 1, y: rng.range(0.75, 1))
      petal(c, r: rr, color: rgb(p.accent, a))
    }
  }
  for (x, y) in scatter(&rng, cells: 2) {
    let rot = rng.range(0, 2 * .pi)
    wrapped(ctx, x: x, y: y, margin: 30) { c in
      c.rotate(by: rot)
      for k in 0..<5 {
        c.saveGState()
        c.rotate(by: Double(k) * 2 * .pi / 5)
        c.translateBy(x: 0, y: -11)
        petal(c, r: 10, color: rgb(p.accent, p.inkAlpha * 1.05))
        c.restoreGState()
      }
    }
  }
}

// MARK: - Output

let designs: [(String, (CGContext, Palette, Bool) -> Void, Palette, Palette)] = [
  ("xuan", xuan,
   Palette(base: 0xF6EEE0, ink: 0x6B5434, inkAlpha: 0.15, accent: 0xC4826F),
   Palette(base: 0x1C1916, ink: 0xD9C9AE, inkAlpha: 0.11, accent: 0xB57A68)),
  ("bamboo", bamboo,
   Palette(base: 0xEAF0DF, ink: 0x4E6340, inkAlpha: 0.14, accent: 0x6F8F5C),
   Palette(base: 0x151A15, ink: 0xB9CDA8, inkAlpha: 0.11, accent: 0x6E8C5E)),
  ("wave", wave,
   Palette(base: 0xE6EFEE, ink: 0x3E6B67, inkAlpha: 0.09, accent: 0x5D8E89),
   Palette(base: 0x121A1B, ink: 0xA6C8C4, inkAlpha: 0.10, accent: 0x4E7B77)),
  ("stars", stars,
   Palette(base: 0xEEECF5, ink: 0x4D4880, inkAlpha: 0.16, accent: 0x7B73AE),
   Palette(base: 0x13131E, ink: 0xD7D4F5, inkAlpha: 0.20, accent: 0xC4C0EE)),
  ("sakura", sakura,
   Palette(base: 0xF7E8E9, ink: 0x7A4552, inkAlpha: 0.20, accent: 0xD68A9B),
   Palette(base: 0x1D1517, ink: 0xE6C3CB, inkAlpha: 0.17, accent: 0xB57585)),
]

try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for (name, draw, light, dark) in designs {
  for (variant, palette, isDark) in [("light", light, false), ("dark", dark, true)] {
    let ctx = CGContext(
      data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.setFillColor(rgb(palette.base))
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    draw(ctx, palette, isDark)
    let url = out.appendingPathComponent("\(name)_\(variant).jpg")
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!,
      [kCGImageDestinationLossyCompressionQuality: 0.86] as CFDictionary)
    CGImageDestinationFinalize(dest)
    print("wrote \(url.lastPathComponent)")
  }
}
