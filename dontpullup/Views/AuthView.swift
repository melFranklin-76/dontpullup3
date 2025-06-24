import FirebaseAuth
import Network
import SwiftUI

struct AuthBackgroundModifier: ViewModifier {
  func body(content: Content) -> some View {
    ZStack {
      // Background Image
      Image("welcome_background")
        .resizable()
        .aspectRatio(contentMode: .fill)
        .edgesIgnoringSafeArea(.all)

      // Semi-transparent overlay
      Color.black.opacity(0.7)
        .edgesIgnoringSafeArea(.all)

      // Content
      content
    }
  }
}

extension View {
  func withAuthBackground() -> some View {
    modifier(AuthBackgroundModifier())
  }
}

// Add keyboard height detection with improved constraint handling
struct KeyboardAdaptive: ViewModifier {
  @State private var keyboardHeight: CGFloat = 0
  @State private var isKeyboardVisible: Bool = false

  func body(content: Content) -> some View {
    content
      .padding(.bottom, keyboardHeight)
      .animation(.easeInOut(duration: 0.25), value: keyboardHeight)  // Faster animation
      .onReceive(
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
      ) { notification in
        guard !isKeyboardVisible else { return }  // Prevent redundant updates

        if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey]
          as? NSValue
        {
          let keyboardRectangle = keyboardFrame.cgRectValue
          let keyboardHeight = keyboardRectangle.height

          // Use safer approach to get safe area insets
          let safeAreaBottom: CGFloat = {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow })
            else {
              return 0
            }
            return window.safeAreaInsets.bottom
          }()

          let adjustedHeight = max(0, keyboardHeight - safeAreaBottom)

          // Throttle updates to prevent constraint conflicts
          DispatchQueue.main.async {
            self.keyboardHeight = adjustedHeight
            self.isKeyboardVisible = true
          }
        }
      }
      .onReceive(
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
      ) { _ in
        guard isKeyboardVisible else { return }  // Prevent redundant updates

        DispatchQueue.main.async {
          self.keyboardHeight = 0
          self.isKeyboardVisible = false
        }
      }
  }
}

extension View {
  func keyboardAdaptive() -> some View {
    modifier(KeyboardAdaptive())
  }
}

struct AuthView: View {
  @Environment(\.colorScheme) private var colorScheme
  @EnvironmentObject private var networkMonitor: NetworkMonitor
  @EnvironmentObject var authState: AuthState

  @State private var showError = false
  @State private var errorMessage = ""
  @State private var isLoading = false

  @State private var isShowingSignIn = false
  @State private var isShowingSignUp = false

  @State private var email = ""
  @State private var password = ""
  @State private var zipCode = ""

  var body: some View {
    GeometryReader { geometry in
      ZStack {
        // Background Image
        Image("welcome_background")
          .resizable()
          .aspectRatio(contentMode: .fill)
          .frame(width: geometry.size.width, height: geometry.size.height)
          .edgesIgnoringSafeArea(.all)

        // Semi-transparent overlay
        Color.black.opacity(0.7)
          .edgesIgnoringSafeArea(.all)

        // Content
        ScrollView {
          VStack(spacing: adaptiveSpacing(for: geometry)) {
            // App Logo/Title - Adaptive sizing
            VStack(spacing: adaptiveSpacing(for: geometry, multiplier: 0.5)) {
              Text("DON'T PULL UP")
                .font(.system(size: adaptiveFontSize(for: geometry, baseSize: 32), weight: .bold))
                .foregroundColor(.yellow)
                .tracking(2.0)
                .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)

              Text("ON GRANDMA!")
                .font(
                  .custom(
                    "BlackOpsOne-Regular", size: adaptiveFontSize(for: geometry, baseSize: 24))
                )
                .foregroundColor(DPUTheme.colors.alertRed)
                .tracking(1.0)
                .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                .rotationEffect(.degrees(-15))
            }
            .padding(.top, adaptiveSpacing(for: geometry))

            // Main content with adaptive width
            VStack(spacing: adaptiveSpacing(for: geometry)) {
              // Authentication options
              if !isShowingSignIn && !isShowingSignUp {
                authOptionsView(geometry: geometry)
              } else if isShowingSignIn {
                signInView(geometry: geometry)
              } else if isShowingSignUp {
                signUpView(geometry: geometry)
              }
            }
            .frame(maxWidth: adaptiveContentWidth(for: geometry))
            .padding(.horizontal, adaptiveHorizontalPadding(for: geometry))
          }
        }
        .keyboardAdaptive()  // Apply keyboard avoidance
        .onTapGesture {
          // Dismiss keyboard when tapping outside fields
          UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
      }
      .alert(isPresented: $showError) {
        Alert(
          title: Text("Account Setup Issue"),
          message: Text(errorMessage),
          dismissButton: .default(Text("OK")))
      }
    }
  }

