#!/usr/bin/env swift
// Renders the README banner, docs/banner.png, at 2x: the icon, the name, a tagline and
// feature chips on the left, the real window on the right, on a light backdrop taken
// from the icon. The window is docs/screenshot-week-light.png, made by Scripts/screenshots.zsh.
// Usage: swift Scripts/render-banner.swift

import AppKit
import SwiftUI

let name = "Factory Log"
let tagline = "See what your coding agents did,\nand where your time went."
let chips = ["Day timeline", "Week at a glance", "Stays on your Mac"]
let size = CGSize(width: 1280, height: 560)
// Where the window's top-left corner sits, and how much it's scaled down.
let windowOrigin = CGPoint(x: 598, y: 66)
let windowScale: CGFloat = 0.5

// The icon's cream paper into its lavender ground, its teal tray for the glow.
let backgroundTop = Color(hex: 0xFBF7EF)
let backgroundBottom = Color(hex: 0xE9E2F2)
let glow = Color(hex: 0x26A69E)
let ink = Color(hex: 0x13201F)
let muted = ink.opacity(0.64)

let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconSource = root.appending(path: "Resources/AppIcon.png")
let screenshot = root.appending(path: "docs/screenshot-week-light.png")
let output = root.appending(path: "docs/banner.png")
// Scripts/frame-screenshot.swift leaves a 48pt margin around the window for its shadow.
let shadowMargin: CGFloat = 48

extension Color {
  init(hex: UInt32) {
    self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
  }
}

func wave(baseline: CGFloat, amplitude: CGFloat, wavelength: CGFloat, phase: CGFloat) -> Path {
  Path { path in
    for x in stride(from: -10, through: size.width + 10, by: 4) {
      let y = baseline + amplitude * sin(x / wavelength * 2 * .pi + phase)
      if x == -10 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
  }
}

struct Banner: View {
  let icon: NSImage
  let window: NSImage

  var body: some View {
    ZStack(alignment: .topLeading) {
      LinearGradient(colors: [backgroundTop, backgroundBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
      RadialGradient(colors: [glow.opacity(0.16), glow.opacity(0)], center: UnitPoint(x: 0.16, y: 0.36), startRadius: 0, endRadius: 420)
      ForEach(0..<3) { index in
        wave(baseline: size.height - 90 + CGFloat(index) * 30, amplitude: 7, wavelength: 260, phase: CGFloat(index) * 1.7)
          .stroke(ink.opacity(0.07 - Double(index) * 0.017), style: StrokeStyle(lineWidth: 3, lineCap: .round))
      }

      // The screenshot is 2x, so its size in points is half its pixels.
      Image(nsImage: window)
        .resizable()
        .interpolation(.high)
        .frame(width: CGFloat(window.representations[0].pixelsWide) / 2 * windowScale, height: CGFloat(window.representations[0].pixelsHigh) / 2 * windowScale)
        .offset(x: windowOrigin.x - shadowMargin * windowScale, y: windowOrigin.y - shadowMargin * windowScale)

      VStack(alignment: .leading, spacing: 0) {
        Image(nsImage: icon)
          .resizable()
          .interpolation(.high)
          .frame(width: 132, height: 132)
          .shadow(color: Color(hex: 0x342652).opacity(0.22), radius: 16, y: 10)
        Text(name)
          .font(.system(size: 72, weight: .bold))
          .tracking(-1.8)
          .foregroundStyle(ink)
          .padding(.top, 22)
        Text(tagline)
          .font(.system(size: 26, weight: .regular))
          .lineSpacing(4)
          .foregroundStyle(muted)
          .padding(.top, 8)
        HStack(spacing: 10) {
          ForEach(chips, id: \.self) { chip in
            Text(chip)
              .font(.system(size: 16, weight: .semibold))
              .foregroundStyle(Color(hex: 0x13756F))
              .padding(.horizontal, 14)
              .padding(.vertical, 7)
              .background(.white.opacity(0.7), in: .capsule)
              .overlay(Capsule().strokeBorder(Color(hex: 0x26A69E).opacity(0.35)))
          }
        }
        .padding(.top, 24)
      }
      .offset(x: 72, y: 74)
    }
    .frame(width: size.width, height: size.height)
    .clipShape(.rect(cornerRadius: 28))
  }
}

MainActor.assumeIsolated {
  let renderer = ImageRenderer(content: Banner(icon: NSImage(contentsOf: iconSource)!, window: NSImage(contentsOf: screenshot)!))
  renderer.scale = 2
  // ImageRenderer produces 16 bits per channel. Redraw at 8 bits for a small PNG.
  let image = renderer.cgImage!
  let context = CGContext(
    data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
  )!
  context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
  let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
  try! rep.representation(using: .png, properties: [:])!.write(to: output)
  print("Wrote \(output.path)")
}
