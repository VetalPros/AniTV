import AniLibertyKit
import AVFoundation

/// Builds the `externalMetadata` the system transport bar and the TV app use to describe a stream.
enum PlayerMetadata {
    /// Title = release, subtitle = episode, description = quality of the selected stream.
    ///
    /// Artwork is intentionally omitted: loading it would turn the player's appearance into an
    /// asynchronous operation, and the system falls back to the app icon.
    static func items(for request: PlaybackRequest) -> [AVMetadataItem] {
        [
            item(
                identifier: .commonIdentifierTitle,
                value: request.releaseTitle
            ),
            item(
                identifier: .iTunesMetadataTrackSubTitle,
                value: request.episodeTitle
            ),
            item(
                identifier: .commonIdentifierDescription,
                value: "\(request.source.quality.rawValue)p · HLS"
            ),
        ]
    }

    private static func item(identifier: AVMetadataIdentifier, value: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as NSString
        item.extendedLanguageTag = "ru"
        return item
    }
}
