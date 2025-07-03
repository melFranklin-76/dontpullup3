import SwiftUI
import UIKit

/// A SwiftUI wrapper around UIScrollView that disables the rubber-band bounce
struct NoBounceScrollView<Content: View>: UIViewRepresentable {
  let axes: Axis.Set
  let showsIndicators: Bool
  let content: Content

  init(
    axes: Axis.Set = .vertical,
    showsIndicators: Bool = true,
    @ViewBuilder content: () -> Content
  ) {
    self.axes = axes
    self.showsIndicators = showsIndicators
    self.content = content()
  }

  func makeUIView(context: Context) -> UIScrollView {
    let scrollView = UIScrollView()
    scrollView.bounces = false  // disable rubber-band bounce
    scrollView.alwaysBounceVertical = axes.contains(.vertical) && showsIndicators
    scrollView.alwaysBounceHorizontal = axes.contains(.horizontal) && showsIndicators
    scrollView.showsVerticalScrollIndicator = showsIndicators
    scrollView.showsHorizontalScrollIndicator = showsIndicators

    // embed SwiftUI content
    let host = UIHostingController(rootView: content)
    host.view.translatesAutoresizingMaskIntoConstraints = false
    host.view.backgroundColor = .clear
    scrollView.addSubview(host.view)

    // pin content to scrollView's contentLayoutGuide
    NSLayoutConstraint.activate([
      host.view.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
      host.view.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
      host.view.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
      host.view.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),

      // match width (for vertical) or height (for horizontal) to frameLayoutGuide
      axes == .vertical
        ? host.view.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        : host.view.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
    ])

    return scrollView
  }

  func updateUIView(_ uiView: UIScrollView, context: Context) {
    // nothing to update
  }
}

// Add a ViewModifier to make NoBounceScrollView easier to use
struct NoBounceScrollModifier: ViewModifier {
  let showsIndicators: Bool
  
  func body(content: Content) -> some View {
    NoBounceScrollView(showsIndicators: showsIndicators) {
      content
    }
  }
}

// Extension to use NoBounceScrollView as a view modifier
extension View {
  func noBounceScroll(showsIndicators: Bool = true) -> some View {
    modifier(NoBounceScrollModifier(showsIndicators: showsIndicators))
  }
}
