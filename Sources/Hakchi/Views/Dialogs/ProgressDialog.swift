import SwiftUI

struct ProgressDialog: View {
    let title: String
    let progress: Double
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.headline)

            ProgressView(value: progress) {
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .progressViewStyle(.linear)

            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            if progress >= 1.0 {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title)
            }
        }
        .padding(24)
        .frame(width: 350)
    }
}
