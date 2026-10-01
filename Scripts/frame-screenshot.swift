#!/usr/bin/env swift

// Gives a raw window capture the look of a macOS screenshot: rounded corners,
// a soft shadow and a transparent margin. Rewrites the PNG in place.
//
//   swift Scripts/frame-screenshot.swift docs/screenshot-today-light.png

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("Usage: swift Scripts/frame-screenshot.swift <capture.png>\n".utf8))
    exit(2)
}

let url = URL(fileURLWithPath: CommandLine.arguments[1])
guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fatalError("Could not read \(url.path).")
}

// The capture is at 2x, so these are 10pt corners and a 48pt margin.
let radius = 20.0
let margin = 96.0
let width = Double(image.width)
let height = Double(image.height)

guard let context = CGContext(
    data: nil,
    width: Int(width + margin * 2),
    height: Int(height + margin * 2),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fatalError("Could not create a drawing context.")
}

let frame = CGRect(x: margin, y: margin, width: width, height: height)
let shape = CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil)

context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -24), blur: 70, color: CGColor(gray: 0, alpha: 0.3))
context.addPath(shape)
context.setFillColor(CGColor(gray: 0.5, alpha: 1))
context.fillPath()
context.restoreGState()

context.addPath(shape)
context.clip()
context.draw(image, in: frame)

guard let framed = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("Could not write \(url.path).")
}
CGImageDestinationAddImage(destination, framed, nil)
CGImageDestinationFinalize(destination)
