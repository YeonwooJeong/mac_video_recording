import AppKit
import AudioToolbox
import AVFoundation
import CoreGraphics
import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

final class ScreenRecorder: NSObject {
    var onRuntimeError: ((String) -> Void)?

    private let outputQueue = DispatchQueue(label: "screen-recorder.output.queue")
    private var stream: SCStream?
    private var writer: RecordingSampleWriter?
    private var outputURL: URL?

    func startMP4(
        target: CaptureTarget,
        videoBitrateKbps: Int,
        frameRate: Int,
        includeAudio: Bool,
        audioBitrateKbps: Int,
        outputURL: URL
    ) async throws {
        guard stream == nil else { return }

        let setup = try makeCaptureSetup(for: target, frameRate: frameRate, includeAudio: includeAudio)
        let writer = try MP4SampleWriter(
            outputURL: outputURL,
            width: setup.width,
            height: setup.height,
            videoBitrateKbps: videoBitrateKbps,
            videoFrameRate: frameRate,
            audioBitrateKbps: includeAudio ? audioBitrateKbps : nil
        )

        try await startStream(with: setup, writer: writer, outputURL: outputURL, includeAudio: includeAudio)
    }

    func startGIF(target: CaptureTarget, frameRate: Int, outputURL: URL) async throws {
        guard stream == nil else { return }

        let setup = try makeCaptureSetup(for: target, frameRate: frameRate, includeAudio: false)
        let writer = try GIFSampleWriter(outputURL: outputURL, frameRate: frameRate)

        try await startStream(with: setup, writer: writer, outputURL: outputURL, includeAudio: false)
    }

    func stop() async throws -> URL? {
        guard let stream else {
            return outputURL
        }

        var stopError: Error?
        do {
            try await stopCapture(stream)
        } catch {
            stopError = error
        }

        try await finishWriter()

        let finishedURL = outputURL
        self.stream = nil
        self.writer = nil
        self.outputURL = nil

        if let stopError {
            throw stopError
        }

        return finishedURL
    }

    private func startStream(
        with setup: CaptureSetup,
        writer: RecordingSampleWriter,
        outputURL: URL,
        includeAudio: Bool
    ) async throws {
        let stream = SCStream(filter: setup.filter, configuration: setup.configuration, delegate: self)

        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)

