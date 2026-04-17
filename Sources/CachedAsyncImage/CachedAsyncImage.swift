import SwiftUI

/// A drop-in replacement for `AsyncImage` that caches downloaded images in memory.
public struct CachedAsyncImage<Content: View>: View {
    private let url: URL?
    private let content: (AsyncImagePhase) -> Content
    private let thumbnailSize: CGSize?
    @Environment(\.displayScale) private var displayScale
    @State private var phase: AsyncImagePhase = .empty

    public init(url: URL?, thumbnailSize: CGSize? = nil, @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.url = url
        self.thumbnailSize = thumbnailSize
        self.content = content
    }

    public var body: some View {
        content(phase)
            .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else { phase = .empty; return }

        let key = ImageCache.key(for: url, size: thumbnailSize)

        if let cached = ImageCache.shared[key] {
            phase = .success(Image(platformImage: cached))
            return
        }

        do {
            let data: Data
            if let cached = ImageCache.shared.data(for: url) {
                data = cached
            } else {
                let (downloaded, _) = try await URLSession.shared.data(from: url)
                ImageCache.shared.store(data: downloaded, for: url)
                data = downloaded
            }

            let thumbnailSize = self.thumbnailSize
            let displayScale = self.displayScale

            let decodeTask = Task.detached(priority: .userInitiated) { () -> (PlatformImage?, Bool) in
                if let size = thumbnailSize,
                   let downsampled = downsampleImage(data: data, to: size, scale: displayScale) {
                    return (downsampled, true)
                }
                return (PlatformImage(data: data), false)
            }
            let (loadedImage, alreadyDecoded) = await decodeTask.value

            guard let loadedImage else { throw URLError(.badServerResponse) }

            #if os(iOS) || os(tvOS) || os(visionOS)
            let prepared = alreadyDecoded ? loadedImage : (await loadedImage.byPreparingForDisplay() ?? loadedImage)
            #else
            let prepared = loadedImage
            #endif
            ImageCache.shared[key] = prepared
            phase = .success(Image(platformImage: prepared))

            // Warm full-res cache in background.
            if thumbnailSize != nil, ImageCache.shared.configuration.prefetchesFullResolution {
                let fullResKey = ImageCache.key(for: url, size: nil)
                if ImageCache.shared[fullResKey] == nil {
                    let cache = ImageCache.shared
                    Task.detached(priority: .background) {
                        guard let image = PlatformImage(data: data) else { return }
                        #if os(iOS) || os(tvOS) || os(visionOS)
                        let prepared = await image.byPreparingForDisplay() ?? image
                        #else
                        let prepared = image
                        #endif
                        cache[fullResKey] = prepared
                    }
                }
            }
        } catch {
            phase = .failure(error)
        }
    }

}

// MARK: - Image Downsampling

/// Decodes and downsamples image data to the target size using ImageIO.
/// This is a file-scope function so it carries no actor isolation and can
/// run entirely on whatever thread the caller provides (e.g. a detached task).
private func downsampleImage(data: Data, to size: CGSize, scale: CGFloat) -> PlatformImage? {
    let options = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return nil }

    let maxDimension = max(size.width, size.height) * scale
    let thumbOptions: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxDimension
    ]
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else { return nil }
    #if canImport(UIKit)
    return UIImage(cgImage: cgImage)
    #elseif canImport(AppKit)
    return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    #endif
}

// MARK: - Platform Image Helper

extension Image {
    init(platformImage: PlatformImage) {
        #if canImport(UIKit)
        self.init(uiImage: platformImage)
        #elseif canImport(AppKit)
        self.init(nsImage: platformImage)
        #endif
    }
}

// MARK: - Content + Placeholder convenience initialiser

/// Wraps the content and placeholder closures so the content+placeholder
/// init can be expressed without type-erasing to AnyView.
public struct CachedImageContentView<I: View, P: View>: View {
    let phase: AsyncImagePhase
    let content: (Image) -> I
    let placeholder: () -> P

    public var body: some View {
        if let image = phase.image {
            content(image)
        } else {
            placeholder()
        }
    }
}

extension CachedAsyncImage {
    public init<I: View, P: View>(
        url: URL?,
        thumbnailSize: CGSize? = nil,
        @ViewBuilder content: @escaping (Image) -> I,
        @ViewBuilder placeholder: @escaping () -> P
    ) where Content == CachedImageContentView<I, P> {
        self.url = url
        self.thumbnailSize = thumbnailSize
        self.content = { phase in
            CachedImageContentView(phase: phase, content: content, placeholder: placeholder)
        }
    }
}
