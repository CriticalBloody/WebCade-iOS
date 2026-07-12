import SwiftUI

struct GameCardView: View {
    let game: WebGame
    
    var body: some View {
        VStack(alignment: .leading) {
            
            RoundedRectangle(cornerRadius: 16)
                .fill(game.coverColor.gradient)
                .overlay {
                    if let urlString = game.coverImageUrl, let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            case .failure:
                                Image(systemName: "photo.badge.exclamationmark")
                                    .font(.title2)
                                    .foregroundStyle(.white.opacity(0.5))
                            case .empty:
                                ProgressView()
                                    .tint(.white.opacity(0.6))
                            @unknown default:
                                EmptyView()
                            }
                        }
                    }
                }
                .frame(height: 140) // Feste Kachelhöhe
                .clipShape(RoundedRectangle(cornerRadius: 16)) // Schneidet ab, was übersteht
                
                .overlay(alignment: .topTrailing) {
                    Image(systemName: game.isDownloaded ? "checkmark.circle.fill" : "icloud.and.arrow.down")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(game.isDownloaded ? .green : .white)
                        .shadow(color: .black.opacity(0.8), radius: 4, x: 0, y: 2) // Schatten für perfekten Kontrast
                        .padding(10)
                }
                // ----------------------------------------------------
                
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
            
            Text(game.title)
                .font(.headline)
                .lineLimit(1)
                .padding(.top, 4)
                .padding(.horizontal, 4)
            
            Text(game.developer)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 4)
        }
    }
}
