import SwiftUI

struct RecorderCommands: Commands {
    @ObservedObject var model: RecorderModel

    var body: some Commands {
        CommandMenu("녹화") {
            Picker("녹화 형식", selection: $model.recordingFormat) {
                ForEach(RecordingFormat.allCases) { format in
                    Text(format.title).tag(format)
                }
            }
            .disabled(model.isRecording)

            Button(model.isRecording ? "녹화 중지" : "녹화 시작") {
                model.toggleRecording()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Button("저장 폴더 선택...") {
                model.chooseSaveDirectory()
            }
            .keyboardShortcut(",", modifiers: [.command])
            .disabled(model.isRecording)

            Button("저장 폴더 열기") {
                model.openSaveDirectory()
            }

            if model.lastOutputURL != nil {
                Button("마지막 녹화 파일 보기") {
                    model.revealLastRecording()
                }
            }

            if model.lastGIFURL != nil {
                Button("GIF 편집...") {
                    model.openGIFEditor()
                }
                .disabled(model.isRecording)
            }
        }
    }
}
