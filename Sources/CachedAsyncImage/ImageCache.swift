//
//  ImageCache.swift
//  CachedAsyncImage
//
//  Created by Jonathan Rajya on 17/04/2026.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
public typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
public typealias PlatformImage = NSImage
#endif

/// Configuration options for `ImageCache` and `CachedAsyncImage`.
public struct CacheConfiguration: Sendable {
    /// Maximum memory for decoded images in megabytes, or `nil` for unlimited.
    public var imageCostLimit: Int?

    /// Maximum memory for compressed image data in megabytes, or `nil` for unlimited.
    public var dataCostLimit: Int?

    /// When `true`, thumbnail loads also decode and cache the full-resolution
    /// image in the background.
    public var prefetchesFullResolution: Bool

    public init(
        imageCostLimit: Int? = nil,
        dataCostLimit: Int? = nil,
        prefetchesFullResolution: Bool = false
    ) {
        self.imageCostLimit = imageCostLimit
        self.dataCostLimit = dataCostLimit
        self.prefetchesFullResolution = prefetchesFullResolution
    }
}

public final class ImageCache: @unchecked Sendable {
    public static let shared = ImageCache()
    nonisolated(unsafe) private let imageCache = NSCache<NSString, PlatformImage>()
    nonisolated(unsafe) private let dataCache = NSCache<NSURL, NSData>()
    nonisolated(unsafe) public private(set) var configuration = CacheConfiguration()

    private init() {}

    /// Applies the given configuration to the cache.
    public nonisolated func configure(with configuration: CacheConfiguration) {
        self.configuration = configuration
        let bytesPerMB = 1024 * 1024
        imageCache.totalCostLimit = (configuration.imageCostLimit ?? 0) * bytesPerMB
        dataCache.totalCostLimit = (configuration.dataCostLimit ?? 0) * bytesPerMB
    }

    public static func key(for url: URL, size: CGSize?) -> NSString {
        guard let size else { return url.absoluteString as NSString }
        return "\(url.absoluteString)_\(Int(size.width))x\(Int(size.height))" as NSString
    }

    public nonisolated subscript(_ key: NSString) -> PlatformImage? {
        get { imageCache.object(forKey: key) }
        set {
            if let newValue {
                if configuration.imageCostLimit != nil {
                    #if canImport(UIKit)
                    let bytes = newValue.cgImage.map { $0.height * $0.bytesPerRow } ?? 0
                    #elseif canImport(AppKit)
                    let cgImage = newValue.cgImage(forProposedRect: nil, context: nil, hints: nil)
                    let bytes = cgImage.map { $0.height * $0.bytesPerRow } ?? 0
                    #endif
                    imageCache.setObject(newValue, forKey: key, cost: bytes)
                } else {
                    imageCache.setObject(newValue, forKey: key)
                }
            }
        }
    }

    public nonisolated func data(for url: URL) -> Data? {
        dataCache.object(forKey: url as NSURL) as? Data
    }

    public nonisolated func store(data: Data, for url: URL) {
        dataCache.setObject(data as NSData, forKey: url as NSURL)
    }
}
