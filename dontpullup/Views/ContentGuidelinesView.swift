import SwiftUI

struct ContentGuidelinesView: View {
  @Binding var isPresented: Bool
  let onAccept: () -> Void

  @State private var hasScrolledToBottom = false
  @State private var acceptedGuidelines = false
  @State private var acceptedEmergencyDisclaimer = false
  @State private var acceptedRecordingConsent = false

  var allAccepted: Bool {
    acceptedGuidelines && acceptedEmergencyDisclaimer && acceptedRecordingConsent
      && hasScrolledToBottom
  }

  var body: some View {
    NavigationView {
      ScrollViewReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            Spacer().frame(height: 12)
            // Header
            VStack(spacing: 8) {
              Image(systemName: "shield.checkerboard")
                .font(.system(size: 50))
                .foregroundColor(.orange)

              Text("Community Guidelines")
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

              Text("Please read and accept these important guidelines before using Don't Pull Up")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top)

            // Emergency Disclaimer
            DPUCard(backgroundColor: Color.red.opacity(0.1), cornerRadius: 12, useShadow: true) {
              VStack(alignment: .leading, spacing: 12) {
                HStack {
                  Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.title2)
                  Text("EMERGENCY DISCLAIMER")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.red)
                }

                VStack(alignment: .leading, spacing: 8) {
                  Text("• This app is NOT a substitute for emergency services")
                  Text("• For immediate danger, call 911 DIRECTLY")
                  Text("• Do not rely on this app for emergency response")
                  Text("• Always contact authorities for serious incidents")
                }
                .font(.body)

                HStack {
                  Image(
                    systemName: acceptedEmergencyDisclaimer ? "checkmark.square.fill" : "square"
                  )
                  .foregroundColor(acceptedEmergencyDisclaimer ? .green : .gray)
                  .font(.title2)

                  Text("I understand this is not an emergency service")
                    .font(.body)
                    .fontWeight(.medium)
                }
                .padding(.top, 8)
                .onTapGesture {
                  acceptedEmergencyDisclaimer.toggle()
                }
          }
          .padding(.horizontal, 20)
          .padding(.vertical, 24)
            }

            // Recording Consent Guidelines
            DPUCard(backgroundColor: Color.blue.opacity(0.1), cornerRadius: 12, useShadow: true) {
              VStack(alignment: .leading, spacing: 12) {
                HStack {
                  Image(systemName: "video.fill")
                    .foregroundColor(.blue)
                    .font(.title2)
                  Text("RECORDING CONSENT")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
                }

                VStack(alignment: .leading, spacing: 8) {
                  Text("Before recording video:")
                  Text("• Only record in public spaces where legal")
                  Text("• Respect others' privacy and consent")
                  Text("• Do not record private property without permission")
                  Text("• Be mindful of bystanders and minors")
                  Text("• You are legally responsible for what you record")
                }
                .font(.body)

                HStack {
                  Image(systemName: acceptedRecordingConsent ? "checkmark.square.fill" : "square")
                    .foregroundColor(acceptedRecordingConsent ? .green : .gray)
                    .font(.title2)

                  Text("I will obtain proper consent before recording")
                    .font(.body)
                    .fontWeight(.medium)
                }
                .padding(.top, 8)
                .onTapGesture {
                  acceptedRecordingConsent.toggle()
                }
              }
              .padding()
            }