  // Helper function for adaptive content width
  private func adaptiveContentWidth(for geometry: GeometryProxy) -> CGFloat {
    let screenWidth = geometry.size.width
    return min(500, screenWidth - 40)  // Maximum 500pt width, with 20pt padding on each side
  }

  // Helper function for adaptive horizontal padding
  private func adaptiveHorizontalPadding(for geometry: GeometryProxy) -> CGFloat {
    let screenWidth = geometry.size.width
    let contentWidth = min(500, screenWidth - 40)
    return max(20, (screenWidth - contentWidth) / 2)
  }

  // Helper function for adaptive spacing
  private func adaptiveSpacing(for geometry: GeometryProxy, multiplier: CGFloat = 1.0) -> CGFloat {
    let baseSpacing: CGFloat = 20
    let screenWidth = geometry.size.width

    if screenWidth > 600 {
      return baseSpacing * multiplier * 1.2  // 20% more spacing on larger screens
    }

    return baseSpacing * multiplier
  }

  // Helper function for adaptive font sizes
  private func adaptiveFontSize(for geometry: GeometryProxy, baseSize: CGFloat) -> CGFloat {
    let screenWidth = geometry.size.width

    if screenWidth > 600 {
      return baseSize * 1.3  // 30% larger on iPad
    }

    return baseSize
  }

