import SwiftUI

/// Tutorial overlay that shows as a series of instruction screens
/// for anonymous users or first-time users
struct TutorialOverlayView: View {
    @Binding var isPresented: Bool
    @State private var currentPage = 0
    
    // Tutorial content pages
    private let tutorialPages = [
        TutorialPage(
            title: "Welcome to Don't Pull Up, ON GRANDMA!",
            message: "Long-press to report what you see, attach short clips, and warn neighbors across your zip.",
            emoji: "🚨"
        ),
        TutorialPage(
            title: "Explore the Map",
            message: "Pan or pinch to zoom. Tap the green location button to focus on roughly a 200-foot circle around you.",
            emoji: "🗺️"
        ),
        TutorialPage(
            title: "Navigation Mode",
            message: "Tap the location button again to enable follow mode. The button turns blue and the map tracks your movement.",
            emoji: "🧭"
        ),
        TutorialPage(
            title: "Drop Pins Within Range",
            message: "Long-press anywhere within 200 feet of your position. Pins outside that radius are blocked to keep reports accurate.",
            emoji: "📌"
        ),
        TutorialPage(
            title: "Choose Incident Type",
            message: "Use the picker to tag Verbal, Physical, Emergency/911, or ICE encounters before submitting.",
            emoji: "🏷️"
        ),
        TutorialPage(
            title: "Attach Short Videos",
            message: "Record live or pick a clip from Photos (max 3 minutes). Stay on the screen to watch the circular upload progress.",
            emoji: "🎬"
        ),
        TutorialPage(
            title: "See Only Your Pins",
            message: "Tap the blue phone icon to toggle a view of just the incidents you have reported.",
            emoji: "📱"
        ),
        TutorialPage(
            title: "Edit or Delete",
            message: "Use the pencil button to enter edit mode, then tap one of your pins to remove it when a situation is resolved.",
            emoji: "✏️"
        ),
        TutorialPage(
            title: "Premium Access",
            message: "Unlock extra zip codes or upgrade to unlimited playback so you can watch videos posted outside your home area.",
            emoji: "💎"
        ),
        TutorialPage(
            title: "Filters & Alerts",
            message: "Use the right-side buttons to filter by incident type. We'll still send quick push alerts for nearby emergencies.",
            emoji: "🔔"
        ),
        TutorialPage(
            title: "Help & Settings",
            message: "Need resources, terms, or privacy info? Tap the gear or question mark icons in the main tab anytime.",
            emoji: "⚙️"
        ),
        TutorialPage(
            title: "You're Ready",
            message: "Tap anywhere to dismiss and start reporting responsibly. Stay safe out there.",
            emoji: "🚀"
        )
    ]
    
    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.9)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    advanceTutorial()
                }
            
            // Tutorial content with more visible styling
            VStack {
                Spacer()
                
                // Emoji at top
                Text(tutorialPages[currentPage].emoji)
                    .font(.system(size: 70))
                    .shadow(color: .white.opacity(0.3), radius: 10)
                    .padding(.bottom, 30)
                
                // Main content
                VStack(spacing: 20) {
                    Text(tutorialPages[currentPage].title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .shadow(color: .black, radius: 2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Text(tutorialPages[currentPage].message)
                        .font(.body)
                        .foregroundColor(.white)
                        .shadow(color: .black, radius: 1)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(20)
                .background(Color.black.opacity(0.5))
                .cornerRadius(15)
                
                Spacer()
                
                // Page indicator and dismiss instruction
                VStack(spacing: 8) {
                    Text("\(currentPage + 1) of \(tutorialPages.count)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                    
                    if currentPage < tutorialPages.count - 1 {
                        Text("Tap anywhere to continue")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.9))
                    } else {
                        Text("Tap anywhere to dismiss")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    }
                }
                .padding(12)
                .background(Color.gray.opacity(0.6))
                .cornerRadius(10)
                .padding(.bottom, 40)
            }
            .padding()
        }
        .transition(.opacity.combined(with: .scale))
        .zIndex(1000)
        .shadow(color: .black, radius: 20)
        .animation(.easeInOut, value: currentPage)
    }
    
    private func advanceTutorial() {
        if currentPage < tutorialPages.count - 1 {
            currentPage += 1
        } else {
            // Tutorial completed
            withAnimation {
                isPresented = false
            }
        }
    }
}

/// Model for tutorial page content
struct TutorialPage {
    let title: String
    let message: String
    let emoji: String
}

// Preview
struct TutorialOverlayView_Previews: PreviewProvider {
    static var previews: some View {
        TutorialOverlayView(isPresented: .constant(true))
            .preferredColorScheme(.dark)
    }
} 