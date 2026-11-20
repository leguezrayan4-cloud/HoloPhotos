import Photos
import SwiftUI

struct ThumbnailView: View {
    let asset: PHAsset
    var isSelecting = false
    var isSelected = false
    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.gray.opacity(0.2)
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .overlay(alignment: .bottomLeading) {
                videoBadge
            }
            .overlay(alignment: .bottomTrailing) {
                badge
            }
            .opacity(isSelecting && isSelected ? 0.7 : 1)
            .onAppear(perform: load)
    }

    @ViewBuilder
    private var videoBadge: some View {
        if asset.mediaType == .video {
            Text(durationText)
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .shadow(radius: 2)
                .padding(4)
        }
    }

    private var durationText: String {
        let total = Int(asset.duration)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    @ViewBuilder
    private var badge: some View {
        if isSelecting {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Color.blue : Color.white)
                .shadow(radius: 2)
                .padding(6)
        } else if asset.isFavorite {
            Image(systemName: "heart.fill")
                .foregroundStyle(.white)
                .shadow(radius: 2)
                .padding(6)
        }
    }

    private func load() {
        guard image == nil else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 220, height: 220),
            contentMode: .aspectFill,
            options: options
        ) { result, _ in
            if let result {
                image = result
            }
        }
    }
}
