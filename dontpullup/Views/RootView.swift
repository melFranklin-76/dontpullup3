import SwiftUI

struct RootView: View {
    @EnvironmentObject var authState: AuthState // Use the injected AuthState
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @State private var showTutorialOverlay = false

    var body: some View {
        let isAuthenticated = authState.isAuthenticated

        Group { // Outer group
            if authState.isLoading {
                SplashScreen()
                    #if DEBUG
                    .onAppear { print("[RootView] SplashScreen appeared") }
                    .onDisappear { print("[RootView] SplashScreen disappeared") }
                    #endif
            } else {
                // Restore the original logic for showing AuthView or MainTabView

                Group { // Inner group wrapping conditionals
                    if isAuthenticated { // Simplified condition: if authenticated (anonymous or not), show MainTabView
                        MainTabView()
                            .id("MainTabView_\(authState.isAuthenticated)_\(authState.currentUser?.uid ?? "none")_anon:\(authState.isAnonymous)") // Adjusted ID to reflect anon status
                            .onAppear {
                                #if DEBUG
                                if authState.isAnonymous {
                                    print("[RootView] Showing MainTabView for ANONYMOUS authenticated user")
                                } else {
                                    print("[RootView] Showing MainTabView because isAuthenticated is TRUE and isAnonymous is FALSE")
                                }
                                #endif
                                // showInstructions = authState.shouldShowInstructions // Keep this commented for now
                            }
                            // .onDisappear { print("[RootView] MainTabView disappeared") } // Keep commented
                            // .fullScreenCover(isPresented: $showInstructions) { ... } // Keep commented
                    } else { // Not authenticated
                        AuthView()
                            .id("AuthView_unauthenticated") // Simplified ID
                            .onAppear {
                                #if DEBUG
                                print("[RootView] Showing AuthView because isAuthenticated is FALSE")
                                #endif
                            }
                            // .onDisappear { print("[RootView] AuthView (for unauth) disappeared") } // Keep commented
                    }
                } // End of inner Group
                // print("[RootView] Evaluating body state. isLoading: \\(authState.isLoading), isAuthenticated: \\(authState.isAuthenticated), isAnonymous: \\(authState.isAnonymous), currentUser: \\(authState.currentUser?.uid ?? "nil"))")
                // print("[RootView] Decision Point: isAuthenticated=\\(isAuthenticated), isAnonymous=\\(isAnonymous) after isLoading is false.")
            } // THIS IS THE ELSE BLOCK'S CLOSING BRACE
        }
        .onAppear { 
            #if DEBUG
            print("[RootView] Evaluating body state. isLoading: \(authState.isLoading), isAuthenticated: \(authState.isAuthenticated), isAnonymous: \(authState.isAnonymous), currentUser: \(authState.currentUser?.uid ?? "nil"))")
            #endif
            showTutorialOverlay = authState.isAuthenticated && authState.shouldShowInstructions
        }
        .onChange(of: authState.isAuthenticated) { isAuthed in
            if isAuthed && authState.shouldShowInstructions {
                showTutorialOverlay = true
            } else if !isAuthed {
                showTutorialOverlay = false
            }
        }
        .onChange(of: authState.shouldShowInstructions) { shouldShow in
            if shouldShow && authState.isAuthenticated {
                showTutorialOverlay = true
            } else if !shouldShow {
                showTutorialOverlay = false
            }
        }
        .onChange(of: showTutorialOverlay) { isShowing in
            if !isShowing && authState.shouldShowInstructions {
                authState.dismissInstructions()
            }
        }
        .overlay {
            ZStack {
                if !networkMonitor.isConnected {
                    VStack {
                        Spacer()
                        Text("No Internet Connection")
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.red.opacity(0.8))
                            .cornerRadius(8)
                            .padding(.bottom, 20)
                    }
                }

                if showTutorialOverlay {
                    TutorialOverlayView(isPresented: $showTutorialOverlay)
                        .transition(.opacity)
                        .zIndex(1000)
                }
            }
        }
    }
}

// Add a simple instructions view
struct InstructionsView: View {
    var onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Welcome to Don't Pull Up")
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .padding(.top, 40)
            
            Spacer()
            
            VStack(alignment: .leading, spacing: 16) {
                InstructionRow(
                    icon: "mappin.and.ellipse",
                    title: "Report Incidents",
                    description: "Long press on the map to place a pin and report an incident"
                )
                
                InstructionRow(
                    icon: "video.fill",
                    title: "Upload Videos",
                    description: "Add video evidence when reporting incidents"
                )
                
                InstructionRow(
                    icon: "location.fill",
                    title: "Find Your Location",
                    description: "Tap the location button to center the map on your current position"
                )
                
                InstructionRow(
                    icon: "exclamationmark.triangle.fill",
                    title: "Emergency Reporting",
                    description: "Use the emergency option for urgent situations requiring immediate attention"
                )
            }
            .padding()
            
            Spacer()
            
            Button(action: onDismiss) {
                Text("Got It")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
                    .padding(.horizontal, 40)
            }
            .padding(.bottom, 40)
        }
    }
}

struct InstructionRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundColor(.blue)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
