import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum GIFEditor {
    static func firstFrameSize(of url: URL) -> CGSize? {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return nil
        }

        return CGSize(width: image.width, height: image.height)
    }

    static func reencode(inputURL: URL, outputURL: URL, targetSize: CGSize, quality: CGFloat) throws {
        guard
            targetSize.width >= 20,
            targetSize.height >= 20,
            let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil)
        else {
            throw RecorderError.invalidGIFEditSize
        }

        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else {
            throw RecorderError.noGIFFrames
        }

        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.gif.identifier as CFString,
            frameCount,
            nil
        ) else {
            throw RecorderError.gifWriteFailed
        }

        let normalizedQuality = max(0.01, min(1.0, quality))
        let context = CIContext(options: [.cacheIntermediates: false])

        let fileGIFProperties: [CFString: Any] = [
            kCGImagePropertyGIFLoopCount: 0
        ]
        let fileProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: fileGIFProperties,
            kCGImageDestinationLossyCompressionQuality: normalizedQuality
        ]
        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)

        for index in 0..<frameCount {
            guard let sourceFrame = CGImageSourceCreateImageAtIndex(source, index, nil) else {
                continue
            }

            guard let processedFrame = processedImage(
                sourceFrame,
                targetSize: targetSize,
                quality: normalizedQuality,
                context: context
            ) else {
                continue
            }

            let delay = frameDelay(from: source, index: index)
            let gifProperties: [CFString: Any] = [
                kCGImagePropertyGIFDelayTime: delay,
                kCGImagePropertyGIFUnclampedDelayTime: delay
            ]
            let frameProperties: [CFString: Any] = [
                kCGImagePropertyGIFDictionary: gifProperties,
                kCGImageDestinationLossyCompressionQuality: normalizedQuality
            ]

            CGImageDestinationAddImage(destination, processedFrame, frameProperties as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else {
            throw RecorderError.gifWriteFailed
        }
    }

    private static func processedImage(
        _ image: CGImage,
        targetSize: CGSize,
        quality: CGFloat,
        context: CIContext
    ) -> CGImage? {
        let scaleX = targetSize.width / CGFloat(image.width)
        let scaleY = targetSize.height / CGFloat(image.height)

        var ciImage = CIImage(cgImage: image)
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        if quality < 0.98 {
            let levels = max(4.0, 8.0 + Double(quality) * 56.0)
            ciImage = ciImage.applyingFilter("CIColorPosterize", parameters: [
                "inputLevels": levels
            ])
        }

        let rect = CGRect(origin: .zero, size: targetSize)
        return context.createCGImage(ciImage, from: rect)
    }

    private static func frameDelay(from source: CGImageSource, index: Int) -> Double {
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
            let gifProperties = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        else {
            return 0.05
        }

        let unclamped = gifProperties[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber
        let clamped = gifProperties[kCGImagePropertyGIFDelayTime] as? NSNumber
        let value = unclamped?.doubleValue ?? clamped?.doubleValue ?? 0.05

        return max(0.02, value)
    }
}
