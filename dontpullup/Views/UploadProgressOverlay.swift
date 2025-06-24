import SwiftUI

/// Centered upload progress overlay that appears during video upload
struct UploadProgressOverlay: View {
    @ObservedObject var viewModel: MapViewModel
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        // Only show when actively uploading (progress > 0 and < 1)
        if viewModel.uploadProgress > 0 && viewModel.uploadProgress < 1.0 {
            // Center the progress indicator in the middle of the screen
            VStack {
                Spacer()
                
                HStack {
                    Spacer()
                    
                    // Enhanced centered progress indicator
                    VStack(spacing: 16) {
                        // Large circular progress indicator
                    ZStack {
                        Circle()
                                .stroke(Color.gray.opacity(0.3), lineWidth: 4)
                                .frame(width: 80, height: 80)
                        
                        Circle()
                            .trim(from: 0, to: CGFloat(viewModel.uploadProgress))
                                .stroke(Color.red, lineWidth: 4)
                                .frame(width: 80, height: 80)
                            .rotationEffect(.degrees(-90))
                                .animation(.easeInOut(duration: 0.3), value: viewModel.uploadProgress)
                        
                            Text("\(Int(viewModel.uploadProgress * 100))%")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                        }
                        
                        // Upload status text
                        VStack(spacing: 4) {
                            Text("Uploading Video")
                                .font(.headline)
                            .foregroundColor(.white)
                    
                            Text("Please wait...")
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
            .animation(.easeInOut(duration: 0.3), value: viewModel.uploadProgress)
        }
    }
}

// MARK: - Previews
struct UploadProgressOverlay_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.gray.opacity(0.3)
                .edgesIgnoringSafeArea(.all)
            
            let viewModel = MapViewModel(authState: AuthState.shared)
            UploadProgressOverlay(viewModel: viewModel)
                .onAppear {
                    viewModel.uploadProgress = 0.67
                }
        }
    }
} 