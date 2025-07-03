import SwiftUI

struct ReportVideoView: View {
    @Binding var isPresented: Bool
    let onSubmit: (String, String) -> Void
    let onCancel: () -> Void
    
    @State private var email = ""
    @State private var selectedReason = "Inappropriate"
    @State private var isSubmitting = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    private let reasons = ["Inappropriate", "Misleading", "Harmful", "Other"]
    
    var isValid: Bool {
        !email.isEmpty && email.contains("@") && !selectedReason.isEmpty
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header section
                    VStack(spacing: 8) {
                        Text("Report Video")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        Text("Please provide your email and select a reason for reporting")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }
                    .padding(.top, 20)
                    
                    // Email input section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your Email Address")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        TextField("Enter your email", text: $email)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .font(.body)
                    }
                    .padding(.horizontal, 20)
                    
                    // Reason selection section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Reason for Reporting")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .padding(.horizontal, 20)
                        
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 12) {
                            ForEach(reasons, id: \.self) { reason in
                                Button(action: {
                                    selectedReason = reason
                                }) {
                                    HStack {
                                        Image(systemName: selectedReason == reason ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(selectedReason == reason ? .blue : .gray)
                                        
                                        Text(reason)
                                            .font(.body)
                                            .foregroundColor(.primary)
                                        
                                        Spacer()
                                    }
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(selectedReason == reason ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(selectedReason == reason ? Color.blue : Color.gray.opacity(0.3), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    Spacer(minLength: 40)
                    
                    // Action buttons
                    VStack(spacing: 16) {
                        Button(action: {
                            submitReport()
                        }) {
                            HStack {
                                if isSubmitting {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                } else {
                                    Text("Submit Report")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(isValid && !isSubmitting ? Color.red : Color.gray)
                            .cornerRadius(12)
                        }
                        .disabled(!isValid || isSubmitting)
                        
                        Button(action: {
                            onCancel()
                            isPresented = false
                        }) {
                            Text("Cancel")
                                .font(.headline)
                                .foregroundColor(.blue)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.blue, lineWidth: 1)
                                )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .navigationBarHidden(true)
            .background(Color(.systemBackground))
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
    
    private func submitReport() {
        guard isValid else { return }
        
        isSubmitting = true
        
        // Validate email format
        if !isValidEmail(email) {
            errorMessage = "Please enter a valid email address"
            showError = true
            isSubmitting = false
            return
        }
        
        // Submit the report
        onSubmit(email, selectedReason)
        
        // Reset form and close
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isSubmitting = false
            isPresented = false
        }
    }
    
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
}

struct ReportVideoView_Previews: PreviewProvider {
    static var previews: some View {
        ReportVideoView(
            isPresented: .constant(true),
            onSubmit: { email, reason in
                print("Report submitted: \(email), \(reason)")
            },
            onCancel: {
                print("Report cancelled")
            }
        )
    }
} 