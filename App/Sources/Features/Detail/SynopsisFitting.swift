import Foundation
import UIKit

/// Decides whether a synopsis is clipped when it is collapsed to a fixed number of lines.
///
/// The rule used to be a character count, which is wrong in both directions: a short text with many
/// wide characters grew a "read more" control it did not need, and a long text could fit in six lines
/// and still get one. Here the text is measured the way it will be drawn — same font, same width,
/// same line spacing — and only a text that really needs more lines than allowed offers the control.
///
/// The measurement works at any width, so it survives layout changes and any type size the body font
/// resolves to.
enum SynopsisFitting {
    /// Lines a collapsed synopsis may take.
    static let collapsedLines = 6
    /// Line spacing the synopsis is rendered with, mirrored by the view.
    static let lineSpacing: CGFloat = 5

    /// Body font of the synopsis. Mirrors `DesignTokens.Typography.body`, which is a fixed-size
    /// system font, so the measured text and the drawn text agree.
    private static let bodyFont = UIFont.systemFont(ofSize: 20)

    /// Whether `text` needs more than `lines` lines at `width`.
    ///
    /// - Parameters:
    ///   - text: Synopsis as it will be rendered.
    ///   - width: Width available to the text, in points. A non-positive width means "not laid out
    ///     yet" and is reported as fitting, so the screen does not flash a toggle before it can know.
    ///   - lines: Line budget of the collapsed state.
    static func isClipped(_ text: String, width: CGFloat, lines: Int = collapsedLines) -> Bool {
        guard width > 0, !text.isEmpty else { return false }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .paragraphStyle: paragraphStyle,
        ]
        let fullHeight = height(of: text, width: width, attributes: attributes)
        let singleLineHeight = height(of: "A", width: width, attributes: attributes)
        guard singleLineHeight > 0 else { return false }
        // n lines occupy n * lineHeight + (n - 1) * lineSpacing, with a point of slack for rounding.
        let allowedHeight = CGFloat(lines) * singleLineHeight + CGFloat(lines - 1) * lineSpacing
        return fullHeight > allowedHeight + 1
    }

    private static var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.lineBreakMode = .byWordWrapping
        return style
    }

    private static func height(of text: String, width: CGFloat, attributes: [NSAttributedString.Key: Any]) -> CGFloat {
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        return bounds.height
    }
}
