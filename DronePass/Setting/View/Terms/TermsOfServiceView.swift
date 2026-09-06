import SwiftUI

struct TermsOfServiceView: View {
    @StateObject private var fetcher = FetchWebDocuments()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // 고정된 헤더
            HStack {
                Text(NSLocalizedString("terms.service.title", comment: "Terms of Service"))
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
                if fetcher.isLoadingTerms {
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
                } else if fetcher.termsElements.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary)
                        Text(NSLocalizedString("terms.service.error.title", comment: "Unable to load terms"))
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text(NSLocalizedString("terms.service.error.message", comment: "Please try again later"))
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        
                        Button(NSLocalizedString("terms.retry", comment: "Retry")) {
                            Task {
                                await fetcher.fetchTerms()
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
                        elements: fetcher.termsElements,
                        tables: fetcher.termsTables
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
            if fetcher.termsElements.isEmpty {
                Task {
                    await fetcher.fetchTerms()
                }
            }
        }
    }
}

#Preview {
    TermsOfServiceView()
} 
