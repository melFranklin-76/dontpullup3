import SwiftUI
import UserNotifications

struct SettingsView: View {
  @EnvironmentObject private var authState: AuthState
  @ObservedObject private var authManager = AuthenticationManager.shared
  @StateObject private var premiumManager = PremiumManager.shared
  @Environment(\.dismiss) private var dismiss

  @AppStorage("notificationsEnabled") private var notificationsEnabled = true
  @AppStorage("darkModeEnabled") private var darkModeEnabled = true
  @AppStorage("hapticFeedbackEnabled") private var hapticFeedbackEnabled = true

  @State private var showResetConfirmation = false
  @State private var showNotificationsAlert = false
  @State private var activeSheet: SettingsSheet?

  var body: some View {
    NavigationView {
      NoBounceScrollView {
        VStack(spacing: 20) {
          Spacer().frame(height: 8)
          // GENERAL section
          DPUSectionHeader(title: "GENERAL")

          ModernDPUCard {
            VStack(spacing: 16) {
              // Enable Notifications toggle with permission request and alert
              EnhancedToggle(
                isOn: $notificationsEnabled,
                label: "Enable Notifications",
                description: "Receive alerts about incidents in your areas"
              )
              .onChange(of: notificationsEnabled) { newValue in
                if newValue {
                  UNUserNotificationCenter.current().requestAuthorization(
                    options: [.alert, .badge, .sound]
                  ) { granted, error in
                    DispatchQueue.main.async {
                      if !granted {
                        notificationsEnabled = false
                      }
                    }
                  }
                } else {
                  // Show alert that notifications must be disabled in system settings
                  showNotificationsAlert = true
                }
              }
              .alert("Disable Notifications", isPresented: $showNotificationsAlert) {
                Button("OK") {}
              } message: {
                Text("To fully disable push notifications, please turn them off in your device's Settings app.")
              }

              // Dark Mode toggle that actually applies color scheme
              EnhancedToggle(
                isOn: $darkModeEnabled,
                label: "Dark Mode",
                description: "Use dark theme for better visibility at night"
              )

              // Haptic Feedback toggle
              EnhancedToggle(
                isOn: $hapticFeedbackEnabled,
                label: "Haptic Feedback",
                description: "Vibrate when interacting with buttons"
              )
            }

            // Direct way to launch tutorial for testing
            ModernButton(
              title: "Show Tutorial Guide",
              systemImage: "questionmark.circle",
              style: .secondary
            ) {
              UserDefaults.standard.set(false, forKey: "hasSeenTutorial")
              NotificationCenter.default.post(
                name: Notification.Name("ShowTutorialOverlay"), object: nil)
            }
          }

          // NOTIFICATIONS section
          DPUSectionHeader(title: "NOTIFICATIONS")

          ModernDPUCard {
            ModernButton(
              title: "Notification Preferences",
              systemImage: "bell.badge",
              style: .secondary
            ) {
              activeSheet = .notifications
            }
          }

          // PREMIUM section
          if let userProfile = authManager.currentUserProfile {
            DPUSectionHeader(title: userProfile.isPremium ? "PREMIUM SETTINGS" : "UPGRADE")

            DPUCard {
              if userProfile.isPremium {
                VStack(spacing: 15) {
                  // Premium status indicator
                  HStack {
                    Image(systemName: "star.fill")
                      .foregroundColor(.yellow)
                    Text("Premium Active")
                      .foregroundColor(.white)
                      .font(.headline)
                    Spacer()
                  }

                  Divider().background(Color.gray.opacity(0.3))

                  // Current zip code display
                  HStack {
                    VStack(alignment: .leading) {
                      Text("Current Zip Code")
                        .foregroundColor(.gray)
                        .font(.caption)
                      Text(userProfile.zipCode)
                        .foregroundColor(.white)
                        .font(.title2)
                    }
                    Spacer()
                    Button(action: {
                      #if DEBUG
                      print(
                        "[SettingsView] Change button tapped - isPremium: \(userProfile.isPremium)")
                      print("[SettingsView] Current zip: \(userProfile.zipCode)")
                      #endif
                      activeSheet = .zipEditor
                    }) {
                      Text("Change")
                        .foregroundColor(userProfile.isPremium ? .blue : .gray)
                    }
                    .disabled(!userProfile.isPremium)
                  }

                  // Premium benefits reminder
                  Text(
                    "✓ View incidents from all zip codes\n✓ Change location anytime\n✓ Enhanced notifications"
                  )
                  .foregroundColor(.gray)
                  .font(.caption)
                  .multilineTextAlignment(.leading)
                }
                .padding(.vertical, 10)
              } else {
                VStack(spacing: 15) {
                  HStack {
                    VStack(alignment: .leading) {
                      Text("Free Plan")
                        .foregroundColor(.white)
                        .font(.headline)
                      Text("Limited to \(userProfile.originalZipCode)")
                        .foregroundColor(.gray)
                        .font(.caption)
                    }
                    Spacer()
                    Button(action: {
                      activeSheet = .premium
                    }) {
                      Text("Upgrade")
                        .foregroundColor(.yellow)
                        .fontWeight(.semibold)
                    }
                  }
                }
                .padding(.vertical, 10)
              }
            }
          }

          // APP INFO section
          DPUSectionHeader(title: "APP INFO")

          DPUCard {
            VStack(spacing: 8) {
              NavigationLink(destination: AboutView()) {
                HStack {
                  Text("About Don't Pull Up")
                    .foregroundColor(.white)
                  Spacer()
                  Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                }
                .contentShape(Rectangle())
                .padding(.vertical, 10)
              }

              Divider().background(Color.gray.opacity(0.3))

              NavigationLink(destination: PrivacyPolicyView()) {
                HStack {
                  Text("Privacy Policy")
                    .foregroundColor(.white)
                  Spacer()
                  Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                }
                .contentShape(Rectangle())
                .padding(.vertical, 10)
              }

              Divider().background(Color.gray.opacity(0.3))

              NavigationLink(destination: TermsOfServiceView()) {
                HStack {
                  Text("Terms of Service")
                    .foregroundColor(.white)
                  Spacer()
                  Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                }
                .contentShape(Rectangle())
                .padding(.vertical, 10)
              }
            }
          }

          // RESET section
          DPUCard {
            Button(action: {
              showResetConfirmation = true
            }) {
              Text("Reset All Settings")
                .foregroundColor(.red)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.vertical, 10)
          }

          // VERSION INFO section
          DPUCard {
            HStack {
              Spacer()
              VStack(spacing: 8) {
                Text("Don't Pull Up")
                  .font(.headline)
                  .foregroundColor(.gray)

                Text("Version 1.0.0 (Build 1)")
                  .font(.caption)
                  .foregroundColor(.gray)
              }
              Spacer()
            }
            .padding(.vertical, 8)
          }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
      }
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.inline)
      .alert("Reset Settings", isPresented: $showResetConfirmation) {
        Button("Cancel", role: .cancel) {}
        Button("Reset", role: .destructive) {
          resetSettings()
        }
      } message: {
        Text("Are you sure you want to reset all settings to their default values?")
      }
      .sheet(item: $activeSheet) { sheet in
        switch sheet {
        case .zipEditor:
          ZipCodeEditorView(
            currentZipCode: authManager.currentUserProfile?.zipCode ?? "",
            onSave: { newZip in
              handleZipCodeSave(newZip)
            },
            onCancel: {
              activeSheet = nil
            }
          )
        case .premium:
          PremiumView()
        case .notifications:
          NotificationSettingsView()
        }
      }
    }
    .dpuBackground()
    .navigationViewStyle(.stack)
    .preferredColorScheme(darkModeEnabled ? .dark : .light)
    .onAppear {
      #if DEBUG
      print(
        "[SettingsView] onAppear – isPremium = \(authManager.currentUserProfile?.isPremium ?? false)"
      )
      #endif
    }
  }

