//
//  SavedShapeBottomSheetView.swift
//  DronePass
//
//  Created by 문주성 on 6/11/25.
//

import SwiftUI

struct SavedShapeBottomSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @GestureState private var dragState = DragState.inactive
    @State private var position: CGFloat = 400 // 고정값 사용
    @State private var selectedShapeID: UUID? = nil
    @State private var shapeIDToScrollTo: UUID? = nil

    private let dismissThreshold: CGFloat = 100
    private let minHeight: CGFloat = 200
    private let midHeight: CGFloat = 400
    private let maxHeight: CGFloat = 600 // 고정값 사용
    
    enum DragState {
        case inactive
        case dragging(translation: CGFloat)
        
        var translation: CGFloat {
            switch self {
            case .inactive:
                return 0
            case .dragging(let translation):
                return translation
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 드래그 핸들
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color(UIColor.systemGray3))
                .frame(width: 40, height: 5)
                .padding(.top, 12)
                .padding(.bottom, 8)
            
            // 상단 헤더 영역
            VStack(spacing: 0) {
                Text(NSLocalizedString("saved.bottomSheet.title", comment: "Saved Shapes List"))
                    .font(.system(size: 16, weight: .medium))
                    .frame(height: 44)
            }
            .frame(maxWidth: .infinity)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .gesture(
                DragGesture()
                    .updating($dragState) { value, state, _ in
                        state = .dragging(translation: value.translation.height)
                    }
                    .onEnded { value in
                        if value.translation.height > dismissThreshold {
                            dismiss()
                        }
                    }
            )
            
            // 나머지 컨텐츠
            SavedTableListView(
                selectedShapeID: $selectedShapeID,
                shapeIDToScrollTo: $shapeIDToScrollTo
            )
        }
        .offset(y: dragState.translation)
        .animation(.interactiveSpring(), value: dragState.translation)
    }
}

#Preview {
    SavedShapeBottomSheetView()
} 
