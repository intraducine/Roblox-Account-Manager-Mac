import AppKit
import SwiftUI

struct AccountAvatarView: View {
    let url: URL?
    let size: CGFloat
    let cornerRadius: CGFloat
    @State private var image: NSImage?
    @State private var loadedURL: URL?

    init(url: URL?, size: CGFloat, cornerRadius: CGFloat) {
        self.url = url
        self.size = size
        self.cornerRadius = cornerRadius
        let cachedImage = RemoteImageCache.image(for: url)
        _image = State(initialValue: cachedImage)
        _loadedURL = State(initialValue: cachedImage == nil ? nil : url)
    }

    var body: some View {
        Group {
            if let displayedImage {
                Image(nsImage: displayedImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: size * 0.76))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: url) {
            image = RemoteImageCache.image(for: url)
            loadedURL = image == nil ? nil : url
            guard image == nil, let url else { return }
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let loadedImage = NSImage(data: data) else { return }
            RemoteImageCache.insert(loadedImage, for: url)
            guard self.url == url else { return }
            image = loadedImage
            loadedURL = url
        }
        .accessibilityHidden(true)
    }

    private var displayedImage: NSImage? {
        if loadedURL == url {
            return image
        }
        return RemoteImageCache.image(for: url)
    }
}
