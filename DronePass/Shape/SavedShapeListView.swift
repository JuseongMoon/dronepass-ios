//
//  SavedShapeListView.swift
//  DronePass
//
//  Created by 문주성 on 6/11/25.
//

import SwiftUI

struct SavedShapeListView: View {
    @Environment(\.dismiss) private var dismiss
    @GestureState private var dragState = DragState.inactive
    @State private var position: CGFloat = 400 // 고정값 사용
    @State private var selectedShapeID: UUID?
    @State private var shapeIDToScrollTo: UUID?
    
    private let dismissThreshold: CGFloat = 100
    
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
            // 상단 헤더 영역
            VStack(spacing: 0) {
                Text(NSLocalizedString("saved.list.title", comment: "Saved List"))
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
    SavedShapeListView()
} 