  private func resetSettings() {
    // Reset UI state
    notificationsEnabled = true
    darkModeEnabled = true
    hapticFeedbackEnabled = true

    // Reset all user defaults related to authentication and tutorial
    let defaults = UserDefaults.standard
    defaults.set(false, forKey: "allowAnonymousAccess")
    defaults.set(true, forKey: "shouldShowInstructions")
    defaults.set(false, forKey: "hasSeenTutorial")

    // Notify the app to show tutorial when needed
    NotificationCenter.default.post(name: Notification.Name("ShowTutorialOverlay"), object: nil)

    // Reset location permission preferences (this won't affect actual system permissions)
    defaults.set(false, forKey: "userDeclinedLocationPermissions")

    // Sign out the user - this will trigger navigation back to the auth screen
    authState.signOut()

    // Show confirmation feedback only if haptics enabled
    if hapticFeedbackEnabled {
      let banner = UINotificationFeedbackGenerator()
      banner.notificationOccurred(.success)
    }

    // Dismiss this view after a short delay to allow the haptic feedback to complete
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      // Dismiss the settings view
      dismiss()

      // The RootView will automatically show the AuthView since the user is now signed out
    }
  }

  private func handleZipCodeSave(_ newZip: String) {
    Task {
      do {
        try await authManager.updateZipCode(newZip)
        await MainActor.run {
          activeSheet = nil
        }
      } catch {
        #if DEBUG
        print("Failed to update zip code: \(error.localizedDescription)")
        #endif
      }
    }
  }
}

