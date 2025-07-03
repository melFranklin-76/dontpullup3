import SwiftUI

struct ZipCodeEditorView: View {
  let currentZipCode: String
  let onSave: (String) -> Void
  let onCancel: () -> Void

  @State private var newZipCode: String = ""
  @State private var isLoading = false
  @Environment(\.dismiss) private var dismiss
  @FocusState private var isInputFocused: Bool

  var body: some View {
    NavigationView {
      VStack(spacing: 20) {
        // Close button
        HStack {
          Spacer()
          Button(action: {
            // First remove focus from text field to avoid keyboard issues
            isInputFocused = false
            // Use a slight delay to ensure keyboard dismissal before view dismissal
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
              dismiss()
              onCancel()
            }
          }) {
            Image(systemName: "xmark.circle.fill")
              .font(.title2)
              .foregroundColor(.white.opacity(0.7))
          }
        }
        .padding(.horizontal)
        .padding(.top, 10)

        // Header
        VStack(spacing: 8) {
          Image(systemName: "location.circle.fill")
            .font(.system(size: 50))
            .foregroundColor(.blue)

          Text("Change Zip Code")
            .font(.title2)
            .fontWeight(.bold)
            .foregroundColor(.white)

          Text("Premium users can change their zip code to view incidents from different areas")
            .font(.caption)
            .foregroundColor(.gray)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
        }
        .padding(.top, 20)

        // Current zip code
        VStack(alignment: .leading, spacing: 8) {
          Text("Current Zip Code")
            .font(.caption)
            .foregroundColor(.gray)

          Text(currentZipCode)
            .font(.title3)
            .foregroundColor(.white)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.gray.opacity(0.2))
            .cornerRadius(8)
        }
        .padding(.horizontal)

        // New zip code input
        VStack(alignment: .leading, spacing: 8) {
          Text("New Zip Code")
            .font(.caption)
            .foregroundColor(.gray)

          TextField("Enter 5-digit zip code", text: $newZipCode)
            .keyboardType(.numberPad)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .disabled(isLoading)
            .focused($isInputFocused)
            .onChange(of: newZipCode) { newValue in
              // Limit to 5 digits
              if newValue.count > 5 {
                newZipCode = String(newValue.prefix(5))
              }
              // Only allow numbers
              newZipCode = newValue.filter { $0.isNumber }

              // Auto-save when 5 digits are entered
              if newZipCode.count == 5 && isValidZipCode(newZipCode) && !isLoading {
                saveAndDismiss()
              }
            }
        }
        .padding(.horizontal)

        Spacer()

        // Action buttons
        VStack(spacing: 12) {
          Button(action: saveAndDismiss) {
            HStack {
              if isLoading {
                ProgressView()
                  .progressViewStyle(CircularProgressViewStyle(tint: .white))
                  .scaleEffect(0.8)
              }
              Text(isLoading ? "Updating..." : "Update Zip Code")
                .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(isValidZipCode(newZipCode) ? Color.blue : Color.gray)
            .foregroundColor(.white)
            .cornerRadius(12)
          }
          .disabled(!isValidZipCode(newZipCode) || isLoading)

          Button(action: {
            // First remove focus from text field
            isInputFocused = false
            // Use a slight delay to ensure keyboard dismissal
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
              dismiss()
              onCancel()
            }
          }) {
            Text("Cancel")
              .fontWeight(.medium)
              .frame(maxWidth: .infinity)
              .frame(height: 50)
              .background(Color.clear)
              .foregroundColor(.gray)
              .overlay(
                RoundedRectangle(cornerRadius: 12)
                  .stroke(Color.gray, lineWidth: 1)
              )
          }
          .disabled(isLoading)
        }
        .padding(.horizontal)
        .padding(.bottom, 30)
      }
      .background(Color.black)
      .navigationBarHidden(true)
    }
    .onAppear {
      newZipCode = currentZipCode
      // Delay focusing to avoid keyboard issues
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        isInputFocused = true
      }
    }
  }

  private func saveAndDismiss() {
    guard isValidZipCode(newZipCode) && !isLoading else { return }

    // Remove focus from the text field first
    isInputFocused = false

    print("[ZipCodeEditorView] Saving zip code: \(newZipCode)")
    isLoading = true

    // Call the save callback
    onSave(newZipCode)

    // Prevent Metal texture rendering errors by using proper animation timing
    // First delay allows the loading state to be visible
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      // Disable loading state before dismissal to prevent animation conflicts
      self.isLoading = false

      // Second delay ensures UI is settled before dismissal
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        print("[ZipCodeEditorView] Dismissing view")
        self.dismiss()

        // Final delay ensures view is fully dismissed before updating parent state
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
          self.onCancel()
        }
      }
    }
  }

  private func isValidZipCode(_ zipCode: String) -> Bool {
    return zipCode.count == 5 && zipCode.allSatisfy { $0.isNumber } && zipCode != currentZipCode
  }
}

#Preview {
  ZipCodeEditorView(
    currentZipCode: "53212",
    onSave: { _ in },
    onCancel: {}
  )
}
