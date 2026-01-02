import SwiftUI

struct HistoryView: View {
    @StateObject private var vm = HistoryViewModel()

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        Group {
            if vm.items.isEmpty && !vm.isLoading {
                ContentUnavailableView("No history yet", systemImage: "clock", description: Text("Your recent predictions will appear here."))
            } else {
                List {
                    ForEach(vm.items) { item in
                        HStack(alignment: .top, spacing: 12) {
                            thumbnailView(item)
                                .frame(width: 72, height: 72)
                                .background(Color.secondary.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            VStack(alignment: .leading, spacing: 6) {
                                Text(dateFormatter.string(from: item.createdAt))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                if item.isUnknown {
                                    Text("Not sure")
                                        .font(.headline)
                                        .foregroundStyle(.yellow)
                                } else if let top1 = item.top3.first {
                                    Text(top1.label)
                                        .font(.headline)
                                    HStack(spacing: 8) {
                                        ForEach(item.top3.prefix(3)) { p in
                                            Text("\(p.label) \(Int(p.confidence * 100))%")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 3)
                                                .background(Color.secondary.opacity(0.1))
                                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                        }
                                    }
                                }

                                if let fb = item.feedback {
                                    HStack(spacing: 6) {
                                        Image(systemName: fb.is_correct ? "checkmark.seal.fill" : "xmark.seal.fill")
                                            .foregroundStyle(fb.is_correct ? .green : .red)
                                        if let lbl = fb.selected_label {
                                            Text(lbl)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 6)
                        .onAppear {
                            Task { await vm.loadMoreIfNeeded(currentItem: item) }
                        }
                    }

                    if vm.isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("History")
        .task {
            await vm.refresh()
        }
    }

    @ViewBuilder
    private func thumbnailView(_ item: MergedHistoryItem) -> some View {
        if let image = item.thumbnail {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Color.gray.opacity(0.2)
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