private enum SettingsSheet: Identifiable {
  case zipEditor
  case premium
  case notifications

  var id: Int { hashValue }
}

// MARK: - Notification Settings Sheet

private struct NotificationSettingsView: View {
  @ObservedObject private var authManager = AuthenticationManager.shared
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationView {
      NoBounceScrollView {
        VStack(spacing: 20) {
          Spacer().frame(height: 12)

          VStack(spacing: 8) {
            Image(systemName: "bell.badge")
              .resizable()
              .aspectRatio(contentMode: .fit)
              .frame(width: 60, height: 60)
              .foregroundColor(DPUTheme.colors.electricBlue)

            Text("Notification Settings")
              .font(.title)
              .fontWeight(.bold)
              .foregroundColor(.white)

            Text("Control which areas send you notifications")
              .font(.subheadline)
              .foregroundColor(.gray)
              .multilineTextAlignment(.center)
          }
          .padding(.top, 20)

          if let profile = authManager.currentUserProfile {
            DPUSectionHeader(title: "ZIP CODE NOTIFICATIONS")

            ModernDPUCard {
              VStack(spacing: 16) {
                ForEach(profile.accessibleZipCodes.sorted(), id: \.self) { zipCode in
                  NotificationToggleRow(
                    zipCode: zipCode,
                    isEnabled: profile.notificationsEnabled(for: zipCode),
                    profile: profile
                  ) { enabled in
                    Task {
                      await authManager.updateNotificationPreference(enabled, for: zipCode)
                    }
                  }
                }

                if profile.accessibleZipCodes.isEmpty {
                  Text("No accessible zip codes")
                    .foregroundColor(.gray)
                    .font(.subheadline)
                    .padding()
                }
              }
            }

            DPUSectionHeader(title: "ABOUT")

            ModernDPUCard {
              VStack(alignment: .leading, spacing: 16) {
                InfoRow(
                  icon: "house.fill",
                  title: "Home Area",
                  description: "Your original signup zip code - always accessible"
                )

                if profile.isPremium {
                  InfoRow(
                    icon: "star.fill",
                    title: "Premium Access",
                    description: "All zip codes available as notification areas"
                  )
                } else if !profile.purchasedZipCodes.isEmpty {
                  InfoRow(
                    icon: "checkmark.circle.fill",
                    title: "Purchased Areas",
                    description:
                      "\(profile.purchasedZipCodes.count) additional zip code(s) unlocked"
                  )
                }

                InfoRow(
                  icon: "location.fill",
                  title: "Current Location",
                  description: "Areas you're physically in receive notifications"
                )
              }
            }
          } else {
            Text("Please sign in to manage notification settings")
              .foregroundColor(.gray)
              .padding()
          }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
      }
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button("Done") {
            dismiss()
          }
          .foregroundColor(.white)
        }
      }
    }
    .dpuBackground()
    .preferredColorScheme(.dark)
  }
}