            if includeAudio {
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: outputQueue)
            }

            self.stream = stream
            self.writer = writer
            self.outputURL = outputURL

            try await startCapture(stream)
        } catch {
            self.stream = nil
            self.writer = nil
            self.outputURL = nil
            writer.cancel()
            throw error
        }
    }

    private func makeCaptureSetup(for target: CaptureTarget, frameRate: Int, includeAudio: Bool) throws -> CaptureSetup {
        let filter: SCContentFilter
        let pointSize: CGSize
        let scale: CGFloat

        switch target {
        case .display(let display):
            filter = SCContentFilter(display: display.display, excludingWindows: [])
            pointSize = display.frame.size
            scale = display.scale

        case .window(let window):
            filter = SCContentFilter(desktopIndependentWindow: window.window)
            pointSize = window.frame.size
            scale = window.scale

        case .region(let display, let appKitRect):
            let sourceRect = Self.sourceRect(forAppKitRect: appKitRect, in: display)
            guard sourceRect.width >= 20, sourceRect.height >= 20 else {
                throw RecorderError.invalidRegion
            }

            filter = SCContentFilter(display: display.display, excludingWindows: [])
            pointSize = sourceRect.size
            scale = display.scale

            let configuration = Self.baseConfiguration(
                width: pointSize.width,
                height: pointSize.height,
                scale: scale,
                frameRate: frameRate,
                includeAudio: includeAudio
            )
            configuration.sourceRect = sourceRect
            return CaptureSetup(filter: filter, configuration: configuration, width: configuration.width, height: configuration.height)
        }

        let configuration = Self.baseConfiguration(
            width: pointSize.width,
            height: pointSize.height,
            scale: scale,
            frameRate: frameRate,
            includeAudio: includeAudio
        )
        return CaptureSetup(filter: filter, configuration: configuration, width: configuration.width, height: configuration.height)
    }

    private static func baseConfiguration(
        width: CGFloat,
        height: CGFloat,
        scale: CGFloat,
        frameRate: Int,
        includeAudio: Bool
    ) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = evenPixelCount(width * scale)
        configuration.height = evenPixelCount(height * scale)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(1, frameRate)))
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.queueDepth = 5
        configuration.showsCursor = true
        configuration.scalesToFit = false

        if includeAudio {
            configuration.capturesAudio = true
            configuration.sampleRate = 48_000
            configuration.channelCount = 2
            configuration.excludesCurrentProcessAudio = false
        }

        if #available(macOS 14.0, *) {
            configuration.preservesAspectRatio = true
            configuration.ignoreShadowsSingleWindow = false
        }

        return configuration
    }

    private static func sourceRect(forAppKitRect appKitRect: CGRect, in display: DisplayItem) -> CGRect {
        let clipped = appKitRect.standardized.intersection(display.frame)
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else {
            return .zero
        }

        let localX = clipped.minX - display.frame.minX
        let localBottomY = clipped.minY - display.frame.minY

        // AppKit screen coordinates grow upward from the bottom-left, while ScreenCaptureKit
        // source rectangles use the display's logical top-left origin.
        let localTopY = display.frame.height - localBottomY - clipped.height

        return CGRect(
            x: max(0, localX),
            y: max(0, localTopY),
            width: min(clipped.width, display.frame.width),
            height: min(clipped.height, display.frame.height)
        ).integral
    }

    private static func evenPixelCount(_ value: CGFloat) -> Int {
        var result = max(2, Int(ceil(value)))
        if result % 2 != 0 {
            result += 1
        }
        return result
    }

    private func startCapture(_ stream: SCStream) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            stream.startCapture { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func stopCapture(_ stream: SCStream) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            stream.stopCapture { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func finishWriter() async throws {
        guard let writer else { return }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            outputQueue.async {
                writer.finish { result in
                    continuation.resume(with: result)
                }
            }
        }
    }
}

extension ScreenRecorder: SCStreamOutput, SCStreamDelegate {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        switch type {
        case .screen:
            writer?.appendVideo(sampleBuffer)
        case .audio:
            writer?.appendAudio(sampleBuffer)
        default:
            break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onRuntimeError?("녹화가 중단되었습니다: \(error.localizedDescription)")
    }
}

private struct CaptureSetup {
    let filter: SCContentFilter
    let configuration: SCStreamConfiguration
    let width: Int
    let height: Int
}

private protocol RecordingSampleWriter: AnyObject, Sendable {
    func appendVideo(_ sampleBuffer: CMSampleBuffer)
    func appendAudio(_ sampleBuffer: CMSampleBuffer)
    func finish(_ completion: @escaping (Result<Void, Error>) -> Void)
    func cancel()
}

private final class MP4SampleWriter: RecordingSampleWriter {
    private let assetWriter: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let audioInput: AVAssetWriterInput?
    private var didStartSession = false
    private var didFinish = false

    init(
        outputURL: URL,
        width: Int,
        height: Int,
        videoBitrateKbps: Int,
        videoFrameRate: Int,
        audioBitrateKbps: Int?
    ) throws {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            throw RecorderError.outputFileAlreadyExists(outputURL)
        }

        assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: videoBitrateKbps * 1000,
                AVVideoExpectedSourceFrameRateKey: videoFrameRate,
                AVVideoMaxKeyFrameIntervalKey: videoFrameRate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]

        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true

        guard assetWriter.canAdd(videoInput) else {
            throw RecorderError.writerInputRejected
        }
        assetWriter.add(videoInput)

        if let audioBitrateKbps {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 48_000,
                AVEncoderBitRateKey: audioBitrateKbps * 1000
            ]

            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = true

            guard assetWriter.canAdd(input) else {
                throw RecorderError.writerInputRejected
            }

            assetWriter.add(input)
            audioInput = input
        } else {
            audioInput = nil
        }
    }

    func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        guard CMSampleBufferGetImageBuffer(sampleBuffer) != nil else { return }
        append(sampleBuffer, to: videoInput)
    }

    func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        guard let audioInput else { return }
        append(sampleBuffer, to: audioInput)
    }

    private func append(_ sampleBuffer: CMSampleBuffer, to input: AVAssetWriterInput) {
        guard !didFinish else { return }
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }

        if !didStartSession {
            let startTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

            guard assetWriter.startWriting() else {
                didFinish = true
                return
            }

            assetWriter.startSession(atSourceTime: startTime.isValid ? startTime : .zero)
            didStartSession = true
        }

        guard assetWriter.status == .writing else { return }
        guard input.isReadyForMoreMediaData else { return }

        if !input.append(sampleBuffer) {
            didFinish = true
        }
    }

    func finish(_ completion: @escaping (Result<Void, Error>) -> Void) {
        guard !didFinish else {
            if let error = assetWriter.error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
            return
        }

        didFinish = true

        if assetWriter.status == .unknown {
            assetWriter.cancelWriting()
            completion(.success(()))
            return
        }

        if assetWriter.status == .writing {
            videoInput.markAsFinished()
            audioInput?.markAsFinished()
        }

        assetWriter.finishWriting { [assetWriter] in
            if let error = assetWriter.error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }

    func cancel() {
        didFinish = true
        assetWriter.cancelWriting()
    }
}

private final class GIFSampleWriter: RecordingSampleWriter {
    private let outputURL: URL
    private let frameDelay: Double
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var frames: [CGImage] = []
    private var lastFrameTime: CMTime?
    private var didFinish = false

    init(outputURL: URL, frameRate: Int) throws {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            throw RecorderError.outputFileAlreadyExists(outputURL)
        }

        self.outputURL = outputURL
        frameDelay = 1.0 / Double(max(1, frameRate))
    }

    func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        guard !didFinish else { return }
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if let lastFrameTime, presentationTime.isValid {
            let elapsed = CMTimeSubtract(presentationTime, lastFrameTime).seconds
            guard elapsed.isFinite, elapsed >= frameDelay * 0.85 else { return }
        }

        let image = CIImage(cvPixelBuffer: imageBuffer)
        let rect = CGRect(
            x: 0,
            y: 0,
            width: CVPixelBufferGetWidth(imageBuffer),
            height: CVPixelBufferGetHeight(imageBuffer)
        )

        guard let cgImage = context.createCGImage(image, from: rect) else { return }
        frames.append(cgImage)
        lastFrameTime = presentationTime.isValid ? presentationTime : CMTime(seconds: Double(frames.count) * frameDelay, preferredTimescale: 600)
    }

    func appendAudio(_ sampleBuffer: CMSampleBuffer) {}

    func finish(_ completion: @escaping (Result<Void, Error>) -> Void) {
        didFinish = true

        guard !frames.isEmpty else {
            completion(.failure(RecorderError.noGIFFrames))
            return
        }

        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.gif.identifier as CFString,
            frames.count,
            nil
        ) else {
            completion(.failure(RecorderError.gifWriteFailed))
            return
        }

        let gifProperties: [CFString: Any] = [
            kCGImagePropertyGIFLoopCount: 0
        ]
        let fileProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: gifProperties
        ]
        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)

        let perFrameGIFProperties: [CFString: Any] = [
            kCGImagePropertyGIFDelayTime: frameDelay,
            kCGImagePropertyGIFUnclampedDelayTime: frameDelay
        ]
        let frameProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: perFrameGIFProperties
        ]

        for frame in frames {
            CGImageDestinationAddImage(destination, frame, frameProperties as CFDictionary)
        }

        if CGImageDestinationFinalize(destination) {
            completion(.success(()))
        } else {
            completion(.failure(RecorderError.gifWriteFailed))
        }
    }

    func cancel() {
        didFinish = true
        frames.removeAll()
    }
}

extension MP4SampleWriter: @unchecked Sendable {}
extension GIFSampleWriter: @unchecked Sendable {}
