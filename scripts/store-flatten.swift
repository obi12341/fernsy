// Removes the alpha channel of PNGs in place (App Store Connect refuses screenshots and header
// images with transparency): draws each image onto an opaque RGB bitmap of the same size.
//
//   swift scripts/store-flatten.swift dist/store/iphone/en/*.png
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

var failed = false
for path in CommandLine.arguments.dropFirst() {
    let url = URL(fileURLWithPath: path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        print("cannot read \(path)"); failed = true; continue
    }
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard let flat = context.makeImage(),
          let out = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        print("cannot write \(path)"); failed = true; continue
    }
    CGImageDestinationAddImage(out, flat, nil)
    if !CGImageDestinationFinalize(out) { print("cannot write \(path)"); failed = true }
}
exit(failed ? 1 : 0)
