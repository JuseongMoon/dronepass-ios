import SwiftUI

struct PrivacyPolicyView: View {
    @StateObject private var fetcher = FetchWebDocuments()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // 고정된 헤더
            HStack {
                Text(NSLocalizedString("terms.privacy.title", comment: "Privacy Policy"))
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(NSLocalizedString("appInfo.close", comment: "Close")) {
                    dismiss()
                }
                .font(.body)
                .foregroundColor(.blue)
            }
            .padding(.horizontal)
            .padding(.vertical, 16)
            .background(Color(.systemBackground))
            .overlay(
                Rectangle()
                    .frame(height: 0.5)
                    .foregroundColor(Color(.separator)),
                alignment: .bottom
            )
            
            // 스크롤 가능한 콘텐츠
            ScrollView {
                if fetcher.isLoadingPrivacyPolicy {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            ProgressView(NSLocalizedString("terms.loading", comment: "Loading..."))
                                .progressViewStyle(.circular)
                            Spacer()
                        }
                        Spacer()
                    }
                    .frame(minHeight: 300)
                } else if fetcher.privacyPolicyElements.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary)
                        Text(NSLocalizedString("terms.privacy.error.title", comment: "Unable to load privacy policy"))
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text(NSLocalizedString("terms.privacy.error.message", comment: "Please try again later"))
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        
                        Button(NSLocalizedString("terms.retry", comment: "Retry")) {
                            Task {
                                await fetcher.fetchPrivacyPolicy()
                            }
                        }
                        .buttonStyle(.bordered)
                        .padding(.top, 8)
                        Spacer()
                    }
                    .frame(minHeight: 300)
                    .padding()
                } else {
                    MarkdownView(
                        elements: fetcher.privacyPolicyElements,
                        tables: fetcher.privacyPolicyTables
                    )
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
        }
        .background(Color(.systemBackground))
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            if fetcher.privacyPolicyElements.isEmpty {
                Task {
                    await fetcher.fetchPrivacyPolicy()
                }
            }
        }
    }
}

#Preview {
    PrivacyPolicyView()
} 
