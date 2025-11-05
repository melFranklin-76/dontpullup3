import UIKit
import SwiftUI

/// UIKit-based implementation of the tutorial to bypass SwiftUI presentation issues
class TutorialViewController: UIViewController {
    
    // MARK: - Properties
    private var currentPage = 0
    private let tutorialPages = TutorialData.pages
    private var onDismiss: (() -> Void)?
    
    // MARK: - UI Elements
    private let backgroundView = UIView()
    private let contentView = UIView()
    private let emojiLabel = UILabel()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let pageIndicatorLabel = UILabel()
    
    // MARK: - Initialization
    init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        updateContent(forPage: currentPage)
        
        // Add tap gesture
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        view.addGestureRecognizer(tapGesture)
    }
    
    // MARK: - UI Setup
    private func setupViews() {
        // Background view (semi-transparent black)
        backgroundView.backgroundColor = UIColor.black.withAlphaComponent(0.9)
        backgroundView.frame = view.bounds
        backgroundView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(backgroundView)
        
        // Content container
        contentView.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        contentView.layer.cornerRadius = 15
        contentView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentView)
        
        // Emoji label
        emojiLabel.font = UIFont.systemFont(ofSize: 70)
        emojiLabel.textAlignment = .center
        emojiLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emojiLabel)
        
        // Title label
        titleLabel.font = UIFont.boldSystemFont(ofSize: 22)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)
        
        // Message label
        messageLabel.font = UIFont.systemFont(ofSize: 16)
        messageLabel.textColor = .white
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(messageLabel)
        
        // Page indicator
        pageIndicatorLabel.font = UIFont.systemFont(ofSize: 14)
        pageIndicatorLabel.textColor = .white
        pageIndicatorLabel.textAlignment = .center
        pageIndicatorLabel.backgroundColor = UIColor.gray.withAlphaComponent(0.6)
        pageIndicatorLabel.layer.cornerRadius = 8
        pageIndicatorLabel.clipsToBounds = true
        pageIndicatorLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pageIndicatorLabel)
        
        // Layout constraints
        let emojiCenterX = emojiLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        emojiCenterX.identifier = "emojiCenterX"
        emojiCenterX.priority = .defaultHigh
        
        let emojiTop = emojiLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 80)
        emojiTop.identifier = "emojiTop"
        emojiTop.priority = .defaultHigh
        
        let contentCenterX = contentView.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        contentCenterX.identifier = "contentViewCenterX"
        contentCenterX.priority = .defaultHigh
        
        let contentWidth = contentView.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.95)
        contentWidth.identifier = "contentViewWidth"
        contentWidth.priority = .defaultHigh
        
        let titleTop = titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20)
        titleTop.identifier = "titleTop"
        titleTop.priority = .defaultHigh
        
        let titleLeading = titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20)
        titleLeading.identifier = "titleLeading"
        titleLeading.priority = .defaultHigh
        
        let titleTrailing = titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20)
        titleTrailing.identifier = "titleTrailing"
        titleTrailing.priority = .defaultHigh
        
        let messageTop = messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16)
        messageTop.identifier = "messageTop"
        messageTop.priority = .defaultHigh
        
        let messageLeading = messageLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20)
        messageLeading.identifier = "messageLeading"
        messageLeading.priority = .defaultHigh
        
        let messageTrailing = messageLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20)
        messageTrailing.identifier = "messageTrailing"
        messageTrailing.priority = .defaultHigh
        
        let messageBottom = messageLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20)
        messageBottom.identifier = "messageBottom"
        messageBottom.priority = .defaultHigh
        
        let pageIndicatorCenterX = pageIndicatorLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        pageIndicatorCenterX.identifier = "pageIndicatorCenterX"
        pageIndicatorCenterX.priority = .defaultHigh
        
        let pageIndicatorBottom = pageIndicatorLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -40)
        pageIndicatorBottom.identifier = "pageIndicatorBottom"
        pageIndicatorBottom.priority = .defaultHigh
        
        let pageIndicatorHeight = pageIndicatorLabel.heightAnchor.constraint(equalToConstant: 36)
        pageIndicatorHeight.identifier = "pageIndicatorHeight"
        pageIndicatorHeight.priority = .defaultHigh
        
        NSLayoutConstraint.activate([
            emojiCenterX,
            emojiTop,
            contentCenterX,
            contentWidth,
            titleTop,
            titleLeading,
            titleTrailing,
            messageTop,
            messageLeading,
            messageTrailing,
            messageBottom,
            pageIndicatorCenterX,
            pageIndicatorBottom,
            pageIndicatorHeight
        ])
        
        // Add height constraint for contentView with low priority
        let minHeight = contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 150)
        minHeight.priority = .defaultLow
        minHeight.identifier = "contentViewMinHeight"
        minHeight.isActive = true
        
        // Center Y constraint for contentView
        let centerY = contentView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        centerY.identifier = "contentViewCenterY"
        centerY.priority = .defaultHigh
        centerY.isActive = true
        
        // Add low priority width constraint for pageIndicatorLabel
        let pageIndicatorMinWidth = pageIndicatorLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 150)
        pageIndicatorMinWidth.priority = .defaultLow
        pageIndicatorMinWidth.identifier = "pageIndicatorMinWidth"
        pageIndicatorMinWidth.isActive = true
    }
    
    // MARK: - Content Updates
    private func updateContent(forPage page: Int) {
        guard page < tutorialPages.count else { return }
        
        let tutorialPage = tutorialPages[page]
        emojiLabel.text = tutorialPage.emoji
        titleLabel.text = tutorialPage.title
        messageLabel.text = tutorialPage.message
        pageIndicatorLabel.text = "  Tap anywhere to continue (\(page + 1)/\(tutorialPages.count))  "
        
        // Simple animation
        UIView.animate(withDuration: 0.3) {
            self.contentView.alpha = 1.0
            self.emojiLabel.alpha = 1.0
        }
    }
    
    // MARK: - Actions
    @objc private func handleTap() {
        if currentPage < tutorialPages.count - 1 {
            // Fade out current content
            UIView.animate(withDuration: 0.2, animations: {
                self.contentView.alpha = 0.7
                self.emojiLabel.alpha = 0.7
            }) { _ in
                // Move to next page and fade in
                self.currentPage += 1
                self.updateContent(forPage: self.currentPage)
            }
        } else {
            // Last page, dismiss the tutorial
            dismiss(animated: true) {
                self.onDismiss?()
            }
        }
    }
}

