//
//  ToastMessageModifier.swift
//  Groobean
//
//  Created by 최명수 on 2025/9/18.
//

import SwiftUI

// MARK: - 토스트 메세지를 출력하기 위한 커스텀 뷰 모디파이어
// 사용하려는 뷰에 토스트 메세지의 표시 여부를 저장하는 Bool 타입 상태 값과 토스트 메세지 내용을 저장하는 String 타입 상태 값을 선언한 뒤,
// 해당 뷰에 .toastMessage(isPresented: 선언한 Bool 값 바인딩, message: 선언한 String 값 바인딩, duration: 표시 시간) 모디파이어 적용
// message에 연결된 상태 값에 원하는 내용을 저장한 뒤, isPresented에 연결된 상태 값을 true로 변경하면 토스트 메세지가 duration 동안 표시됨
// isPresented 값을 true로 설정하기 전에 isPresented 값을 false로 설정했다가 변경하여 기존에 표시 중인 메세지를 제거해야 함
struct ToastMessageModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var message: String
    let duration: TimeInterval
    
    // 비동기적으로 토스트 메세지를 제거할 때 기존 비동기 작업을 관리하기 위한 상태 값
    @State private var workItem: DispatchWorkItem?
    
    func body(content: Content) -> some View {
        ZStack {
            content
            if isPresented {
                VStack {
                    Spacer()
                    Text(message)
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(12)
                        .padding(.bottom, 100)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onAppear {
                            // 이전 비동기 작업 취소
                            workItem?.cancel()
                            
                            // 토스트 메세지 제거를 위한 새로운 작업 등록
                            let newWorkItem = DispatchWorkItem {
                                withAnimation {
                                    isPresented = false
                                }
                            }
                            self.workItem = newWorkItem
                            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: newWorkItem)
                        }
                }
                .animation(.easeInOut, value: isPresented)
            }
        }
    }
}

// 원하는 뷰에서 바로 사용 가능하도록 모디파이어로 정의
extension View {
    func toastMessage(isPresented: Binding<Bool>, message: Binding<String>, duration: TimeInterval = 2) -> some View {
        self.modifier(ToastMessageModifier(isPresented: isPresented, message: message, duration: duration))
    }
}
