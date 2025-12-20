import SwiftUI
import MapKit

/// MapView wrapper that includes the upload progress indicator
struct MapContentWrapper: View {
    @ObservedObject var viewModel: MapViewModel
    
    var body: some View {
        ZStack {
            // Main MapView with report sheet functionality
            MapViewWithReportSheet(
                viewModel: viewModel,
                region: $viewModel.region
            )
            .edgesIgnoringSafeArea(.all)
            
            // Upload progress overlay (pin uploads or perspective uploads)
            let isPinUploading = viewModel.uploadProgress > 0 && viewModel.uploadProgress < 1.0
            let isPerspectiveUploading = viewModel.isUploadingPerspective
              && viewModel.perspectiveUploadProgress > 0
              && viewModel.perspectiveUploadProgress < 1.0
            
            if isPinUploading || isPerspectiveUploading {
                let progress = isPerspectiveUploading ? viewModel.perspectiveUploadProgress : viewModel.uploadProgress
                let title = isPerspectiveUploading ? "Uploading Perspective" : "Uploading Video"
                let subtitle = "Please wait..."
                
                UploadProgressOverlay(
                    progress: progress,
                    title: title,
                    subtitle: subtitle
                )
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: progress)
            }
        }
    }
}

// Removed duplicate UploadProgressOverlay definition - now using the one from UploadProgressOverlay.swift 