  // Auth options view with adaptive layout
  private func authOptionsView(geometry: GeometryProxy) -> some View {
    VStack(spacing: adaptiveSpacing(for: geometry)) {
      Text("Welcome")
        .font(.system(size: adaptiveFontSize(for: geometry, baseSize: 28), weight: .bold))
        .foregroundColor(.white)

      Text("Sign in or create an account to report incidents and help keep your community safe.")
        .font(.system(size: adaptiveFontSize(for: geometry, baseSize: 16)))
        .multilineTextAlignment(.center)
        .foregroundColor(.white.opacity(0.8))
        .padding(.bottom, adaptiveSpacing(for: geometry, multiplier: 0.5))

      // Sign In Button
      Button(action: { isShowingSignIn = true }) {
        Text("Sign In")
          .font(.system(size: adaptiveFontSize(for: geometry, baseSize: 18), weight: .bold))
          .foregroundColor(.white)
          .frame(maxWidth: .infinity)
          .frame(height: adaptiveButtonHeight(for: geometry))
      }
      .buttonStyle(.borderedProminent)
      .tint(.blue)
      .cornerRadius(12)

      // Sign Up Button
      Button(action: { isShowingSignUp = true }) {
        Text("Create Account")
          .font(.system(size: adaptiveFontSize(for: geometry, baseSize: 18), weight: .bold))
          .foregroundColor(.white)
          .frame(maxWidth: .infinity)
          .frame(height: adaptiveButtonHeight(for: geometry))
      }
      .buttonStyle(.borderedProminent)
      .tint(.green)
      .cornerRadius(12)

      // Continue as Guest
      if networkMonitor.isConnected {
        Button(action: performAnonymousSignIn) {
          ZStack {
            if isLoading {
              ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.2)
            } else {
              Text("Continue as Guest")
                .font(.system(size: adaptiveFontSize(for: geometry, baseSize: 16)))
                .foregroundColor(.white.opacity(0.8))
            }
          }
        }
        .disabled(isLoading)
        .padding(.top, adaptiveSpacing(for: geometry, multiplier: 0.5))
      } else {
        Text("Sign in required when offline")
          .font(.caption)
          .foregroundColor(.orange)
          .padding(.top, adaptiveSpacing(for: geometry, multiplier: 0.5))
      }
    }
    .padding(adaptiveSpacing(for: geometry))
    .background(Color.black.opacity(0.5))
    .cornerRadius(16)
  }

  // Sign In view with adaptive layout
  private func signInView(geometry: GeometryProxy) -> some View {
    VStack(spacing: adaptiveSpacing(for: geometry)) {
      Text("Sign In")
        .font(.system(size: adaptiveFontSize(for: geometry, baseSize: 28), weight: .bold))
        .foregroundColor(.white)
        .padding(.bottom, adaptiveSpacing(for: geometry, multiplier: 0.5))

      // Email field
      VStack(alignment: .leading, spacing: 8) {
        Text("Email")
          .font(.system(size: adaptiveFontSize(for: geometry, baseSize: 16)))
          .foregroundColor(.white)

        TextField("", text: $email)
          .font(.system(size: adaptiveFontSize(for: geometry, baseSize: 16)))
          .padding()
          .background(Color.white.opacity(0.1))
          .cornerRadius(8)
          .foregroundColor(.white)
          .keyboardType(.emailAddress)
          .autocapitalization(.none)
          .disableAutocorrection(true)
      }

      // Password field
      VStack(alignment: .leading, spacing: 8) {
        Text("Password")
          .font(.system(size: adaptiveFontSize(for: geometry, baseSize: 16)))
          .foregroundColor(.white)

        SecureField("", text: $password)
          .font(.system(size: adaptiveFontSize(for: geometry, baseSize: 16)))
          .padding()
          .background(Color.white.opacity(0.1))
          .cornerRadius(8)
          .foregroundColor(.white)
      }

      // Sign In Button
      Button(action: performSignIn) {
        ZStack {
          if isLoading {
            ProgressView()
              .progressViewStyle(CircularProgressViewStyle(tint: .white))
              .scaleEffect(1.2)
          } else {
            Text("Sign In")
              .font(.system(size: adaptiveFontSize(for: geometry, baseSize: 18), weight: .bold))
              .foregroundColor(.white)
          }
        }
        .frame(maxWidth: .infinity)
        .frame(height: adaptiveButtonHeight(for: geometry))
      }
      .buttonStyle(.borderedProminent)
      .tint(.blue)
      .cornerRadius(12)
      .padding(.top, adaptiveSpacing(for: geometry, multiplier: 0.5))
      .disabled(isLoading || email.isEmpty || password.isEmpty)

      // Back button
      Button("Back") {
        isShowingSignIn = false
        email = ""
        password = ""
      }
      .foregroundColor(.white.opacity(0.8))
      .padding(.top, adaptiveSpacing(for: geometry, multiplier: 0.5))
    }
    .padding(adaptiveSpacing(for: geometry))
    .background(Color.black.opacity(0.5))
    .cornerRadius(16)
  }

  // Sign Up view with adaptive layout
  private func signUpView(geometry: GeometryProxy) -> some View {
    VStack(spacing: adaptiveSpacing(for: geometry)) {
      Text("Create Account")
        .font(.system(size: adaptiveFontSize(for: geometry, baseSize: 28), weight: .bold))
        .foregroundColor(.white)
        .padding(.bottom, adaptiveSpacing(for: geometry, multiplier: 0.5))

      // Email field
      VStack(alignment: .leading, spacing: 8) {
        Text("Email")
          .font(.system(size: adaptiveFontSize(for: geometry, baseSize: 16)))
          .foregroundColor(.white)

        TextField("", text: $email)
          .font(.system(size: adaptiveFontSize(for: geometry, baseSize: 16)))
          .padding()
          .background(Color.white.opacity(0.1))
          .cornerRadius(8)
          .foregroundColor(.white)
          .keyboardType(.emailAddress)
          .autocapitalization(.none)
          .disableAutocorrection(true)
      }

      // Password field
      VStack(alignment: .leading, spacing: 8) {
        Text("Password")
          .font(.system(size: adaptiveFontSize(for: geometry, baseSize: 16)))
          .foregroundColor(.white)

        SecureField("", text: $password)
          .font(.system(size: adaptiveFontSize(for: geometry, baseSize: 16)))
          .padding()
          .background(Color.white.opacity(0.1))
          .cornerRadius(8)
          .foregroundColor(.white)

        // Password strength indicator
        VStack(alignment: .leading, spacing: 6) {
          // Password strength bar
          HStack(spacing: 2) {
            Text("Strength: ")
              .font(.system(size: adaptiveFontSize(for: geometry, baseSize: 12)))
              .foregroundColor(.white.opacity(0.7))

            Rectangle()
              .frame(height: 6)
              .frame(width: 120)
              .foregroundColor(passwordStrengthColor(password))
              .cornerRadius(3)
          }

          Text("Password must be at least 8 characters with at least one letter and one number")
            .font(.system(size: adaptiveFontSize(for: geometry, baseSize: 12)))
            .foregroundColor(.white.opacity(0.7))
        }
        .padding(.top, 4)
      }

      // Zip Code field
      VStack(alignment: .leading, spacing: 8) {
        Text("Zip Code")
          .font(.system(size: adaptiveFontSize(for: geometry, baseSize: 16)))
          .foregroundColor(.white)

        TextField("", text: $zipCode)
          .font(.system(size: adaptiveFontSize(for: geometry, baseSize: 16)))
          .padding()
          .background(Color.white.opacity(0.1))
          .cornerRadius(8)
          .foregroundColor(.white)
          .keyboardType(.numberPad)
          .onChange(of: zipCode) { newValue in
            // Limit to 5 digits
            if newValue.count > 5 {
              zipCode = String(newValue.prefix(5))
            }

            // Filter non-numeric characters
            zipCode = newValue.filter { "0123456789".contains($0) }
          }
      }

      // Sign Up Button
      Button(action: performSignUp) {
        ZStack {
          if isLoading {
            ProgressView()
              .progressViewStyle(CircularProgressViewStyle(tint: .white))
              .scaleEffect(1.2)
          } else {
            Text("Create Account")
              .font(.system(size: adaptiveFontSize(for: geometry, baseSize: 18), weight: .bold))
              .foregroundColor(.white)
          }
        }
        .frame(maxWidth: .infinity)
        .frame(height: adaptiveButtonHeight(for: geometry))
      }
      .buttonStyle(.borderedProminent)
      .tint(.green)
      .cornerRadius(12)
      .padding(.top, adaptiveSpacing(for: geometry, multiplier: 0.5))
      .disabled(isLoading || email.isEmpty || password.isEmpty || zipCode.count != 5)

      // Back button
      Button("Back") {
        isShowingSignUp = false
        email = ""
        password = ""
        zipCode = ""
      }
      .foregroundColor(.white.opacity(0.8))
      .padding(.top, adaptiveSpacing(for: geometry, multiplier: 0.5))
    }
    .padding(adaptiveSpacing(for: geometry))
    .background(Color.black.opacity(0.5))
    .cornerRadius(16)
  }

  // Helper function for adaptive button height
  private func adaptiveButtonHeight(for geometry: GeometryProxy) -> CGFloat {
    let screenWidth = geometry.size.width

    if screenWidth > 600 {
      return 65  // Taller buttons on iPad
    }

    return 55  // Standard height on iPhone
  }

  private func performSignIn() {
    // Validate email
    let emailValidation = validateEmail(email)
    if !emailValidation.isValid {
      errorMessage = emailValidation.message ?? "Invalid email address"
      showError = true
      return
    }

    // Validate password (only check if it's not empty for login)
    if password.isEmpty {
      errorMessage = "Please enter your password"
      showError = true
      return
    }

    // Validation passed, proceed with sign in
    isLoading = true
    authState.signIn(email: email, password: password) { result in
      isLoading = false
      switch result {
      case .success(_):
        isShowingSignIn = false
      case .failure(let error):
        errorMessage = error.localizedDescription
        showError = true
      }
    }
  }

  private func performSignUp() {
    // Validate email
    let emailValidation = validateEmail(email)
    if !emailValidation.isValid {
      errorMessage = emailValidation.message ?? "Invalid email address"
      showError = true
      return
    }

    // Validate password
    let passwordValidation = validatePassword(password)
    if !passwordValidation.isValid {
      errorMessage = passwordValidation.message ?? "Invalid password"
      showError = true
      return
    }

    // Validate zip code
    let zipValidation = validateZipCode(zipCode)
    if !zipValidation.isValid {
      errorMessage = zipValidation.message ?? "Invalid zip code"
      showError = true
      return
    }

    // All validations passed, proceed with sign up
    isLoading = true
    authState.signUp(email: email, password: password, zipCode: zipCode) { result in
      isLoading = false
      switch result {
      case .success(_):
        isShowingSignUp = false
      case .failure(let error):
        errorMessage = error.localizedDescription
        showError = true
      }
    }
  }

  private func performAnonymousSignIn() {
    isLoading = true
    authState.signInAnonymously { result in
      isLoading = false
      switch result {
      case .success(_):
        // Anonymous sign-in successful, no need to dismiss any sheets
        break
      case .failure(let error):
        errorMessage = error.localizedDescription
        showError = true
      }
    }
  }

  // MARK: - Input Validation

  private func validateEmail(_ email: String) -> (isValid: Bool, message: String?) {
    // Basic email format validation
    let emailRegex = "^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
    let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)

    if email.isEmpty {
      return (false, "Email address cannot be empty")
    }

    if !emailPredicate.evaluate(with: email) {
      return (false, "Please enter a valid email address (e.g., example@domain.com)")
    }

    return (true, nil)
  }

  private func validatePassword(_ password: String) -> (isValid: Bool, message: String?) {
    // Password requirements - at least 8 characters with at least one number and one letter
    if password.isEmpty {
      return (false, "Password cannot be empty")
    }

    if password.count < 8 {
      return (false, "Password must be at least 8 characters long")
    }

    let hasLetter = password.rangeOfCharacter(from: .letters) != nil
    let hasNumber = password.rangeOfCharacter(from: .decimalDigits) != nil

    if !hasLetter || !hasNumber {
      return (false, "Password must contain at least one letter and one number")
    }

    return (true, nil)
  }

  private func validateZipCode(_ zipCode: String) -> (isValid: Bool, message: String?) {
    if zipCode.isEmpty {
      return (false, "Zip code cannot be empty")
    }

    if zipCode.count != 5 || !zipCode.allSatisfy({ "0123456789".contains($0) }) {
      return (false, "Please enter a valid 5-digit zip code")
    }

    return (true, nil)
  }

  // Returns a color indicating password strength
  private func passwordStrengthColor(_ password: String) -> Color {
    if password.isEmpty {
      return .gray.opacity(0.5)
    }

    // Basic requirements check
    let hasMinLength = password.count >= 8
    let hasLetter = password.rangeOfCharacter(from: .letters) != nil
    let hasNumber = password.rangeOfCharacter(from: .decimalDigits) != nil
    let hasSpecial = password.rangeOfCharacter(from: .punctuationCharacters) != nil

    // Calculate "strength score" 0-4
    var score = 0
    if hasMinLength { score += 1 }
    if hasLetter { score += 1 }
    if hasNumber { score += 1 }
    if hasSpecial { score += 1 }

    switch score {
    case 0: return .gray.opacity(0.5)
    case 1: return .red
    case 2: return .orange
    case 3: return .yellow
    case 4: return .green
    default: return .gray.opacity(0.5)
    }
  }
}

struct AuthView_Previews: PreviewProvider {
  static var previews: some View {
    AuthView()
      .environmentObject(AuthState.shared)
      .environmentObject(NetworkMonitor())
  }
}
