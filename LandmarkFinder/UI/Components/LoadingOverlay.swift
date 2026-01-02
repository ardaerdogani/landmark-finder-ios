import SwiftUI

struct LoadingOverlay: View {
    var text: String = "Recognizing..."

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(.circular)
            Text(text)
                .font(.headline)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(radius: 10)
    }
}