// MARK: - SwiftUI Helper
struct TutorialViewControllerRepresentable: UIViewControllerRepresentable {
    let onDismiss: () -> Void
    
    func makeUIViewController(context: Context) -> TutorialViewController {
        return TutorialViewController(onDismiss: onDismiss)
    }
    
    func updateUIViewController(_ uiViewController: TutorialViewController, context: Context) {
        // No updates needed
    }
}

// MARK: - Tutorial Data
struct TutorialData {
    static let pages = [
        TutorialPage(
            title: "Welcome to Don't Pull Up",
            message: "This app helps you identify and share incidents in your area. Swipe or tap to continue.",
            emoji: "🗺️"
        ),
        TutorialPage(
            title: "Map Navigation",
            message: "Pan and zoom the map to explore your area. Tap the location button to center on your position.",
            emoji: "📍"
        ),
        TutorialPage(
            title: "Incident Filters",
            message: "Use the buttons on the right to filter incidents by type: verbal, physical, or emergency.",
            emoji: "📢"
        ),
        TutorialPage(
            title: "Reporting Incidents",
            message: "Tap the pencil icon to enter edit mode, then long-press within 200 feet of your location to drop a pin.",
            emoji: "📌"
        ),
        TutorialPage(
            title: "Allow access to photo library, select a video (max 3 min).",
            message: "The upload runs in the background & map updates automatically.",
            emoji: "🎬"
        ),
        TutorialPage(
            title: "Your Pins",
            message: "Tap the phone icon to view only pins you've dropped. You can edit or delete your own pins.",
            emoji: "📱"
        ),
        TutorialPage(
            title: "Map Types",
            message: "Toggle between standard and satellite view by tapping the map icon in the toolbar.",
            emoji: "🌎"
        ),
        TutorialPage(
            title: "Offline Mode",
            message: "You can still view previously loaded pins when offline, but can't add new ones.",
            emoji: "📶"
        ),
        TutorialPage(
            title: "Sign In",
            message: "Create an account to save your data across devices and access all features.",
            emoji: "👤"
        ),
        TutorialPage(
            title: "Settings",
            message: "Access app settings, terms of service, and privacy policy through the gear icon.",
            emoji: "⚙️"
        ),
        TutorialPage(
            title: "Help",
            message: "Tap the question mark icon for detailed help on using the app.",
            emoji: "❓"
        ),
        TutorialPage(
            title: "Ready to Go!",
            message: "You're all set! Tap to start using Don't Pull Up.",
            emoji: "��"
        )
    ]
}
