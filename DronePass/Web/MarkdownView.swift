//
//  MarkdownView.swift
//  DronePass
//
//  Created by 문주성 on 7/23/25.
//

import SwiftUI

struct MarkdownView: View {
    let elements: [MarkdownElement]
    let tables: [TableData]
    
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            ForEach(elements) { element in
                switch element.type {
                case .header:
                    HeaderView(text: element.content, level: element.level ?? 1)
                case .paragraph:
                    ParagraphView(text: element.content)
                case .table:
                    if let tableId = UUID(uuidString: element.content),
                       let table = tables.first(where: { $0.id == tableId }) {
                        TableView(tableData: table)
                    }
                case .separator:
                    SeparatorView()
                case .list:
                    ListItemView(text: element.content)
                case .bold, .italic:
                    ParagraphView(text: element.content)
                }
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - 개별 요소 뷰들

struct HeaderView: View {
    let text: String
    let level: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(parseInlineMarkdown(text))
                .font(headerFont)
                .fontWeight(headerWeight)
                .foregroundColor(.primary)
            
            if level <= 2 {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.3))
                    .frame(height: level == 1 ? 3 : 2)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, headerPadding)
    }
    
    private var headerFont: Font {
        switch level {
        case 1: return .title.bold()
        case 2: return .title2.bold()
        case 3: return .title3.bold()
        default: return .headline.bold()
        }
    }
    
    private var headerWeight: Font.Weight {
        switch level {
        case 1: return .bold
        case 2: return .bold
        case 3: return .semibold
        default: return .semibold
        }
    }
    
    private var headerPadding: CGFloat {
        switch level {
        case 1: return 12
        case 2: return 10
        case 3: return 8
        default: return 6
        }
    }
}

struct ParagraphView: View {
    let text: String
    
    var body: some View {
        Text(parseInlineMarkdown(text))
            .font(.body)
            .lineSpacing(4)
            .foregroundColor(.primary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct TableView: View {
    let tableData: TableData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 헤더
            HStack(spacing: 0) {
                ForEach(Array(tableData.headers.enumerated()), id: \.offset) { index, header in
                    Text(header)
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
//                        .background(Color(.systemGray5))
                        .overlay(
                            Rectangle()
                                .fill(Color(.separator))
                                .frame(width: 0.5),
                            alignment: .trailing
                        )
                }
            }
            .overlay(
                Rectangle()
                    .fill(Color(.separator))
                    .frame(height: 0.5),
                alignment: .bottom
            )
            
            // 데이터 행들
            ForEach(Array(tableData.rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { columnIndex, cell in
                        Text(parseInlineMarkdown(cell))
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.systemBackground))
                            .overlay(
                                Rectangle()
                                    .fill(Color(.separator))
                                    .frame(width: 0.5),
                                alignment: .trailing
                            )
                        
                        // 셀이 부족한 경우 빈 셀 추가
                        if columnIndex == row.count - 1 && row.count < tableData.headers.count {
                            ForEach(0..<(tableData.headers.count - row.count), id: \.self) { _ in
                                Text("")
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(.systemBackground))
                                    .overlay(
                                        Rectangle()
                                            .fill(Color(.separator))
                                            .frame(width: 0.5),
                                        alignment: .trailing
                                    )
                            }
                        }
                    }
                }
                .overlay(
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(height: 0.5),
                    alignment: .bottom
                )
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(.separator), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.vertical, 4)
    }
}

struct SeparatorView: View {
    var body: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
    }
}

struct ListItemView: View {
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(.body.bold())
                .foregroundColor(.accentColor)
                .padding(.top, 2)
            
            Text(parseInlineMarkdown(text))
                .font(.body)
                .lineSpacing(3)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 8)
    }
}

// MARK: - 인라인 마크다운 파싱 헬퍼

private func parseInlineMarkdown(_ text: String) -> AttributedString {
    do {
        // iOS 15+ AttributedString 마크다운 지원 활용
        let attributedString = try AttributedString(markdown: text, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        return attributedString
    } catch {
        // 마크다운 파싱 실패 시 일반 텍스트로 반환
        return AttributedString(text)
    }
}

//#Preview {
//    ScrollView {
//        MarkdownView(
//            elements: [
//                MarkdownElement(type: .header, content: "테스트 제목", level: 1),
//                MarkdownElement(type: .paragraph, content: "이것은 **볼드** 텍스트와 *이탤릭* 텍스트가 포함된 단락입니다."),
//                MarkdownElement(type: .separator, content: "", level: nil),
//                MarkdownElement(type: .list, content: "첫 번째 항목"),
//                MarkdownElement(type: .list, content: "두 번째 항목")
//            ],
//            tables: []
//        )
//    }
//} 
