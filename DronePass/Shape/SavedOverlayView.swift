import SwiftUI

struct SavedOverlayView: View {
    @Binding var isPresented: Bool
    @Binding var selectedShapeID: UUID?
    @State private var shapeIDToScrollTo: UUID?
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 드래그 핸들
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 40, height: 4)
                .cornerRadius(2)
                .padding(.top, 8)
                .gesture(
                    DragGesture()
                        .onChanged { gesture in
                            if !isDragging {
                                isDragging = true
                            }
                            dragOffset = gesture.translation.height
                        }
                        .onEnded { gesture in
                            isDragging = false
                            if gesture.translation.height > 50 {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    isPresented = false
                                }
                            }
                            dragOffset = 0
                        }
                )
            
            // 헤더
            HStack {
                Text(String(localized: "common.savedItems"))
                    .font(.headline)
                Spacer()
                Button(action: {
                    isPresented = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
            .padding()
            
            // 리스트
            SavedTableListView(
                selectedShapeID: $selectedShapeID,
                shapeIDToScrollTo: $shapeIDToScrollTo
            )
        }
        .offset(y: dragOffset)
        .animation(.interactiveSpring(), value: isDragging)
    }
} 