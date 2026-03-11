#!/bin/bash

# Generate PrivateCopyClip app icon from SF Symbol
ICONSET="iconset"
mkdir -p "$ICONSET"

# Render a 1024x1024 icon using a Swift inline script
cat > /tmp/render_clip_icon.swift << 'SWIFT'
import Cocoa

let symbolName = "doc.on.clipboard.fill"
let size = CGSize(width: 1024, height: 1024)

guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else {
    print("Failed to load symbol"); exit(1)
}

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size.width),
    pixelsHigh: Int(size.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else { print("Failed to create bitmap"); exit(1) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Background — deep indigo blue
let bgColor = NSColor(calibratedRed: 0.18, green: 0.32, blue: 0.82, alpha: 1.0)
bgColor.setFill()
CGRect(origin: .zero, size: size).fill()

// Draw white symbol centered
let config = NSImage.SymbolConfiguration(pointSize: 580, weight: .medium)
let configured = symbol.withSymbolConfiguration(config)
let white = configured?.withSymbolConfiguration(
    NSImage.SymbolConfiguration(hierarchicalColor: .white)
)
white?.draw(in: CGRect(x: 222, y: 200, width: 580, height: 580))

NSGraphicsContext.restoreGraphicsState()

if let data = rep.representation(using: .png, properties: [:]) {
    try? data.write(to: URL(fileURLWithPath: "/tmp/clip_icon_1024.png"))
    print("Icon rendered.")
}
SWIFT

swift /tmp/render_clip_icon.swift

SRC="/tmp/clip_icon_1024.png"

sips -z 16   16   "$SRC" --out "$ICONSET/icon_16x16.png"
sips -z 32   32   "$SRC" --out "$ICONSET/icon_16x16@2x.png"
sips -z 32   32   "$SRC" --out "$ICONSET/icon_32x32.png"
sips -z 64   64   "$SRC" --out "$ICONSET/icon_32x32@2x.png"
sips -z 128  128  "$SRC" --out "$ICONSET/icon_128x128.png"
sips -z 256  256  "$SRC" --out "$ICONSET/icon_128x128@2x.png"
sips -z 256  256  "$SRC" --out "$ICONSET/icon_256x256.png"
sips -z 512  512  "$SRC" --out "$ICONSET/icon_256x256@2x.png"
sips -z 512  512  "$SRC" --out "$ICONSET/icon_512x512.png"
cp "$SRC"         "$ICONSET/icon_512x512@2x.png"

echo "✅ Icon sizes generated in ./$ICONSET/"
