import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Direct off-screen sRGB drawing: no NSImage/lockFocus or display-server dependency.
let destination = CommandLine.arguments.dropFirst().first ?? "Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
let width = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(data: nil, width: width, height: width, bitsPerComponent: 8,
    bytesPerRow: width * 4, space: space,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.setAllowsAntialiasing(true)
func color(_ hex: UInt32) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat((hex >> 16) & 255)/255,
        CGFloat((hex >> 8) & 255)/255, CGFloat(hex & 255)/255, 1])!
}
func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat, _ fill: UInt32) {
    context.setFillColor(color(fill))
    context.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h),
        cornerWidth: r, cornerHeight: r, transform: nil))
    context.fillPath()
}
// Full bleed. iOS supplies the outer superellipse; never bake a mask or transparency.
context.setFillColor(color(0x58DDBB))
context.fill(CGRect(x: 0, y: 0, width: width, height: width))
// A generous, friendly television silhouette, with just enough tonal depth.
rounded(182, 226, 660, 526, 120, 0x24AE91)
rounded(182, 246, 660, 526, 120, 0xFFF9E9)
rounded(230, 294, 564, 430, 78, 0x153E45)
rounded(421, 172, 182, 44, 22, 0xFFF9E9)
rounded(489, 192, 46, 76, 20, 0xFFF9E9)
// Two clean pause bars: deliberate viewing, legible even at notification size.
rounded(370, 403, 76, 208, 24, 0xFFF9E9)
rounded(492, 403, 76, 208, 24, 0xFFF9E9)
// A warm time dial. The two hands form a quiet check rather than another play logo.
context.setFillColor(color(0xFFD45A))
context.fillEllipse(in: CGRect(x: 624, y: 208, width: 242, height: 242))
context.setStrokeColor(color(0x153E45)); context.setLineWidth(22)
context.setLineCap(.round); context.setLineJoin(.round)
context.move(to: CGPoint(x: 745, y: 391))
context.addLine(to: CGPoint(x: 745, y: 329))
context.addLine(to: CGPoint(x: 794, y: 300))
context.strokePath()
let image = context.makeImage()!
let url = URL(fileURLWithPath: destination)
let output = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(output, image, nil)
precondition(CGImageDestinationFinalize(output), "PNG write failed")
print("Wrote opaque sRGB icon: \(destination)")
// Regenerate every declared size from the same master in a single deterministic run.
let folder = url.deletingLastPathComponent()
let manifest = folder.appendingPathComponent("Contents.json")
if let entries = (try? JSONSerialization.jsonObject(with: Data(contentsOf: manifest))) as? [String: Any],
   let images = entries["images"] as? [[String: String]] {
    for entry in images {
        guard let file = entry["filename"], file != url.lastPathComponent,
              let rawSize = entry["size"]?.split(separator: "x").first,
              let base = Double(rawSize), let scaleText = entry["scale"],
              let scale = Double(scaleText.dropLast()) else { continue }
        let pixels = Int(base * scale)
        let scaled = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
            bytesPerRow: pixels * 4, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        scaled.interpolationQuality = .high
        scaled.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        let outputURL = folder.appendingPathComponent(file)
        let writer = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(writer, scaled.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(writer))
        let decoded = CGImageSourceCreateWithURL(outputURL as CFURL, nil)!
        let checked = CGImageSourceCreateImageAtIndex(decoded, 0, nil)!
        precondition(checked.width == pixels && checked.height == pixels)
        print("Verified \(file): \(pixels) × \(pixels)")
    }
}
let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
precondition(bytes[0] > 0 && bytes[1] > 0 && bytes[2] > 0, "Black icon output")
