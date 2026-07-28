import SwiftUI

struct OrganizeProgressPanel: View {
    var phase: OrganizerViewModel.Phase
    var fileProgress: Double
    var filesDone: Int
    var filesTotal: Int
    var bytesDone: Int64
    var bytesTotal: Int64
    var currentFileName: String
    var instantMBps: Double
    var averageMBps: Double
    var etaText: String?

    private static let byteFmt: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    private var byteProgress: Double {
        guard bytesTotal > 0 else { return fileProgress }
        return min(1, max(0, Double(bytesDone) / Double(bytesTotal)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch phase {
            case .idle:
                EmptyView()
            case .scanning:
                ProgressView()
                Text("미디어를 찾고 있습니다…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            case .organizing, .done, .cancelled:
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: byteProgress, total: 1.0) {
                        Text("파일 \(filesDone) / \(filesTotal)")
                    }
                    .progressViewStyle(.linear)

                    if bytesTotal > 0 {
                        Text("\(Self.byteFmt.string(fromByteCount: bytesDone)) / \(Self.byteFmt.string(fromByteCount: bytesTotal))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    if !currentFileName.isEmpty {
                        Text(currentFileName)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        LabeledContent {
                            Text(String(format: "%.1f MB/s", instantMBps))
                                .font(.body.weight(.medium))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                        } label: {
                            Label("순간", systemImage: "bolt.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        LabeledContent {
                            Text(String(format: "%.1f MB/s", averageMBps))
                                .font(.body.weight(.medium))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                        } label: {
                            Label("평균", systemImage: "gauge.with.dots.needle.67percent")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let eta = etaText {
                            LabeledContent {
                                Text(eta)
                                    .font(.body.weight(.medium))
                                    .monospacedDigit()
                            } label: {
                                Label("남은 시간", systemImage: "clock")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .animation(.easeInOut(duration: 0.15), value: byteProgress)
        .animation(.easeInOut(duration: 0.2), value: instantMBps)
        .animation(.easeInOut(duration: 0.2), value: averageMBps)
    }
}
