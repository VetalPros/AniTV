import AniLibertyKit
import UIKit

/// Skip hint built in UIKit, placed in `AVPlayerViewController.contentOverlayView`.
///
/// It is deliberately not SwiftUI: a `UIHostingController` inside the content overlay does not give the
/// focus engine a container that traverses between siblings, so only the first button ever answered
/// `hasFocus`. Two `UIButton`s in a `UIStackView` are ordinary focus items, and Left/Right moves between
/// them the way the remote expects.
final class SkipHintOverlayView: UIView {
    private let stack = UIStackView()
    let skipButton = UIButton(type: .system)
    let dismissButton = UIButton(type: .system)

    var onSkip: (() -> Void)?
    var onDismiss: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// No `preferredFocusEnvironments` here on purpose: returning the skip button on every focus update pulled
    /// the focus back to it the moment Left/Right moved to the second control, so «Смотреть» could never keep
    /// focus. The initial focus is granted once by the player controller instead.
    /// Applies what the hint should offer.
    ///
    /// - Parameters:
    ///   - primary: Title of the leading control.
    ///   - primaryIsProminent: Whether the leading control is the recommended action.
    ///   - dismiss: Title of the control that only waves the hint away.
    func configure(primary: String, primaryIsProminent: Bool, dismiss: String) {
        skipButton.configuration = primaryIsProminent ? .prominentGlass() : .glass()
        dismissButton.configuration = .glass()
        apply(title: primary, to: skipButton)
        apply(title: dismiss, to: dismissButton)
    }

    private func apply(title: String, to button: UIButton) {
        var configuration = button.configuration ?? .glass()
        var attributes = AttributeContainer()
        attributes.font = UIFont.systemFont(ofSize: 21, weight: .semibold)
        configuration.attributedTitle = AttributedString(title, attributes: attributes)
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 8, bottom: 10, trailing: 8)
        button.configuration = configuration
    }

    private func setUp() {
        stack.axis = .horizontal
        stack.spacing = 14
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        skipButton.accessibilityIdentifier = "player.skipButton"
        dismissButton.accessibilityIdentifier = "player.skipDismissButton"
        skipButton.addTarget(self, action: #selector(skipTapped), for: .primaryActionTriggered)
        dismissButton.addTarget(self, action: #selector(dismissTapped), for: .primaryActionTriggered)
        stack.addArrangedSubview(skipButton)
        stack.addArrangedSubview(dismissButton)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @objc private func skipTapped() {
        onSkip?()
    }

    @objc private func dismissTapped() {
        onDismiss?()
    }
}
