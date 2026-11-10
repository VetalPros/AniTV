import AniLibertyKit
import os
import SwiftUI
import UIKit

/// Poster/thumbnail image that loads its bytes through the Kit's shared ``ImageCache``.
///
/// The cache owns memory + disk buffering and networking; this view only decodes and cross-fades.
/// Images are decorative here: the enclosing card carries the accessibility label.
struct RemoteImage: View {
    private enum Phase {
        case empty
        case loading
        case loaded(UIImage)
        case failed
    }

    private static let logger = Logger(subsystem: "tv.anitv.client", category: "RemoteImage")

    let url: URL?

    @State private var phase: Phase = .empty

    var body: some View {
        ZStack {
            Rectangle().fill(Palette.posterPlaceholder)
            switch phase {
            case .empty, .failed:
                Image(systemName: "photo")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.white.opacity(0.22))
            case .loading:
                ProgressView()
                    .controlSize(.regular)
                    .tint(.white.opacity(0.65))
            case let .loaded(image):
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            }
        }
        .clipped()
        .task(id: url) { await load() }
        .accessibilityHidden(true)
    }

    private func load() async {
        guard let url else {
            phase = .empty
            return
        }
        phase = .loading
        do {
            let data = try await ImageCache.shared.data(for: url)
            guard !Task.isCancelled else { return }
            guard let image = UIImage(data: data) else {
                Self.logger.error("Undecodable image payload from \(url.host() ?? "unknown-host", privacy: .public)")
                phase = .failed
                return
            }
            phase = .loaded(image)
        } catch {
            guard !Task.isCancelled else { return }
            Self.logger.debug("Image load failed: \(error.localizedDescription, privacy: .public)")
            phase = .failed
        }
    }
}
