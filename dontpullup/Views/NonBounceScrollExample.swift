import SwiftUI

/// A simple example view that demonstrates scrolling without the bounce effect
struct NonBounceScrollExample: View {
  var body: some View {
    NoBounceScrollView {
      VStack(spacing: 24) {
        Text("No-Bounce Scroll Example")
          .font(.title)
          .fontWeight(.bold)
          .padding()

        Text(
          "This view demonstrates scrolling without the rubber-band bounce effect. Try scrolling to the top or bottom and notice how it stops cleanly without bouncing."
        )
        .padding()
        .multilineTextAlignment(.center)

        // Outer scroll view with no bounce
        Group {
          Text("Main Content Area (No Bounce):")
            .font(.headline)
            .padding(.bottom, 4)

          ForEach(1...20, id: \.self) { index in
            Text("Item \(index)")
              .frame(maxWidth: .infinity)
              .padding()
              .background(Color.blue.opacity(0.2))
              .cornerRadius(8)
          }
        }
        .padding(.horizontal)

        // Nested scroll view example
        VStack {
          Text("Nested Scroll View (Also No Bounce):")
            .font(.headline)
            .padding(.bottom, 4)

          NoBounceScrollView {
            VStack(spacing: 20) {
              ForEach(21...30, id: \.self) { index in
                Text("Nested Item \(index)")
                  .frame(maxWidth: .infinity)
                  .padding()
                  .background(Color.green.opacity(0.2))
                  .cornerRadius(8)
              }
            }
            .padding()
          }
          .frame(height: 300)
          .background(Color.gray.opacity(0.1))
          .cornerRadius(12)
        }
        .padding()

        Text("Implementation Details")
          .font(.headline)
          .padding(.top, 16)

        Text(
          "This uses a UIViewRepresentable wrapper around UIScrollView with bounces=false to disable the rubber-band effect while maintaining momentum scrolling."
        )
        .padding()
        .multilineTextAlignment(.center)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal)

        Spacer(minLength: 40)
      }
    }
    .navigationTitle("No-Bounce Scroll")
  }
}

#Preview {
  NonBounceScrollExample()
}
