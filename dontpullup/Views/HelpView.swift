import SwiftUI

struct HelpView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var showingSettings = false
  @State private var showingProfile = false
  @State private var showingTerms = false  // State for Terms sheet
  @State private var showingPrivacy = false  // State for Privacy sheet

  var body: some View {
    // Wrap in NavigationView to get a nav bar for the Done button and handle safe area
    NavigationView {
      NoBounceScrollView {
        VStack(spacing: 24) {
          // Title with clear spacing
          Text("Help & Resources")
            .font(.title2)
            .fontWeight(.bold)
            .padding(.bottom, 16)
            .foregroundColor(.white)

          // Central Action Buttons
          VStack(spacing: 24) {  // Increased spacing between buttons
            actionButton(title: "Settings", systemImage: "gearshape.fill") {
              showingSettings = true
            }

            actionButton(title: "Profile", systemImage: "person.fill") {
              showingProfile = true
            }

            actionButton(title: "Terms of Service", systemImage: "doc.text.fill") {
              showingTerms = true
            }

            actionButton(title: "Privacy Policy", systemImage: "shield.lefthalf.filled") {
              showingPrivacy = true
            }

            // Additional resources section to ensure content is scrollable
            DPUSectionHeader(title: "ADDITIONAL RESOURCES")
              .padding(.top, 16)

            DPUCard {
              VStack(alignment: .leading, spacing: 16) {
                Text("Community Support")
                  .font(.headline)
                  .foregroundColor(.white)

                Text(
                  "Find resources and support in your local community. Connect with others who are committed to safety and awareness."
                )
                .foregroundColor(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)

                Button(action: {
                  // This would navigate to a resources page in a real app
                }) {
                  Text("View Community Resources")
                    .foregroundColor(.blue)
                }
                .padding(.top, 4)
              }
              .padding(.vertical, 8)
            }

            DPUCard {
              VStack(alignment: .leading, spacing: 16) {
                Text("Safety Tips")
                  .font(.headline)
                  .foregroundColor(.white)

                Text(
                  "Learn how to stay safe in your community and what to do if you witness or experience an incident."
                )
                .foregroundColor(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)

                Button(action: {
                  // This would navigate to a safety tips page in a real app
                }) {
                  Text("View Safety Tips")
                    .foregroundColor(.blue)
                }
                .padding(.top, 4)
              }
              .padding(.vertical, 8)
            }

            // Contact section
            DPUSectionHeader(title: "CONTACT US")
              .padding(.top, 16)

            DPUCard {
              VStack(alignment: .leading, spacing: 16) {
                Text("Need help with the app?")
                  .font(.headline)
                  .foregroundColor(.white)

                Text(
                  "Our support team is here to help. Contact us with any questions or issues you may have."
                )
                .foregroundColor(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)

                Button(action: {
                  // This would open email or contact form in a real app
                }) {
                  Text("Contact Support")
                    .foregroundColor(.blue)
                }
                .padding(.top, 4)
              }
              .padding(.vertical, 8)
            }
          }
          .padding(.horizontal, 24)
        }
        .padding(.top, 16)
      }
      // Add Navigation Bar items
      .navigationBarTitleDisplayMode(.inline)
      // Optionally add a title if desired, or leave it blank
      .navigationBarItems(
        trailing: Button("Done") {
          dismiss()
        }
        .padding(.vertical, 8)  // Add vertical padding to increase tap target
      )
    }
    .navigationViewStyle(.stack)  // Use stack style for modal presentation
    .preferredColorScheme(.dark)  // Ensure dark mode for the NavigationView itself
    // Sheets for presenting modal views
    .sheet(isPresented: $showingSettings) {
      // Assuming SettingsView manages its own NavigationView if needed
      SettingsView()
    }
    .sheet(isPresented: $showingProfile) {
      // Assuming ProfileView manages its own NavigationView if needed
      ProfileView()
    }
    .sheet(isPresented: $showingTerms) {
      NavigationView {
        TermsOfServiceView()
          .navigationBarItems(
            trailing: Button("Done") { showingTerms = false }
              .padding(.vertical, 8))
      }
      .preferredColorScheme(.dark)
    }
    .sheet(isPresented: $showingPrivacy) {
      NavigationView {
        PrivacyPolicyView()
          .navigationBarItems(
            trailing: Button("Done") { showingPrivacy = false }
              .padding(.vertical, 8))
      }
      .preferredColorScheme(.dark)
    }
  }

  // Helper function for creating consistent action buttons
  private func actionButton(title: String, systemImage: String, action: @escaping () -> Void)
    -> some View
  {
    Button(action: action) {
      HStack(spacing: 15) {
        Image(systemName: systemImage)
          .font(.title2)
          .frame(width: 30)  // Align icons
        Text(title)
          .font(.headline)
        Spacer()
        Image(systemName: "chevron.right")
          .font(.system(size: 14))
          .opacity(0.5)
      }
      .padding(.vertical, 16)  // Increased vertical padding for better touch targets
      .padding(.horizontal, 20)  // Consistent horizontal padding
      .frame(maxWidth: .infinity)
      .background(Color.black.opacity(0.5))
      .foregroundColor(.white)
      .cornerRadius(10)
    }
  }
}

#Preview {
  HelpView()
}
