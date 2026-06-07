import SwiftUI

struct URLInputView: View {
    @ObservedObject var viewModel: MainViewModel

    var body: some View {
        VECard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("视频链接", systemImage: "link")
                        .font(.headline)

                    Spacer()

                    Button {
                        Task {
                            await viewModel.analyzeLinks()
                        }
                    } label: {
                        Label(viewModel.isAnalyzing ? "分析中" : "分析链接", systemImage: "magnifyingglass")
                    }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(viewModel.isAnalyzing)
                }

                TextEditor(text: $viewModel.urlText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 96)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(alignment: .topLeading) {
                        if viewModel.urlText.isEmpty {
                            Text("每行一个链接，例如 https://www.youtube.com/watch?v=...")
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 18)
                                .allowsHitTesting(false)
                        }
                    }
            }
        }
    }
}
