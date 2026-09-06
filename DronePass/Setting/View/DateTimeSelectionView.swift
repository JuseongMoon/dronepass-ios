
//
//  DateTimeSelectionView.swift
//  DronePass
//
//  Created by 문주성 on 6/27/25.
//

import SwiftUI

struct DateTimeSelectionView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var selectedDate: Date
    var isDateOnly: Bool
    var title: String

    var body: some View {
        NavigationView {
            VStack {
                DatePicker(
                    title,
                    selection: $selectedDate,
                    displayedComponents: isDateOnly ? .date : [.date, .hourAndMinute]
                )
                .datePickerStyle(.graphical) // 그래픽 스타일 유지
                .labelsHidden() // 레이블 숨기기

                Spacer()

                Button(NSLocalizedString("dateTime.done", comment: "Done")) {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .padding()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("common.cancel", comment: "Cancel")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    DateTimeSelectionView(selectedDate: .constant(Date()), isDateOnly: false, title: "날짜/시간 선택")
}
