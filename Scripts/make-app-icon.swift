#!/usr/bin/env swift

// Turns one square piece of artwork into the macOS app icon set.
//
//   swift Scripts/make-app-icon.swift artwork.png
//
// The artwork should be a full-bleed square with no rounded corners of its own.
// This masks it to the macOS icon shape, adds the drop shadow the system
// expects, and writes every size the asset catalog asks for.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Apple draws the icon body inside 824 of the 1024pt canvas, leaving room for
// the shadow, so an icon sits correctly next to the system's own.
let canvas = 824.0
let padding = 100.0
let catalogSizes = [16, 32, 128, 256, 512].flatMap { [($0, 1), ($0, 2)] }

/// Apple's corner is a superellipse, not a circular arc, so a plain rounded
/// rectangle reads as visibly rounder than neighbouring icons.
func squircle(in rect: CGRect, exponent: Double = 5) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2
    let b = rect.height / 2
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let steps = 720

    for step in 0...steps {
        let t = 2 * Double.pi * Double(step) / Double(steps)
        let cosT = cos(t)
        let sinT = sin(t)
        let x = center.x + a * copysign(pow(abs(cosT), 2 / exponent), cosT)
        let y = center.y + b * copysign(pow(abs(sinT), 2 / exponent), sinT)
        if step == 0 {
            path.move(to: CGPoint(x: x, y: y))
        } else {
            path.addLine(to: CGPoint(x: x, y: y))
        }
    }

    path.closeSubpath()
    return path
}

func makeContext(size: Double) -> CGContext {
    guard let context = CGContext(
        data: nil,
        width: Int(size),
        height: Int(size),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fatalError("Could not create a \(Int(size))pt drawing context.")
    }
    context.interpolationQuality = .high
    return context
}

func loadImage(at url: URL) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        fatalError("Could not read artwork at \(url.path).")
    }
    return image
}

func write(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        fatalError("Could not write \(url.path).")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        fatalError("Could not finalize \(url.path).")
    }
}

func makeMaster(from artwork: CGImage) -> CGImage {
    let full = padding * 2 + canvas
    let context = makeContext(size: full)
    let body = CGRect(x: padding, y: padding, width: canvas, height: canvas)
    let shape = squircle(in: body)

    // Filling the shape first casts the shadow. The artwork then covers the
    // fill exactly, so only the shadow remains visible.
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -12),
        blur: 24,
        color: CGColor(gray: 0, alpha: 0.28)
    )
    context.addPath(shape)
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shape)
    context.clip()
    context.draw(artwork, in: body)
    context.restoreGState()

    guard let image = context.makeImage() else {
        fatalError("Could not render the icon master.")
    }
    return image
}

func resize(_ image: CGImage, to size: Int) -> CGImage {
    let context = makeContext(size: Double(size))
    context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    guard let resized = context.makeImage() else {
        fatalError("Could not render a \(size)pt icon.")
    }
    return resized
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("Usage: swift Scripts/make-app-icon.swift <artwork.png>\n".utf8))
    exit(2)
}

let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let artworkURL = URL(fileURLWithPath: CommandLine.arguments[1])
let resources = root.appending(path: "Resources", directoryHint: .isDirectory)
let iconSet = resources.appending(
    path: "Assets.xcassets/AppIcon.appiconset",
    directoryHint: .isDirectory
)

try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)

let master = makeMaster(from: loadImage(at: artworkURL))
write(master, to: resources.appending(path: "AppIcon.png", directoryHint: .notDirectory))

for (size, scale) in catalogSizes {
    let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@\(scale)x.png"
    write(resize(master, to: size * scale), to: iconSet.appending(path: name, directoryHint: .notDirectory))
    print("wrote \(name)")
}