private struct NotificationToggleRow: View {
  let zipCode: String
  @State private var isEnabled: Bool
  let profile: UserProfile
  let onToggle: (Bool) -> Void

  init(zipCode: String, isEnabled: Bool, profile: UserProfile, onToggle: @escaping (Bool) -> Void) {
    self.zipCode = zipCode
    self._isEnabled = State(initialValue: isEnabled)
    self.profile = profile
    self.onToggle = onToggle
  }

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text(zipCode)
            .font(.headline)
            .foregroundColor(.white)

          if zipCode == profile.originalZipCode {
            BadgeView(text: "Home", color: .green)
          } else if profile.purchasedZipCodes.contains(zipCode) {
            BadgeView(text: "Purchased", color: .blue)
          } else if profile.isPremium {
            BadgeView(text: "Premium", color: .yellow)
          }
        }

        Text(description)
          .font(.caption)
          .foregroundColor(.gray)
      }

      Spacer()

      Toggle("", isOn: $isEnabled)
        .toggleStyle(SwitchToggleStyle(tint: DPUTheme.colors.electricBlue))
        .onChange(of: isEnabled) { newValue in
          onToggle(newValue)
        }
    }
    .padding(.vertical, 8)
  }

  private var description: String {
    if zipCode == profile.originalZipCode {
      return "Your home area - always accessible"
    } else if profile.purchasedZipCodes.contains(zipCode) {
      return "Purchased access - permanent"
    } else if profile.isPremium {
      return "Premium access - unlimited"
    }
    return "Available area"
  }
}

private struct InfoRow: View {
  let icon: String
  let title: String
  let description: String

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: icon)
        .foregroundColor(.blue)
        .frame(width: 24, height: 24)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.subheadline)
          .fontWeight(.medium)
          .foregroundColor(.white)

        Text(description)
          .font(.caption)
          .foregroundColor(.gray)
      }
    }
  }
}

private struct BadgeView: View {
  let text: String
  let color: Color

  var body: some View {
    Text(text.uppercased())
      .font(.caption2.weight(.semibold))
      .foregroundColor(DPUTheme.colors.lightGray)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(
        Capsule(style: .continuous)
          .fill(color.opacity(0.15))
          .overlay(
            Capsule(style: .continuous)
              .stroke(color.opacity(0.45), lineWidth: 0.8)
          )
      )
  }
}

struct AboutView: View {
  var body: some View {
    NoBounceScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text("About Don't Pull Up")
          .font(.title)
          .fontWeight(.bold)
          .foregroundColor(.white)
          .padding(.bottom, 8)

        Text(
          "Don't Pull Up is a community-driven safety app designed to help users identify and avoid potentially unsafe areas. The app allows users to mark locations where incidents have occurred, helping others stay informed and make safer decisions about their travel routes."
        )
        .foregroundColor(.white)
        .fixedSize(horizontal: false, vertical: true)  // Allow text to wrap properly

        Text(
          "Our mission is to create a safer community through shared awareness and information. By reporting incidents, you're helping others stay safe."
        )
        .foregroundColor(.white)
        .fixedSize(horizontal: false, vertical: true)  // Allow text to wrap properly

        Text(
          "The app is built with privacy in mind. All reports are anonymous by default, and we do not track your location unless you explicitly grant permission."
        )
        .foregroundColor(.white)
        .fixedSize(horizontal: false, vertical: true)  // Allow text to wrap properly

        // Add more content to ensure scrolling is possible
        Text("Community Guidelines")
          .font(.headline)
          .foregroundColor(.white)
          .padding(.top, 20)
          .padding(.bottom, 8)

        Text(
          "We ask all users to follow our community guidelines when reporting incidents. Please only report actual incidents that you've witnessed or experienced, and provide accurate information. False reports can harm the community and diminish the effectiveness of the app."
        )
        .foregroundColor(.white)
        .fixedSize(horizontal: false, vertical: true)  // Allow text to wrap properly

        Text("Contact Us")
          .font(.headline)
          .foregroundColor(.white)
          .padding(.top, 20)
          .padding(.bottom, 8)

        Text(
          "If you have any questions, concerns, or suggestions about the app, please contact our support team at support@dontpullup.com."
        )
        .foregroundColor(.white)
        .fixedSize(horizontal: false, vertical: true)  // Allow text to wrap properly
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 24)
    }
    .navigationTitle("About")
    .navigationBarTitleDisplayMode(.inline)
    .dpuBackground()
  }
}

