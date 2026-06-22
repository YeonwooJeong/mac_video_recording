import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: RecorderModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            formatPicker
            modePicker
            targetControls
            recordingSettings
            statusArea
            Spacer(minLength: 0)
            actionBar
        }
        .padding(24)
        .task {
            await model.refreshShareableContent()
        }
        .sheet(isPresented: $model.isShowingGIFEditor) {
            GIFEditorSheet()
                .environmentObject(model)
                .frame(width: 420)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: model.recordingFormat.symbolName)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(model.isRecording ? .red : .primary)

            VStack(alignment: .leading, spacing: 2) {
                Text("화면 녹화 앱")
                    .font(.title2.weight(.semibold))
                Text("MP4, GIF")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                model.openScreenRecordingSettings()
            } label: {
                Label("설정 열기", systemImage: "gearshape")
            }

            Button {
                model.requestScreenRecordingPermission()
            } label: {
                Label("권한 확인", systemImage: model.screenRecordingPermissionGranted ? "checkmark.shield" : "exclamationmark.shield")
            }
        }
    }

    private var formatPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("녹화 형식")
                .font(.headline)

            Picker("녹화 형식", selection: $model.recordingFormat) {
                ForEach(RecordingFormat.allCases) { format in
                    Label(format.title, systemImage: format.symbolName)
                        .tag(format)
                }
            }
            .pickerStyle(.segmented)
            .disabled(model.isRecording)
        }
    }

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("녹화 방식")
                .font(.headline)

            Picker("녹화 방식", selection: $model.mode) {
                ForEach(CaptureMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbolName)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(model.isRecording)
        }
    }

    @ViewBuilder
    private var targetControls: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                switch model.mode {
                case .fullDisplay:
                    displayPicker(title: "녹화할 화면")

                case .window:
                    HStack(spacing: 10) {
                        Picker("녹화할 창", selection: $model.selectedWindowID) {
                            if model.windows.isEmpty {
                                Text("선택 가능한 창 없음").tag(CGWindowID?.none)
                            } else {
                                ForEach(model.windows) { window in
                                    Text(window.displayTitle).tag(Optional(window.id))
                                }
                            }
                        }
                        .disabled(model.isRecording || model.windows.isEmpty)

                        Button {
                            Task { await model.refreshShareableContent() }
                        } label: {
                            Label("새로고침", systemImage: "arrow.clockwise")
                        }
                        .disabled(model.isRecording)
                    }

                case .region:
                    displayPicker(title: "기준 화면")

                    HStack(spacing: 10) {
                        Button {
                            model.selectRegion()
                        } label: {
                            Label("영역 지정", systemImage: "selection.pin.in.out")
                        }
                        .disabled(model.isRecording)

                        Text(model.selectedRegionText)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        } label: {
            Label("대상", systemImage: model.mode.symbolName)
        }
    }

    private func displayPicker(title: String) -> some View {
        HStack(spacing: 10) {
            Picker(title, selection: $model.selectedDisplayID) {
                if model.displays.isEmpty {
                    Text("선택 가능한 화면 없음").tag(CGDirectDisplayID?.none)
                } else {
                    ForEach(model.displays) { display in
                        Text(display.title).tag(Optional(display.id))
                    }
                }
            }
            .disabled(model.isRecording || model.displays.isEmpty)

            Button {
                Task { await model.refreshShareableContent() }
            } label: {
                Label("새로고침", systemImage: "arrow.clockwise")
            }
            .disabled(model.isRecording)
        }
    }

    private var recordingSettings: some View {
        GroupBox {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                if model.recordingFormat == .mp4 {
                    GridRow {
                        Label("비디오 비트레이트", systemImage: "speedometer")
                        HStack(spacing: 8) {
                            TextField("2200", text: $model.bitrateText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 96)
                                .multilineTextAlignment(.trailing)
                                .disabled(model.isRecording)
                            Text("kbps")
                                .foregroundStyle(.secondary)
                        }
                    }

                    GridRow {
                        Label("동영상 프레임", systemImage: "rectangle.stack.badge.play")
                        Picker("동영상 프레임", selection: $model.videoFrameRate) {
                            Text("20 fps").tag(20)
                            Text("30 fps").tag(30)
                            Text("60 fps").tag(60)
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 150, alignment: .leading)
                        .disabled(model.isRecording)
                    }

                    GridRow {
                        Label("오디오 녹음", systemImage: "waveform")
                        HStack(spacing: 10) {
                            Toggle("", isOn: $model.includeAudio)
                                .labelsHidden()
                                .disabled(model.isRecording)
                            Text(model.includeAudio ? "ON" : "OFF")
                                .font(.system(.body, design: .monospaced).weight(.semibold))
                                .foregroundStyle(model.includeAudio ? .green : .secondary)
                        }
                    }

                    if model.includeAudio {
                        GridRow {
                            Label("오디오 음질", systemImage: "speaker.wave.2")
                            HStack(spacing: 8) {
                                TextField("64", text: $model.audioBitrateText)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 96)
                                    .multilineTextAlignment(.trailing)
                                    .disabled(model.isRecording)
                                Text("kbps")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    GridRow {
                        Label("GIF 프레임", systemImage: "rectangle.stack")
                        HStack(spacing: 8) {
                            TextField("20", text: $model.gifFrameRateText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 96)
                                .multilineTextAlignment(.trailing)
                                .disabled(model.isRecording)
                            Text("fps")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if model.lastGIFURL != nil {
                        GridRow {
                            Label("GIF 편집", systemImage: "slider.horizontal.3")
                            Button {
                                model.openGIFEditor()
                            } label: {
                                Label("편집 열기", systemImage: "crop")
                            }
                            .disabled(model.isRecording)
                        }
                    }
                }

                GridRow {
                    Label("저장 폴더", systemImage: "folder")
                    HStack(spacing: 8) {
                        Text(model.saveDirectory.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 8)

                        Button {
                            model.chooseSaveDirectory()
                        } label: {
                            Label("변경", systemImage: "folder.badge.gearshape")
                        }
                        .disabled(model.isRecording)

                        Button {
                            model.resetSaveDirectoryToDownloads()
                        } label: {
                            Label("다운로드", systemImage: "arrow.counterclockwise")
                        }
                        .disabled(model.isRecording)
                    }
                }
            }
        } label: {
            Label("설정", systemImage: "slider.horizontal.3")
        }
    }

    private var statusArea: some View {
        HStack(spacing: 10) {
            Image(systemName: model.isRecording ? "record.circle.fill" : "info.circle")
                .foregroundStyle(model.isRecording ? .red : .secondary)
            Text(model.statusMessage)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()

            if model.lastGIFURL != nil {
                Button {
                    model.openGIFEditor()
                } label: {
                    Label("GIF 편집", systemImage: "crop")
                }
                .disabled(model.isRecording)
            }

            if model.lastOutputURL != nil {
                Button {
                    model.revealLastRecording()
                } label: {
                    Label("파일 보기", systemImage: "magnifyingglass")
                }
            }
        }
        .font(.callout)
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button {
                model.openSaveDirectory()
            } label: {
                Label("저장 폴더 열기", systemImage: "folder")
            }

            Spacer()

            Button {
                model.toggleRecording()
            } label: {
                Label(
                    model.isRecording ? "녹화 중지" : "\(model.recordingFormat.title) 녹화 시작",
                    systemImage: model.isRecording ? "stop.fill" : "record.circle"
                )
                .frame(minWidth: 128)
            }
            .buttonStyle(.borderedProminent)
            .tint(model.isRecording ? .red : .accentColor)
            .controlSize(.large)
        }
    }
}

private struct GIFEditorSheet: View {
    @EnvironmentObject private var model: RecorderModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("GIF 편집", systemImage: "crop")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
            }

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    Label("가로", systemImage: "arrow.left.and.right")
                    HStack(spacing: 8) {
                        TextField("Width", text: $model.gifEditWidthText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                            .multilineTextAlignment(.trailing)
                        Text("px")
                            .foregroundStyle(.secondary)
                    }
                }

                GridRow {
                    Label("세로", systemImage: "arrow.up.and.down")
                    HStack(spacing: 8) {
                        TextField("Height", text: $model.gifEditHeightText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                            .multilineTextAlignment(.trailing)
                        Text("px")
                            .foregroundStyle(.secondary)
                    }
                }

                GridRow {
                    Label("화질", systemImage: "dial.medium")
                    HStack(spacing: 8) {
                        TextField("80", text: $model.gifQualityText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                            .multilineTextAlignment(.trailing)
                        Text("%")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                Spacer()
                Button {
                    model.applyGIFEdit()
                } label: {
                    if model.isEditingGIF {
                        Label("저장 중", systemImage: "hourglass")
                    } else {
                        Label("편집본 저장", systemImage: "square.and.arrow.down")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isEditingGIF)
            }
        }
        .padding(20)
    }
}
