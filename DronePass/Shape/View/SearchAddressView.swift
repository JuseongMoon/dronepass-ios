//
//  SearchingAddressView.swift
//  DronePass
//
//  Created by 문주성 on 6/18/25.
//

import SwiftUI
import Combine
import Foundation
import MapKit





struct SearchAddressView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = SearchAddressViewModel()
    @State private var searchText = ""
    
    var onSelectAddress: ((NaverDetailAddress) -> Void)?
    
    init(onSelectAddress: ((NaverDetailAddress) -> Void)? = nil) {
        self.onSelectAddress = onSelectAddress
    }
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 0) {
                // 검색 바
                SearchBar(
                    text: $searchText,
                    placeholder: String(localized: "address.search.placeholder"),
                    onSubmit: {
                        Task {
                            await viewModel.searchAddress(query: searchText)
                        }
                    },
                    onClear: {
                        searchText = ""
                        viewModel.searchText = ""
                    }
                )
                .padding(.horizontal)
                .padding(.top, 8)
                
                if viewModel.isSearching {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage = viewModel.errorMessage {
                    ErrorView(message: errorMessage)
                } else if viewModel.addresses.isEmpty {
                    // 검색 결과가 없을 때 안내 메시지 표시
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "address.search.guide"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Text(String(localized: "address.search.example"))
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Group {
                            Text("• 서초대로78길 24 (도로명)")
                            Text("• 서초동 1305-6 (지번)")
                            Text("• 테헤란로 322 (도로명)")
                            Text("• 역삼동 679-4 (지번)")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(maxWidth: 500) // Adjust max width as desired
                    .background(Color(.systemGray6))
                    .cornerRadius(20)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal)
                    .padding(.top)
                    
                    
                    Spacer()
                } else {
                    AddressListView(
                        addresses: viewModel.addresses,
                        onSelect: { address in
                            onSelectAddress?(address)
                            dismiss()
                        }
                    )
                }
            }
            .navigationTitle(String(localized: "address.search.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(String(localized: "common.cancel")) {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Supporting Views
struct SearchBar: View {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void
    var onClear: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                TextField(placeholder, text: $text)
                    .textFieldStyle(PlainTextFieldStyle())
                    .submitLabel(.search)
                    .onSubmit(onSubmit)
                
                if !text.isEmpty {
                    Button(action: onClear) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(8)
            .background(Color(.systemGray6))
            .cornerRadius(8)
            
            Button(action: onSubmit) {
                Text(String(localized: "common.search"))
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .disabled(text.isEmpty)
        }
    }
}

struct AddressListView: View {
    let addresses: [NaverDetailAddress]
    let onSelect: (NaverDetailAddress) -> Void
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(addresses, id: \.roadAddress) { address in
                    AddressCardView(address: address)
                        .onTapGesture {
                            onSelect(address)
                        }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct AddressCardView: View {
    let address: NaverDetailAddress

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 지번 주소
            HStack(alignment: .top, spacing: 8) {
                Text(String(localized: "address.type.jibun"))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue)
                    .cornerRadius(6)

                Text(address.jibunAddress)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // 도로명 주소
            HStack(alignment: .top, spacing: 8) {
                Text(String(localized: "address.type.road"))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green)
                    .cornerRadius(6)

                Text(address.roadAddress)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // 건물명 (있는 경우)
            if let buildingName = address.buildingName, !buildingName.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "building.2")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(buildingName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.systemGray5), lineWidth: 1)
        )
    }
}

struct ErrorView: View {
    let message: String
    
    var body: some View {
        VStack {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.red)
                .padding()
            
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundColor(.red)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    SearchAddressView(
        onSelectAddress: { address in
            print("Selected address: \(address.roadAddress)")
        }
    )
}