struct PrivacyPolicyView: View {
  var body: some View {
    NoBounceScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text("Privacy Policy")
          .font(.title)
          .fontWeight(.bold)
          .foregroundColor(.white)

        Text("Last updated: January 2025")
          .font(.caption)
          .foregroundColor(.gray)

        Text(
          "This Privacy Policy describes how Don't Pull Up collects, uses, and discloses your personal information when you use our mobile application."
        )
        .foregroundColor(.white)
        .fixedSize(horizontal: false, vertical: true)  // Allow text to wrap properly

        Group {
          Text("Information We Collect")
            .font(.headline)
            .foregroundColor(.white)
            .padding(.top, 10)

          Text(
            "We may collect certain personal information when you create an account, such as your email address, display name, and general location. We also collect information about the incidents you report, including location data and incident type."
          )
          .foregroundColor(.white)
          .fixedSize(horizontal: false, vertical: true)  // Allow text to wrap properly
        }

        Group {
          Text("How We Use Your Information")
            .font(.headline)
            .foregroundColor(.white)
            .padding(.top, 10)

          Text(
            "We use the information we collect to provide, maintain, and improve our services, to communicate with you, and to protect our users and the public."
          )
          .foregroundColor(.white)
          .fixedSize(horizontal: false, vertical: true)  // Allow text to wrap properly
        }

        Group {
          Text("Information Sharing")
            .font(.headline)
            .foregroundColor(.white)
            .padding(.top, 10)

          Text(
            "We may share information about reported incidents with other users of the app to help them stay informed and make safer decisions. We will not share your personal information with third parties without your consent, except as required by law."
          )
          .foregroundColor(.white)
          .fixedSize(horizontal: false, vertical: true)  // Allow text to wrap properly
        }

        Group {
          Text("Data Security")
            .font(.headline)
            .foregroundColor(.white)
            .padding(.top, 10)

          Text(
            "We take reasonable measures to protect your personal information from unauthorized access, use, or disclosure. However, no method of transmission over the internet or electronic storage is 100% secure."
          )
          .foregroundColor(.white)
          .fixedSize(horizontal: false, vertical: true)  // Allow text to wrap properly
        }

        Group {
          Text("Your Rights")
            .font(.headline)
            .foregroundColor(.white)
            .padding(.top, 10)

          Text(
            "You have the right to access, correct, or delete your personal information. You can also opt out of receiving communications from us at any time."
          )
          .foregroundColor(.white)
          .fixedSize(horizontal: false, vertical: true)  // Allow text to wrap properly
        }

        Group {
          Text("Changes to This Privacy Policy")
            .font(.headline)
            .foregroundColor(.white)
            .padding(.top, 10)

          Text(
            "We may update our Privacy Policy from time to time. We will notify you of any changes by posting the new Privacy Policy on this page and updating the 'Last updated' date."
          )
          .foregroundColor(.white)
          .fixedSize(horizontal: false, vertical: true)  // Allow text to wrap properly
        }

        Group {
          Text("Contact Us")
            .font(.headline)
            .foregroundColor(.white)
            .padding(.top, 10)

          Text(
            "If you have any questions about this Privacy Policy, please contact us at privacy@dontpullup.com."
          )
          .foregroundColor(.white)
          .fixedSize(horizontal: false, vertical: true)  // Allow text to wrap properly
        }
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 24)
    }
    .navigationTitle("Privacy Policy")
    .navigationBarTitleDisplayMode(.inline)
    .dpuBackground()
  }
}

