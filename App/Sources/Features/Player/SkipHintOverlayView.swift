import AniLibertyKit
import UIKit

/// Skip hint built in UIKit, placed in `AVPlayerViewController.contentOverlayView`.
///
/// It is deliberately not SwiftUI: a `UIHostingController` inside the content overlay never gave the focus
/// engine a real focus item here. A single `UIButton` is an ordinary focus item, so the hint can hold focus
/// and Select presses it — which is the whole point of showing it. There is one control only: the owner's
/// second control («Смотреть») was removed because the remote could not reach it.
final class SkipHintOverlayView: UIView {
    private let stack = UIStackView()
    let skipButton = UIButton(type: .system)

    var onSkip: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// Applies what the hint should offer.
    ///
    /// - Parameters:
    ///   - title: Text of the single control.
    ///   - isProminent: Whether the action is the recommended one («Следующая серия»).
    func configure(title: String, isProminent: Bool) {
        skipButton.configuration = isProminent ? .prominentGlass() : .glass()
        apply(title: title)
    }

    private func apply(title: String) {
        guard var configuration = skipButton.configuration else { return }
        var attributes = AttributeContainer()
        attributes.font = UIFont.systemFont(ofSize: 21, weight: .semibold)
        configuration.attributedTitle = AttributedString(title, attributes: attributes)
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 8, bottom: 10, trailing: 8)
        skipButton.configuration = configuration
    }

    private func setUp() {
        stack.axis = .horizontal
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        skipButton.accessibilityIdentifier = "player.skipButton"
        skipButton.addTarget(self, action: #selector(skipTapped), for: .primaryActionTriggered)
        stack.addArrangedSubview(skipButton)

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
}
