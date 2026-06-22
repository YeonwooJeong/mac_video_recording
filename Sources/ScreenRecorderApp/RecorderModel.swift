import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

@MainActor
final class RecorderModel: ObservableObject {
    @Published var recordingFormat: RecordingFormat = .mp4
    @Published var mode: CaptureMode = .fullDisplay
    @Published var bitrateText = "2200"
    @Published var videoFrameRate = 30
    @Published var includeAudio = true
    @Published var audioBitrateText = "64"
    @Published var gifFrameRateText = "20"
    @Published var saveDirectory: URL
    @Published var displays: [DisplayItem] = []
    @Published var windows: [WindowItem] = []
    @Published var selectedDisplayID: CGDirectDisplayID?
    @Published var selectedWindowID: CGWindowID?
    @Published var selectedRegion: CGRect?
    @Published var isRecording = false
    @Published var statusMessage = "준비됨"
    @Published var lastOutputURL: URL?
    @Published var lastGIFURL: URL?
    @Published var isShowingGIFEditor = false
    @Published var isEditingGIF = false
    @Published var gifEditWidthText = ""
    @Published var gifEditHeightText = ""
    @Published var gifQualityText = "80"

    private let recorder = ScreenRecorder()
    private var regionSelectionController: RegionSelectionController?
    private var activeRecordingFormat: RecordingFormat?

    init() {
        let storedPath = UserDefaults.standard.string(forKey: "saveDirectoryPath")
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        saveDirectory = storedPath.map(URL.init(fileURLWithPath:)) ?? downloads ?? FileManager.default.homeDirectoryForCurrentUser

        recorder.onRuntimeError = { [weak self] message in
            Task { @MainActor in
                self?.isRecording = false
                self?.activeRecordingFormat = nil
                self?.statusMessage = message
            }
        }
    }

    var selectedRegionText: String {
        guard let rect = selectedRegion else {
            return "선택된 영역 없음"
        }
        return "\(Int(rect.width)) x \(Int(rect.height)) pt"
    }

    var screenRecordingPermissionGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    func refreshShareableContent() async {
        guard screenRecordingPermissionGranted else {
            displays = []
            windows = []
            selectedDisplayID = nil
            selectedWindowID = nil
            statusMessage = "화면 기록 권한이 필요합니다. 이미 허용했다면 앱을 완전히 종료한 뒤 다시 실행해주세요."
            return
        }

        statusMessage = "화면과 창 목록을 읽는 중..."

        do {
            let content = try await SCShareableContent.current
            let screensByID = Dictionary(uniqueKeysWithValues: NSScreen.screens.compactMap { screen -> (CGDirectDisplayID, NSScreen)? in
                guard let id = screen.displayID else { return nil }
                return (id, screen)
            })

            let displayItems = content.displays.enumerated().map { index, display in
                let screen = screensByID[display.displayID]
                let frame = screen?.frame ?? display.frame
                let scale = screen?.backingScaleFactor ?? 1
                return DisplayItem(
                    id: display.displayID,
                    display: display,
                    title: "화면 \(index + 1) (\(Int(frame.width)) x \(Int(frame.height)) pt)",
                    frame: frame,
                    scale: scale
                )
            }

            let currentPID = ProcessInfo.processInfo.processIdentifier
            let windowItems = content.windows
                .filter { window in
                    guard window.isOnScreen, window.windowLayer == 0 else { return false }
                    guard window.owningApplication?.processID != currentPID else { return false }
                    return window.frame.width >= 80 && window.frame.height >= 60
                }
                .map { window in
                    let applicationName = window.owningApplication?.applicationName ?? "알 수 없는 앱"
                    let title = window.title ?? ""
                    let scale = Self.scaleForRect(window.frame, displays: displayItems)
                    return WindowItem(
                        id: window.windowID,
                        window: window,
                        title: title,
                        applicationName: applicationName,
                        frame: window.frame,
                        scale: scale
                    )
                }
                .sorted { (lhs: WindowItem, rhs: WindowItem) in
                    lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
                }

            displays = displayItems
            windows = windowItems

            if selectedDisplayID == nil || !displayItems.contains(where: { $0.id == selectedDisplayID }) {
                selectedDisplayID = displayItems.first?.id
            }

            if selectedWindowID == nil || !windowItems.contains(where: { $0.id == selectedWindowID }) {
                selectedWindowID = windowItems.first?.id
            }

            statusMessage = "준비됨"
        } catch {
            statusMessage = "목록을 가져오지 못했습니다: \(error.localizedDescription)"
        }
    }

