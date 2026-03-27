import SwiftUI

struct StorageBar: View {
    let used: Int64
    let total: Int64

    private var usagePercent: Double {
        guard total > 0 else { return 0 }
        return Double(used) / Double(total)
    }

    private var free: Int64 {
        max(0, total - used)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.secondary.opacity(0.2))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(barColor)
                        .frame(width: geometry.size.width * usagePercent, height: 8)
                }
            }
            .frame(height: 8)

            HStack {
                Text("\(formatSize(used)) used")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(formatSize(free)) free")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var barColor: Color {
        if usagePercent > 0.9 {
            return .red
        } else if usagePercent > 0.7 {
            return .orange
        }
        return .accentColor
    }

    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
