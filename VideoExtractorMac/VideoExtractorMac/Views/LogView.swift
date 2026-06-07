import SwiftUI

struct LogView: View {
    @StateObject private var viewModel = LogViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("日志")
                    .font(.largeTitle.bold())
                Spacer()
                Button {
                    viewModel.refresh()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }

            VECard {
                ScrollView {
                    Text(viewModel.lines.joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 520)
            }
        }
        .padding(24)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            viewModel.refresh()
        }
    }
}
