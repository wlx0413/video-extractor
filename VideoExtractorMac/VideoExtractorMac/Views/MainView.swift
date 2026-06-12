import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case downloads
    case history
    case settings
    case logs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .downloads:
            return "下载"
        case .history:
            return "历史"
        case .settings:
            return "设置"
        case .logs:
            return "日志"
        }
    }

    var symbol: String {
        switch self {
        case .downloads:
            return "arrow.down.circle"
        case .history:
            return "clock.arrow.circlepath"
        case .settings:
            return "gearshape"
        case .logs:
            return "doc.text.magnifyingglass"
        }
    }
}

struct MainView: View {
    @EnvironmentObject private var settingsViewModel: SettingsViewModel
    @StateObject private var viewModel = MainViewModel()
    @State private var selectedSection: AppSection? = .downloads

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selectedSection) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
            }
            .navigationTitle("视频提取器")
        } detail: {
            switch selectedSection ?? .downloads {
            case .downloads:
                downloadsView
            case .history:
                HistoryView()
            case .settings:
                SettingsView(viewModel: settingsViewModel)
            case .logs:
                LogView()
            }
        }
    }

    private var downloadsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                URLInputView(viewModel: viewModel)
                DownloadDestinationCard(settingsViewModel: settingsViewModel)
                FormatSelectionView(viewModel: viewModel)
                DownloadQueueView(viewModel: viewModel)
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("提示", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if $0 == false { viewModel.errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "arrow.down.app.fill")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 4) {
                Text("Media Extractor")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("3.0 内置下载核心。粘贴 YouTube 链接可选择单语、双语或三语外挂字幕。")
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

private struct DownloadDestinationCard: View {
    @ObservedObject var settingsViewModel: SettingsViewModel

    var body: some View {
        VECard {
            HStack(spacing: 12) {
                Label("保存位置", systemImage: "folder")
                    .font(.headline)

                Text(settingsViewModel.settings.defaultDownloadDirectoryPath)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    settingsViewModel.chooseDownloadDirectory()
                } label: {
                    Label("更改", systemImage: "folder.badge.gearshape")
                }
            }
        }
    }
}

struct VECard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
            )
    }
}

struct StatusBadge: View {
    var status: DownloadStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch status {
        case .waiting, .ready:
            return .secondary
        case .analyzing, .downloading, .converting:
            return .blue
        case .paused:
            return .orange
        case .completed:
            return .green
        case .failed:
            return .red
        case .cancelled:
            return .orange
        }
    }
}

struct EmptyStateView: View {
    var title: String
    var systemImage: String
    var description: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
    }
}
