import SwiftUI

struct ZipCodeEditorView: View {
  let currentZipCode: String
  let onSave: (String) -> Void
  let onCancel: () -> Void

  @State private var newZipCode: String = ""
  @State private var isLoading = false

  var body: some View {
    NavigationView {
      VStack(spacing: 20) {
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
            .onChange(of: newZipCode) { newValue in
              // Limit to 5 digits
              if newValue.count > 5 {
                newZipCode = String(newValue.prefix(5))
              }
              // Only allow numbers
              newZipCode = newValue.filter { $0.isNumber }
            }
        }
        .padding(.horizontal)

        Spacer()

        // Action buttons
        VStack(spacing: 12) {
          Button(action: {
            if isValidZipCode(newZipCode) {
              isLoading = true
              onSave(newZipCode)
            }
          }) {
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

          Button(action: onCancel) {
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
