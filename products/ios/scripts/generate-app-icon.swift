#!/usr/bin/env swift
//
// Renders the app icon into App/Resources/Assets.xcassets/AppIcon.appiconset.
// The icon is generated rather than hand-drawn so it stays reproducible and
// reviewable as code: run `swift scripts/generate-app-icon.swift` from
// products/ios after changing anything here.
//
// The mark is the rising line the trends renderer draws, on PostHog's brand
// orange. Dark and tinted variants ship the mark on transparency, which is what
// iOS composites over its own backdrop.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let side = 1024
let brandOrange = (red: CGFloat(0xF5) / 255, green: CGFloat(0x4E) / 255, blue: CGFloat(0x00) / 255)

func context(opaque: Bool) -> CGContext {
  CGContext(
    data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast).rawValue
  )!
}

func write(_ ctx: CGContext, to path: String) {
  guard let image = ctx.makeImage(),
    let destination = CGImageDestinationCreateWithURL(
      URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)
  else {
    fatalError("could not encode \(path)")
  }
  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else { fatalError("could not write \(path)") }
  print("wrote \(path)")
}

/// The rising line, drawn in the given color. Proportions are shared by every
/// variant so they read as the same icon.
func drawMark(_ ctx: CGContext, red: CGFloat, green: CGFloat, blue: CGFloat) {
  let points: [CGPoint] = [
    CGPoint(x: 0.19, y: 0.34), CGPoint(x: 0.38, y: 0.47), CGPoint(x: 0.56, y: 0.44),
    CGPoint(x: 0.78, y: 0.70),
  ].map { CGPoint(x: $0.x * CGFloat(side), y: $0.y * CGFloat(side)) }

  ctx.setStrokeColor(red: red, green: green, blue: blue, alpha: 1)
  ctx.setFillColor(red: red, green: green, blue: blue, alpha: 1)
  ctx.setLineWidth(CGFloat(side) * 0.075)
  ctx.setLineCap(.round)
  ctx.setLineJoin(.round)
  ctx.beginPath()
  ctx.move(to: points[0])
  for point in points.dropFirst() { ctx.addLine(to: point) }
  ctx.strokePath()

  let radius = CGFloat(side) * 0.072
  guard let last = points.last else { return }
  ctx.fillEllipse(
    in: CGRect(x: last.x - radius, y: last.y - radius, width: radius * 2, height: radius * 2))
}

let outputDirectory =
  CommandLine.arguments.count > 1
  ? CommandLine.arguments[1]
  : FileManager.default.currentDirectoryPath + "/App/Resources/Assets.xcassets/AppIcon.appiconset"

// Default: white mark on brand orange. App icons must not carry alpha.
do {
  let ctx = context(opaque: true)
  ctx.setFillColor(red: brandOrange.red, green: brandOrange.green, blue: brandOrange.blue, alpha: 1)
  ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
  drawMark(ctx, red: 1, green: 1, blue: 1)
  write(ctx, to: "\(outputDirectory)/AppIcon.png")
}

// Dark: the mark in brand orange over the system's dark backdrop.
do {
  let ctx = context(opaque: false)
  drawMark(ctx, red: 1, green: 0.42, blue: 0.17)
  write(ctx, to: "\(outputDirectory)/AppIcon-Dark.png")
}

// Tinted: grayscale, so the system can apply the user's tint.
do {
  let ctx = context(opaque: false)
  drawMark(ctx, red: 1, green: 1, blue: 1)
  write(ctx, to: "\(outputDirectory)/AppIcon-Tinted.png")
}
