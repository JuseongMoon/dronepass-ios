//
//  CopyableTextModifier.swift
//  DronePass
//
//  Created by Claude on 2025-10-12.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Copyable Text Modifier

/// 텍스트를 길게 눌러 클립보드에 복사할 수 있는 modifier
/// 햅틱 피드백과 토스트 메시지 포함
struct CopyableTextModifier: ViewModifier {
    let text: String?
    @Binding var showToast: Bool
    @Binding var toastMessage: String

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onLongPressGesture {
                guard let text = text, !text.isEmpty else { return }

                // 클립보드에 복사
                UIPasteboard.general.string = text

                // 햅틱 피드백
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)

                // 토스트 메시지 표시
                toastMessage = NSLocalizedString("common.copied", comment: "Copied")
                withAnimation {
                    showToast = true
                }

                // 1.5초 후 토스트 숨김
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation {
                        showToast = false
                    }
                }
            }
    }
}

// MARK: - View Extension

extension View {
    /// 텍스트를 길게 눌러 클립보드에 복사할 수 있도록 만듭니다
    /// - Parameters:
    ///   - text: 복사할 텍스트 (nil이면 복사 불가)
    ///   - showToast: 토스트 표시 여부를 관리하는 Binding
    ///   - toastMessage: 토스트 메시지를 관리하는 Binding
    /// - Returns: 수정된 View
    func copyableText(
        _ text: String?,
        showToast: Binding<Bool>,
        toastMessage: Binding<String>
    ) -> some View {
        modifier(CopyableTextModifier(
            text: text,
            showToast: showToast,
            toastMessage: toastMessage
        ))
    }
}

// MARK: - Toast Overlay

/// 복사 완료 토스트 메시지 오버레이
struct CopyToastOverlay: ViewModifier {
    @Binding var showToast: Bool
    let message: String

    func body(content: Content) -> some View {
        content
            .overlay(
                VStack {
                    Spacer()
                    if showToast {
                        Text(message)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.75))
                            )
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .padding(.bottom, 50)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: showToast)
            )
    }
}

extension View {
    /// 복사 완료 토스트 메시지를 표시합니다
    /// - Parameters:
    ///   - showToast: 토스트 표시 여부
    ///   - message: 표시할 메시지
    /// - Returns: 수정된 View
    func copyToast(showToast: Binding<Bool>, message: String) -> some View {
        modifier(CopyToastOverlay(showToast: showToast, message: message))
    }
}
