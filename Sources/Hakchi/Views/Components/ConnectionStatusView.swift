import SwiftUI

struct ConnectionStatusView: View {
    let state: ConsoleState

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(state.displayName)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(statusColor.opacity(0.15))
        )
    }

    private var statusColor: Color {
        switch state {
        case .disconnected: return .red
        case .felMode: return .orange
        case .connected: return .green
        case .busy: return .yellow
        }
    }
}
