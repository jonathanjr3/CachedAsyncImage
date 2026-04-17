# CachedAsyncImage

A drop-in replacement for SwiftUI's `AsyncImage` that caches downloaded images in memory.

## Features

- **In-memory caching** of both decoded images and compressed data
- **Thumbnail downsampling** via ImageIO for memory-efficient lists
- **Optional full-resolution prefetching** for cases where the full res image is required in a detail view
- **Configurable cost limits** to cap memory usage
- **Multiplatform** — iOS 15+, macOS 14+, tvOS 15+, watchOS 8+, visionOS 1+

## Installation

Add the package to your project via Swift Package Manager:

```swift
.package(url: "https://github.com/jonathanjr3/CachedAsyncImage.git", from: "1.0.0")
```

## Usage

### Basic

Works exactly like `AsyncImage`:

```swift
CachedAsyncImage(url: imageURL) { phase in
    switch phase {
    case .success(let image):
        image.resizable().scaledToFill()
    case .failure:
        Image(systemName: "photo")
    default:
        ProgressView()
    }
}
```

### Content + Placeholder

A convenience initializer mirrors the `AsyncImage` content/placeholder pattern:

```swift
CachedAsyncImage(url: imageURL) { image in
    image.resizable().scaledToFill()
} placeholder: {
    ProgressView()
}
```

### Thumbnails

Pass a `thumbnailSize` to downsample large images efficiently using ImageIO:

```swift
CachedAsyncImage(url: imageURL, thumbnailSize: CGSize(width: 80, height: 80)) { phase in
    if let image = phase.image {
        image.resizable().scaledToFill()
    }
}
```

### Configuration

Configure the shared cache at app launch:

```swift
ImageCache.shared.configure(with: CacheConfiguration(
    imageCostLimit: 600,           // 600 MB for decoded images
    dataCostLimit: 80,             // 80 MB for compressed data
    prefetchesFullResolution: true // Warm full-res cache in background
))
```

| Option | Default | Description |
|---|---|---|
| `imageCostLimit` | `nil` (unlimited) | Max memory for decoded images in MB |
| `dataCostLimit` | `nil` (unlimited) | Max memory for compressed data in MB |
| `prefetchesFullResolution` | `false` | Pre-decode full-res images when loading thumbnails |
