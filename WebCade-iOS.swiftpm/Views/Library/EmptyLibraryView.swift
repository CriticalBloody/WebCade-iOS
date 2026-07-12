import SwiftUI

struct EmptyLibraryView: View {
    @Binding var showingAddSheet: Bool
    @State private var isPulsing = false

    var body: some View {
        VStack(spacing: 36) {
            ZStack {
                Circle()
                    .fill(.blue.opacity(0.08))
                    .frame(width: 180, height: 180)
                    .scaleEffect(isPulsing ? 1.12 : 1.0)
                    .animation(
                        .easeInOut(duration: 2.2).repeatForever(autoreverses: true),
                        value: isPulsing
                    )
                Circle()
                    .fill(.blue.opacity(0.14))
                    .frame(width: 136, height: 136)
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 58))
                    .foregroundStyle(.blue.gradient)
            }

            VStack(spacing: 10) {
                Text(String(localized: "Noch keine Spiele"))
                    .font(.title2.bold())
                Text(String(localized: "Tippe auf + und öffne eine Spielseite auf\nitch.io, um dein erstes Spiel hinzuzufügen."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                showingAddSheet = true
            } label: {
                Label(String(localized: "Spiel hinzufügen"), systemImage: "plus.circle.fill")
                    .font(.headline)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(.blue)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { isPulsing = true }
    }
}
