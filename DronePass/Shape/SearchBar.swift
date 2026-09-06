import SwiftUI

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
                Text("검색")
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

#Preview {
    SearchBar(
        text: .constant(""),
        placeholder: "검색어를 입력하세요",
        onSubmit: {},
        onClear: {}
    )
} 