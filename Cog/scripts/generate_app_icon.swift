import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let documentURL = URL(
    fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources/AppIcon.icon"
)
let assetsURL = documentURL.appendingPathComponent("Assets")
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [red, green, blue, alpha])!
}

func point(from point: CGPoint, toward target: CGPoint, distance: CGFloat) -> CGPoint {
    let dx = target.x - point.x
    let dy = target.y - point.y
    let length = hypot(dx, dy)

    return CGPoint(
        x: point.x + (dx / length) * distance,
        y: point.y + (dy / length) * distance
    )
}

func roundedHexagonPath(size: CGFloat, radius: CGFloat, cornerInset: CGFloat) -> CGPath {
    let center = CGPoint(x: size / 2, y: size / 2)
    let vertices = (0..<6).map { index in
        let angle = CGFloat(index) * (.pi / 3)

        return CGPoint(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
        )
    }

    let path = CGMutablePath()
    let start = point(from: vertices[0], toward: vertices[1], distance: cornerInset)
    path.move(to: start)

    for index in 0..<6 {
        let nextIndex = (index + 1) % vertices.count
        let vertex = vertices[nextIndex]
        let nextVertex = vertices[(nextIndex + 1) % vertices.count]
        let lineEnd = point(from: vertex, toward: vertices[index], distance: cornerInset)
        let curveEnd = point(from: vertex, toward: nextVertex, distance: cornerInset)

        path.addLine(to: lineEnd)
        path.addQuadCurve(to: curveEnd, control: vertex)
    }

    path.closeSubpath()
    return path
}

func renderHexagonLayer(pixels: Int) throws -> CGImage {
    guard let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: pixels * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw NSError(domain: "AppIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create bitmap context"])
    }

    let size = CGFloat(pixels)
    context.clear(CGRect(x: 0, y: 0, width: size, height: size))
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    let center = CGPoint(x: size / 2, y: size / 2)
    let apertureRadius = size * 0.108
    let aperture = CGRect(
        x: center.x - apertureRadius,
        y: center.y - apertureRadius,
        width: apertureRadius * 2,
        height: apertureRadius * 2
    )

    context.addPath(roundedHexagonPath(size: size, radius: size * 0.36, cornerInset: size * 0.047))
    context.addEllipse(in: aperture)
    context.setFillColor(color(0, 0, 0))
    context.drawPath(using: .eoFill)

    guard let image = context.makeImage() else {
        throw NSError(domain: "AppIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not finalize bitmap"])
    }

    return image
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "AppIcon", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not create PNG destination"])
    }

    CGImageDestinationAddImage(destination, image, nil)

    if !CGImageDestinationFinalize(destination) {
        throw NSError(domain: "AppIcon", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not write PNG at \(url.path)"])
    }
}

let iconJSON = """
{
  "fill" : {
    "automatic-gradient" : "extended-srgb:1.00000,1.00000,1.00000,1.00000"
  },
  "groups" : [
    {
      "layers" : [
        {
          "glass" : true,
          "image-name" : "Hexagon.png",
          "name" : "Hexagon",
          "position" : {
            "scale" : 1,
            "translation-in-points" : [
              0,
              0
            ]
          }
        }
      ],
      "shadow" : {
        "kind" : "neutral",
        "opacity" : 0.42
      },
      "translucency" : {
        "enabled" : true,
        "value" : 0.34
      }
    }
  ],
  "supported-platforms" : {
    "squares" : "shared"
  }
}
"""

try FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: true)
try writePNG(renderHexagonLayer(pixels: 1024), to: assetsURL.appendingPathComponent("Hexagon.png"))
try iconJSON.write(to: documentURL.appendingPathComponent("icon.json"), atomically: true, encoding: .utf8)

print("Generated Icon Composer document at \(documentURL.path)")
