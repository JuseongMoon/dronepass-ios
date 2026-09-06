import SwiftUI

struct LocationTermsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(NSLocalizedString("terms.location.title", comment: "Location-Based Service Terms"))
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.bottom, 8)
                Text(NSLocalizedString("terms.location.content", comment: "Location-Based Service Terms Content"))
                    .font(.body)
            }
            .padding()
        }
        .navigationTitle(NSLocalizedString("terms.location.title", comment: "Location-Based Service Terms"))
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemBackground))
    }
}

#Preview {
    LocationTermsView()
} 