struct TermsOfServiceView: View {
  var body: some View {
    NoBounceScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text("Terms of Service")
          .font(.title)
          .fontWeight(.bold)
          .foregroundColor(.white)

        Text("Last updated: January 2025")
          .font(.caption)
          .foregroundColor(.gray)

        Text(
          "By downloading, installing, or using Don't Pull Up, you agree to be bound by these Terms of Service. If you do not agree to these terms, you may not use the app."
        )
        .foregroundColor(.white)
        .fixedSize(horizontal: false, vertical: true)  // Allow text to wrap properly

        Group {
          Text("User Content")
            .font(.headline)
            .foregroundColor(.white)
            .padding(.top, 10)

          Text(
            "Users are responsible for the content they submit to the app. You agree not to submit false or misleading information, or content that is offensive, harmful, or violates the rights of others."
          )
          .foregroundColor(.white)
          .fixedSize(horizontal: false, vertical: true)  // Allow text to wrap properly
        }

        Group {
          Text("Use of the Service")
            .font(.headline)
            .foregroundColor(.white)
            .padding(.top, 10)

          Text(
            "The app is intended to be used for informational purposes only. Don't Pull Up is not responsible for any actions taken based on the information provided through the app."
          )
          .foregroundColor(.white)
          .fixedSize(horizontal: false, vertical: true)  // Allow text to wrap properly
        }

        Group {
          Text("User Accounts")
            .font(.headline)
            .foregroundColor(.white)
            .padding(.top, 10)

          Text(
            "You are responsible for maintaining the confidentiality of your account credentials and for all activities that occur under your account. You agree to notify us immediately of any unauthorized use of your account."
          )
          .foregroundColor(.white)
          .fixedSize(horizontal: false, vertical: true)  // Allow text to wrap properly
        }

        Group {
          Text("Intellectual Property")
            .font(.headline)
            .foregroundColor(.white)
            .padding(.top, 10)

          Text(
            "All content and materials available in the app, including but not limited to text, graphics, logos, icons, images, audio clips, and software, are the property of Don't Pull Up or its licensors and are protected by copyright, trademark, and other intellectual property laws."
          )
          .foregroundColor(.white)
          .fixedSize(horizontal: false, vertical: true)  // Allow text to wrap properly
        }

        Group {
          Text("Limitation of Liability")
            .font(.headline)
            .foregroundColor(.white)
            .padding(.top, 10)

          Text(
            "In no event shall Don't Pull Up be liable for any indirect, incidental, special, consequential, or punitive damages, including without limitation, loss of profits, data, use, goodwill, or other intangible losses, resulting from your access to or use of or inability to access or use the app."
          )
          .foregroundColor(.white)
          .fixedSize(horizontal: false, vertical: true)  // Allow text to wrap properly
        }

        Group {
          Text("Changes to Terms")
            .font(.headline)
            .foregroundColor(.white)
            .padding(.top, 10)

          Text(
            "We reserve the right to modify or replace these Terms of Service at any time. If a revision is material, we will provide at least 30 days' notice prior to any new terms taking effect."
          )
          .foregroundColor(.white)
          .fixedSize(horizontal: false, vertical: true)  // Allow text to wrap properly
        }

        Group {
          Text("Contact Us")
            .font(.headline)
            .foregroundColor(.white)
            .padding(.top, 10)

          Text(
            "If you have any questions about these Terms of Service, please contact us at terms@dontpullup.com."
          )
          .foregroundColor(.white)
          .fixedSize(horizontal: false, vertical: true)  // Allow text to wrap properly
        }
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 24)
    }
    .navigationTitle("Terms of Service")
    .navigationBarTitleDisplayMode(.inline)
    .dpuBackground()
  }
}

#Preview {
  SettingsView()
    .environmentObject(AuthState.shared)
}

extension View {
  @ViewBuilder
  func hideListBackgroundIfNeeded() -> some View {
    if #available(iOS 16.0, *) {
      self.scrollContentBackground(.hidden)
    } else {
      // For iOS versions below 16.0, we need an alternative approach
      self.onAppear {
        // This modifies the UITableView background for iOS 15 and below
        UITableView.appearance().backgroundColor = .clear
      }
      .onDisappear {
        // Reset when view disappears
        UITableView.appearance().backgroundColor = .systemGroupedBackground
      }
    }
  }
}
