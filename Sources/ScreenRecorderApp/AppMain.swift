import SwiftUI

@main
struct ScreenRecorderApplication: App {
    @StateObject private var recorderModel = RecorderModel()

    var body: some Scene {
        WindowGroup("화면 녹화 앱") {
            ContentView()
                .environmentObject(recorderModel)
                .frame(minWidth: 680, minHeight: 560)
        }
        .defaultSize(width: 720, height: 600)
        .commands {
            RecorderCommands(model: recorderModel)
        }
    }
}
