import SwiftUI

/// Toast notification component.
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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(toast.level.color.opacity(0.3), lineWidth: 1)
        )
        .frame(maxWidth: 400)
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }
}