    func requestScreenRecordingPermission() {
        if CGPreflightScreenCaptureAccess() {
            statusMessage = "화면 기록 권한이 허용되어 있습니다."
            Task {
                await refreshShareableContent()
            }
            return
        }

        statusMessage = "시스템 권한 대화상자를 확인한 뒤 앱을 다시 실행해주세요."
        let granted = CGRequestScreenCaptureAccess()

        if granted {
            statusMessage = "권한이 허용되었습니다. 앱을 완전히 종료한 뒤 다시 실행해주세요."
        } else {
            statusMessage = "권한이 아직 허용되지 않았습니다. 시스템 설정에서 화면 기록을 허용해주세요."
        }
    }

    func openScreenRecordingSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")

        if let url {
            NSWorkspace.shared.open(url)
        }
    }

    func chooseSaveDirectory() {
        let panel = NSOpenPanel()
        panel.title = "저장 폴더 선택"
        panel.prompt = "선택"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = saveDirectory

        if panel.runModal() == .OK, let url = panel.url {
            saveDirectory = url
            UserDefaults.standard.set(url.path, forKey: "saveDirectoryPath")
            statusMessage = "저장 폴더가 변경되었습니다."
        }
    }

    func resetSaveDirectoryToDownloads() {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        saveDirectory = downloads ?? FileManager.default.homeDirectoryForCurrentUser
        UserDefaults.standard.set(saveDirectory.path, forKey: "saveDirectoryPath")
        statusMessage = "저장 폴더를 다운로드로 되돌렸습니다."
    }

    func openSaveDirectory() {
        NSWorkspace.shared.open(saveDirectory)
    }

    func revealLastRecording() {
        guard let lastOutputURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastOutputURL])
    }

    func selectRegion() {
        guard !isRecording else { return }

        let controller = RegionSelectionController()
        regionSelectionController = controller
        statusMessage = "드래그해서 녹화할 영역을 지정하세요."

        controller.begin { [weak self] rect in
            Task { @MainActor in
                guard let self else { return }
                self.regionSelectionController = nil

                guard let rect, rect.width >= 20, rect.height >= 20 else {
                    self.statusMessage = "영역 선택이 취소되었습니다."
                    return
                }

                self.selectedRegion = rect.standardized
                self.mode = .region

                if let display = self.displayForRegion(rect) {
                    self.selectedDisplayID = display.id
                }

                self.statusMessage = "영역이 지정되었습니다."
            }
        }
    }

    func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    func startRecording() {
        guard !isRecording else { return }

        Task {
            do {
                guard screenRecordingPermissionGranted else {
                    throw RecorderError.screenRecordingPermissionRequired
                }

                if displays.isEmpty {
                    await refreshShareableContent()
                }

                let target = try selectedTarget()
                let outputURL = makeOutputURL(fileExtension: recordingFormat.fileExtension)

                statusMessage = "\(recordingFormat.title) 녹화 준비 중..."
                isRecording = true
                activeRecordingFormat = recordingFormat

                switch recordingFormat {
                case .mp4:
                    let bitrate = try validatedBitrate()
                    let audioBitrate = includeAudio ? try validatedAudioBitrate() : 64
                    try await recorder.startMP4(
                        target: target,
                        videoBitrateKbps: bitrate,
                        frameRate: videoFrameRate,
                        includeAudio: includeAudio,
                        audioBitrateKbps: audioBitrate,
                        outputURL: outputURL
                    )

                case .gif:
                    let frameRate = try validatedFrameRate()
                    try await recorder.startGIF(target: target, frameRate: frameRate, outputURL: outputURL)
                }

                statusMessage = "\(recordingFormat.title) 녹화 중..."
            } catch {
                isRecording = false
                activeRecordingFormat = nil
                statusMessage = error.localizedDescription
            }
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        Task {
            let format = activeRecordingFormat ?? recordingFormat
            statusMessage = "\(format.title) 파일을 마무리하는 중..."

            do {
                let outputURL = try await recorder.stop()
                isRecording = false
                activeRecordingFormat = nil

                if let outputURL {
                    lastOutputURL = outputURL

                    if format == .gif {
                        lastGIFURL = outputURL
                        prepareGIFEditor(for: outputURL)
                    }

                    statusMessage = "저장 완료: \(outputURL.lastPathComponent)"
                } else {
                    statusMessage = "녹화가 중지되었습니다."
                }
            } catch {
                isRecording = false
                activeRecordingFormat = nil
                statusMessage = "중지 실패: \(error.localizedDescription)"
            }
        }
    }

    func openGIFEditor() {
        guard let lastGIFURL else {
            statusMessage = RecorderError.noGIFToEdit.localizedDescription
            return
        }

        prepareGIFEditor(for: lastGIFURL)
    }

    func applyGIFEdit() {
        guard !isEditingGIF else { return }
        guard let inputURL = lastGIFURL else {
            statusMessage = RecorderError.noGIFToEdit.localizedDescription
            return
        }

        do {
            let size = try validatedGIFEditSize()
            let quality = try validatedGIFQuality()
            let outputURL = makeEditedGIFURL(for: inputURL)

            isEditingGIF = true
            statusMessage = "GIF 편집본을 저장하는 중..."

            Task {
                do {
                    try await Task.detached {
                        try GIFEditor.reencode(
                            inputURL: inputURL,
                            outputURL: outputURL,
                            targetSize: size,
                            quality: quality
                        )
                    }.value

                    isEditingGIF = false
                    lastGIFURL = outputURL
                    lastOutputURL = outputURL
                    prepareGIFEditorFields(for: outputURL)
                    statusMessage = "GIF 편집 완료: \(outputURL.lastPathComponent)"
                } catch {
                    isEditingGIF = false
                    statusMessage = "GIF 편집 실패: \(error.localizedDescription)"
                }
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func prepareGIFEditor(for url: URL) {
        prepareGIFEditorFields(for: url)
        gifQualityText = "80"
        isShowingGIFEditor = true
    }

    private func prepareGIFEditorFields(for url: URL) {
        if let size = GIFEditor.firstFrameSize(of: url) {
            gifEditWidthText = "\(Int(size.width))"
            gifEditHeightText = "\(Int(size.height))"
        }
    }

    private func validatedBitrate() throws -> Int {
        let text = bitrateText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let bitrate = Int(text), bitrate >= 100 else {
            throw RecorderError.invalidBitrate
        }
        return bitrate
    }

    private func validatedAudioBitrate() throws -> Int {
        let text = audioBitrateText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let bitrate = Int(text), bitrate >= 16 else {
            throw RecorderError.invalidAudioBitrate
        }
        return bitrate
    }

    private func validatedFrameRate() throws -> Int {
        let text = gifFrameRateText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let frameRate = Int(text), (1...60).contains(frameRate) else {
            throw RecorderError.invalidFrameRate
        }
        return frameRate
    }

    private func validatedGIFEditSize() throws -> CGSize {
        let widthText = gifEditWidthText.trimmingCharacters(in: .whitespacesAndNewlines)
        let heightText = gifEditHeightText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard
            let width = Int(widthText),
            let height = Int(heightText),
            width >= 20,
            height >= 20
        else {
            throw RecorderError.invalidGIFEditSize
        }

        return CGSize(width: width, height: height)
    }

    private func validatedGIFQuality() throws -> CGFloat {
        let text = gifQualityText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(text), (1...100).contains(value) else {
            throw RecorderError.invalidGIFQuality
        }

        return CGFloat(value) / 100
    }

    private func selectedTarget() throws -> CaptureTarget {
        switch mode {
        case .fullDisplay:
            guard let display = displays.first(where: { $0.id == selectedDisplayID }) ?? displays.first else {
                throw RecorderError.noDisplaySelected
            }
            return .display(display)

        case .window:
            guard let window = windows.first(where: { $0.id == selectedWindowID }) else {
                throw RecorderError.noWindowSelected
            }
            return .window(window)

        case .region:
            guard let rect = selectedRegion else {
                throw RecorderError.noRegionSelected
            }
            guard let display = displayForRegion(rect) ?? displays.first(where: { $0.id == selectedDisplayID }) else {
                throw RecorderError.noDisplaySelected
            }
            return .region(display: display, appKitRect: rect)
        }
    }

    private func makeOutputURL(fileExtension: String) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"

        let prefix = fileExtension == "gif" ? "GIF Recording" : "Screen Recording"
        let baseName = "\(prefix) \(formatter.string(from: Date()))"
        var candidate = saveDirectory.appendingPathComponent(baseName).appendingPathExtension(fileExtension)
        var suffix = 2

        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = saveDirectory.appendingPathComponent("\(baseName) \(suffix)").appendingPathExtension(fileExtension)
            suffix += 1
        }

        return candidate
    }

    private func makeEditedGIFURL(for sourceURL: URL) -> URL {
        let directory = sourceURL.deletingLastPathComponent()
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        var candidate = directory.appendingPathComponent("\(baseName) edited").appendingPathExtension("gif")
        var suffix = 2

        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName) edited \(suffix)").appendingPathExtension("gif")
            suffix += 1
        }

        return candidate
    }

    private func displayForRegion(_ rect: CGRect) -> DisplayItem? {
        displays
            .map { display -> (display: DisplayItem, area: CGFloat) in
                let intersection = display.frame.intersection(rect)
                let area = max(0, intersection.width) * max(0, intersection.height)
                return (display, area)
            }
            .filter { $0.area > 0 }
            .max { $0.area < $1.area }?
            .display
    }

    private static func scaleForRect(_ rect: CGRect, displays: [DisplayItem]) -> CGFloat {
        displays
            .map { display -> (scale: CGFloat, area: CGFloat) in
                let intersection = display.frame.intersection(rect)
                return (display.scale, max(0, intersection.width) * max(0, intersection.height))
            }
            .max { $0.area < $1.area }?
            .scale ?? NSScreen.main?.backingScaleFactor ?? 1
    }
}