            // Community Standards
            DPUCard(backgroundColor: Color.green.opacity(0.1), cornerRadius: 12, useShadow: true) {
              VStack(alignment: .leading, spacing: 12) {
                HStack {
                  Image(systemName: "person.3.fill")
                    .foregroundColor(.green)
                    .font(.title2)
                  Text("COMMUNITY STANDARDS")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.green)
                }

                VStack(alignment: .leading, spacing: 8) {
                  Text("Prohibited Content:")
                  Text("• False or misleading incident reports")
                  Text("• Harassment, threats, or hate speech")
                  Text("• Graphic violence or disturbing content")
                  Text("• Personal information of others")
                  Text("• Spam or promotional content")
                  Text("• Content violating local laws")

                  Text("\nViolations may result in:")
                  Text("• Content removal")
                  Text("• Account suspension or termination")
                  Text("• Reporting to authorities if necessary")
                }
                .font(.body)
              }
              .padding()
            }

            // Legal Responsibility
            DPUCard(backgroundColor: Color.orange.opacity(0.1), cornerRadius: 12, useShadow: true) {
              VStack(alignment: .leading, spacing: 12) {
                HStack {
                  Image(systemName: "scale.3d")
                    .foregroundColor(.orange)
                    .font(.title2)
                  Text("YOUR RESPONSIBILITIES")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.orange)
                }

                VStack(alignment: .leading, spacing: 8) {
                  Text("By using this app, you agree that:")
                  Text("• You are solely responsible for all content you post")
                  Text("• You verify accuracy before reporting incidents")
                  Text("• You have rights to any media you upload")
                  Text("• You indemnify the app creators from user-generated content")
                  Text("• You understand false reports may have legal consequences")
                  Text("• The app creators are not liable for user content")
                }
                .font(.body)
              }
              .padding()
            }

            // Safety Guidelines
            DPUCard(backgroundColor: Color.purple.opacity(0.1), cornerRadius: 12, useShadow: true) {
              VStack(alignment: .leading, spacing: 12) {
                HStack {
                  Image(systemName: "shield.fill")
                    .foregroundColor(.purple)
                    .font(.title2)
                  Text("SAFETY FIRST")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.purple)
                }

                VStack(alignment: .leading, spacing: 8) {
                  Text("Your safety is the priority:")
                  Text("• Do not approach dangerous situations")
                  Text("• Report from a safe distance")
                  Text("• Let professionals handle emergencies")
                  Text("• Do not interfere with police or emergency responders")
                  Text("• Trust your instincts - leave if you feel unsafe")
                }
                .font(.body)
              }
              .padding()
            }

            // Final Acceptance
            DPUCard(backgroundColor: Color.gray.opacity(0.1), cornerRadius: 12, useShadow: true) {
              VStack(spacing: 12) {
                HStack {
                  Image(systemName: acceptedGuidelines ? "checkmark.square.fill" : "square")
                    .foregroundColor(acceptedGuidelines ? .green : .gray)
                    .font(.title2)

                  VStack(alignment: .leading) {
                    Text("I have read and agree to these Community Guidelines")
                      .font(.body)
                      .fontWeight(.medium)
                    Text("I understand my legal responsibilities as a user")
                      .font(.caption)
                      .foregroundColor(.secondary)
                  }
                  Spacer()
                }
                .onTapGesture {
                  acceptedGuidelines.toggle()
                }
              }
              .padding()
            }

            // Scroll indicator
            HStack {
              Spacer()
              if !hasScrolledToBottom {
                Text("↓ Scroll to continue ↓")
                  .font(.caption)
                  .foregroundColor(.secondary)
                  .padding()
              }
              Spacer()
            }
            .id("bottom")
          }
          .padding(.horizontal)
          .onAppear {
            // Detect when user has scrolled to bottom
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
              withAnimation {
                proxy.scrollTo("bottom", anchor: .bottom)
              }
            }
          }

        }
      }
      .navigationTitle("Guidelines")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
          Button("Cancel") {
            isPresented = false
          }
        }

        ToolbarItem(placement: .navigationBarTrailing) {
          Button("Accept") {
            onAccept()
            isPresented = false
          }
          .disabled(!allAccepted)
          .fontWeight(allAccepted ? .bold : .regular)
          .foregroundColor(allAccepted ? .green : .gray)
        }
      }
    }
    .onAppear {
      // Auto-scroll to bottom after a delay to ensure user reads everything
      DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
        hasScrolledToBottom = true
      }
    }
    .dpuBackground()
  }
}

// Storage for guidelines acceptance
extension UserDefaults {
  var hasAcceptedContentGuidelines: Bool {
    get { bool(forKey: "hasAcceptedContentGuidelines") }
    set { set(newValue, forKey: "hasAcceptedContentGuidelines") }
  }
}

#Preview {
  ContentGuidelinesView(isPresented: .constant(true)) {
    print("Guidelines accepted")
  }
}
