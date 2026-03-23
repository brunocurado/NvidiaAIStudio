import SwiftUI

struct ToastView: View {
    let toast: ToastMessage

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.level.icon)
                .foregroundStyle(toast.level.color)
            Text(toast.message)
                .font(.caption)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular.tint(toast.level.color.opacity(0.15)), in: RoundedRectangle(cornerRadius: 10))
        .frame(maxWidth: 400)
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }
}
