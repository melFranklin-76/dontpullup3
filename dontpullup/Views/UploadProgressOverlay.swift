import SwiftUI

/// Centered progress overlay for both main pin uploads and perspectives.
struct UploadProgressOverlay: View {
    let progress: Double   // 0...1
    let title: String
    let subtitle: String
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        // Center the progress indicator in the middle of the screen
        VStack {
            Spacer()
            
            HStack {
                Spacer()
                
                VStack(spacing: 16) {
                    // Large circular progress indicator
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.3), lineWidth: 4)
                            .frame(width: 80, height: 80)
                        
                        Circle()
                            .trim(from: 0, to: CGFloat(progress))
                            .stroke(Color.red, lineWidth: 4)
                            .frame(width: 80, height: 80)
                            .rotationEffect(.degrees(-90))
                            .animation(.easeInOut(duration: 0.3), value: progress)
                        
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    // Upload status text
                    VStack(spacing: 4) {
                        Text(title)
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(colorScheme == .dark ?
                              Color.black.opacity(0.85) :
                              Color.gray.opacity(0.9))
                        .shadow(color: Color.black.opacity(0.4), radius: 8)
                )
                
                Spacer()
            }
            
            Spacer()
        }
        .transition(.scale.combined(with: .opacity))
        .animation(.easeInOut(duration: 0.3), value: progress)
    }
}

// MARK: - Previews
struct UploadProgressOverlay_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.gray.opacity(0.3)
                .edgesIgnoringSafeArea(.all)
            
            UploadProgressOverlay(
                progress: 0.67,
                title: "Uploading Video",
                subtitle: "Please wait..."
            )
        }
    }
}