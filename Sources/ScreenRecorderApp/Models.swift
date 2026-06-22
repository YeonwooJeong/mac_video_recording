import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

enum RecordingFormat: String, CaseIterable, Identifiable {
    case mp4
    case gif

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mp4:
            return "MP4"
        case .gif:
            return "GIF"
        }
    }

    var fileExtension: String {
        switch self {
        case .mp4:
            return "mp4"
        case .gif:
            return "gif"
        }
    }

    var symbolName: String {
        switch self {
        case .mp4:
            return "film"
        case .gif:
            return "photo.stack"
        }
    }
}

enum CaptureMode: String, CaseIterable, Identifiable {
    case fullDisplay
    case window
    case region

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fullDisplay:
            return "전체 화면"
        case .window:
            return "특정 창"
        case .region:
            return "지정 영역"
        }
    }

    var symbolName: String {
        switch self {
        case .fullDisplay:
            return "display"
        case .window:
            return "macwindow"
        case .region:
            return "selection.pin.in.out"
        }
    }
}

struct DisplayItem: Identifiable, Equatable {
    let id: CGDirectDisplayID
    let display: SCDisplay
    let title: String
    let frame: CGRect
    let scale: CGFloat

    static func == (lhs: DisplayItem, rhs: DisplayItem) -> Bool {
        lhs.id == rhs.id
    }
}

struct WindowItem: Identifiable, Equatable {
    let id: CGWindowID
    let window: SCWindow
    let title: String
    let applicationName: String
    let frame: CGRect
    let scale: CGFloat

    var displayTitle: String {
        if title.isEmpty {
            return applicationName
        }
        return "\(applicationName) - \(title)"
    }

    static func == (lhs: WindowItem, rhs: WindowItem) -> Bool {
        lhs.id == rhs.id
    }
}

enum CaptureTarget {
    case display(DisplayItem)
    case window(WindowItem)
    case region(display: DisplayItem, appKitRect: CGRect)
}

enum RecorderError: LocalizedError {
    case noDisplaySelected
    case noWindowSelected
    case noRegionSelected
    case screenRecordingPermissionRequired
    case invalidBitrate
    case invalidAudioBitrate
    case invalidFrameRate
    case invalidRegion
    case invalidGIFEditSize
    case invalidGIFQuality
    case noGIFToEdit
    case noGIFFrames
    case gifWriteFailed
    case writerInputRejected
    case writerStartFailed
    case outputFileAlreadyExists(URL)

    var errorDescription: String? {
        switch self {
        case .noDisplaySelected:
            return "녹화할 화면을 선택해주세요."
        case .noWindowSelected:
            return "녹화할 창을 선택해주세요."
        case .noRegionSelected:
            return "녹화할 영역을 먼저 지정해주세요."
        case .screenRecordingPermissionRequired:
            return "화면 기록 권한이 필요합니다. 이미 허용했다면 앱을 완전히 종료한 뒤 다시 실행해주세요."
        case .invalidBitrate:
            return "비트레이트는 100 kbps 이상의 숫자로 입력해주세요."
        case .invalidAudioBitrate:
            return "오디오 음질은 16 kbps 이상의 숫자로 입력해주세요."
        case .invalidFrameRate:
            return "GIF 프레임은 1부터 60 사이의 숫자로 입력해주세요."
        case .invalidRegion:
            return "지정 영역이 너무 작거나 화면 밖에 있습니다."
        case .invalidGIFEditSize:
            return "GIF 편집 크기는 가로/세로 20 px 이상으로 입력해주세요."
        case .invalidGIFQuality:
            return "GIF 화질은 1부터 100 사이의 숫자로 입력해주세요."
        case .noGIFToEdit:
            return "편집할 GIF 파일이 없습니다."
        case .noGIFFrames:
            return "GIF로 저장할 프레임이 없습니다."
        case .gifWriteFailed:
            return "GIF 파일을 저장하지 못했습니다."
        case .writerInputRejected:
            return "MP4 입력을 만들 수 없습니다."
        case .writerStartFailed:
            return "MP4 파일 쓰기를 시작할 수 없습니다."
        case .outputFileAlreadyExists(let url):
            return "이미 같은 이름의 파일이 있습니다: \(url.lastPathComponent)"
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }
}
