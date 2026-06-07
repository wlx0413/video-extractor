import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("设置")
                    .font(.largeTitle.bold())

                VECard {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("下载偏好", systemImage: "folder")
                            .font(.headline)

                        pathRow(
                            title: "默认保存路径",
                            path: $viewModel.settings.defaultDownloadDirectoryPath,
                            action: viewModel.chooseDownloadDirectory
                        )

                        Picker("默认视频质量", selection: $viewModel.settings.defaultVideoQuality) {
                            ForEach(VideoQuality.allCases) { quality in
                                Text(quality.displayName).tag(quality)
                            }
                        }

                        Picker("默认音频格式", selection: $viewModel.settings.defaultAudioFormat) {
                            ForEach(AudioOutputFormat.allCases) { format in
                                Text(format.displayName).tag(format)
                            }
                        }
                        .pickerStyle(.segmented)

                        Toggle("下载完成后自动打开文件夹", isOn: $viewModel.settings.shouldOpenFolderWhenFinished)
                    }
                }

                VECard {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("显示外观", systemImage: "circle.lefthalf.filled")
                            .font(.headline)

                        Picker("外观模式", selection: $viewModel.settings.appearanceMode) {
                            ForEach(AppearanceMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                VECard {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("命令行工具", systemImage: "terminal")
                            .font(.headline)

                        toolSection(
                            name: "yt-dlp",
                            mode: $viewModel.settings.ytdlpPathMode,
                            path: $viewModel.settings.customYTDLPPath,
                            version: viewModel.ytdlpVersion,
                            chooseAction: viewModel.chooseYTDLPPath
                        )

                        Divider()

                        toolSection(
                            name: "FFmpeg",
                            mode: $viewModel.settings.ffmpegPathMode,
                            path: $viewModel.settings.customFFmpegPath,
                            version: viewModel.ffmpegVersion,
                            chooseAction: viewModel.chooseFFmpegPath
                        )

                        HStack {
                            Button {
                                viewModel.checkTools()
                            } label: {
                                Label("检查工具", systemImage: "checkmark.seal")
                            }
                            .buttonStyle(.borderedProminent)

                            if let error = viewModel.toolCheckError {
                                Label(error, systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }

                            Spacer()
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            viewModel.checkTools()
        }
    }

    private func pathRow(title: String, path: Binding<String>, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .frame(width: 112, alignment: .leading)
                .foregroundStyle(.secondary)
            TextField(title, text: path)
                .textFieldStyle(.roundedBorder)
            Button(action: action) {
                Image(systemName: "folder")
            }
            .help("选择路径")
        }
    }

    private func toolSection(
        name: String,
        mode: Binding<ToolPathMode>,
        path: Binding<String>,
        version: String,
        chooseAction: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 80, alignment: .leading)

                Picker(name, selection: mode) {
                    ForEach(ToolPathMode.allCases) { item in
                        Text(item.displayName).tag(item)
                    }
                }
                .labelsHidden()
                .frame(width: 180)

                Text(version)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()
            }

            if mode.wrappedValue == .custom {
                pathRow(title: "工具路径", path: path, action: chooseAction)
            }
        }
    }
}
