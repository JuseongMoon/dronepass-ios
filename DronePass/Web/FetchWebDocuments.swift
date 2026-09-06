//
//  FetchWebDocuments.swift
//  DronePass
//
//  Created by 문주성 on 7/23/25.
//

import SwiftUI
import CoreLocation

// MARK: - 마크다운 렌더링을 위한 구조체들
struct MarkdownElement: Identifiable {
    let id = UUID()
    let type: ElementType
    let content: String
    let level: Int? // 헤더 레벨용
    
    enum ElementType {
        case header
        case paragraph
        case table
        case separator
        case list
        case bold
        case italic
    }
}

struct TableData: Identifiable {
    let id = UUID()
    let headers: [String]
    let rows: [[String]]
}

class FetchWebDocuments: NSObject, ObservableObject, CLLocationManagerDelegate  {

    // MARK: - URL 상수
    private static let baseURL = "https://sciencefiction.co.kr/dronepass"

    // 현재 언어 설정에 따라 파일명 반환
    private static func getLocalizedFileName(_ baseName: String, extension fileExtension: String = "txt") -> String {
        let currentLanguage = UserDefaults.standard.string(forKey: "AppLanguage") ?? "ko"

        if currentLanguage == "en" {
            return "\(baseName)_en.\(fileExtension)"
        } else {
            // 한국어는 기존 파일명 사용 (레거시 지원)
            return "\(baseName).\(fileExtension)"
        }
    }

    private static var patchNotesURL: String {
        let fileName = getLocalizedFileName("version-patches")
        return "\(baseURL)/\(fileName)"
    }

    private static var termsURL: String {
        let fileName = getLocalizedFileName("terms/termsofservice")
        return "\(baseURL)/\(fileName)"
    }

    private static var privacyPolicyURL: String {
        let fileName = getLocalizedFileName("terms/privacypolicy")
        return "\(baseURL)/\(fileName)"
    }
    
    // MARK: - 패치노트 관련
    @Published var showPatchNotesSheet = false
    @Published var patchNotes: [PatchNote] = []
    @Published var isLoadingPatchNotes = false
    
    // MARK: - 약관 관련
    @Published var showTermsSheet = false
    @Published var termsContent: String = ""
    @Published var termsElements: [MarkdownElement] = []
    @Published var termsTables: [TableData] = []
    @Published var isLoadingTerms = false
    
    // MARK: - 개인정보 취급방침 관련
    @Published var showPrivacyPolicySheet = false
    @Published var privacyPolicyContent: String = ""
    @Published var privacyPolicyElements: [MarkdownElement] = []
    @Published var privacyPolicyTables: [TableData] = []
    @Published var isLoadingPrivacyPolicy = false
    
    // MARK: - 마크다운 파싱 메서드들
    
    private func parseMarkdown(_ content: String) -> ([MarkdownElement], [TableData]) {
        var elements: [MarkdownElement] = []
        var tables: [TableData] = []
        
        let lines = content.components(separatedBy: .newlines)
        var i = 0
        
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            
            // 빈 줄 건너뛰기
            if line.isEmpty {
                i += 1
                continue
            }
            
            // 헤더 처리
            if line.hasPrefix("#") {
                let level = line.prefix(while: { $0 == "#" }).count
                let headerText = String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces)
                elements.append(MarkdownElement(type: .header, content: headerText, level: level))
            }
            // 구분선 처리
            else if line.hasPrefix("---") {
                elements.append(MarkdownElement(type: .separator, content: "", level: nil))
            }
            // 표 처리
            else if line.contains("|") && i + 1 < lines.count && lines[i + 1].contains("|") {
                let (tableData, nextIndex) = parseTable(lines: lines, startIndex: i)
                if let table = tableData {
                    tables.append(table)
                    elements.append(MarkdownElement(type: .table, content: table.id.uuidString, level: nil))
                }
                i = nextIndex
                continue
            }
            // 리스트 처리
            else if line.hasPrefix("-") || line.hasPrefix("•") {
                let listText = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                elements.append(MarkdownElement(type: .list, content: listText, level: nil))
            }
            // 일반 단락 처리
            else {
                elements.append(MarkdownElement(type: .paragraph, content: line, level: nil))
            }
            
            i += 1
        }
        
        return (elements, tables)
    }
    
    private func parseTable(lines: [String], startIndex: Int) -> (TableData?, Int) {
        var i = startIndex
        var tableLines: [String] = []
        
        // 표 라인들 수집
        while i < lines.count && lines[i].contains("|") {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            // 헤더 구분선 건너뛰기 (|---|--- 형태)
            if !line.contains("---") {
                tableLines.append(line)
            }
            i += 1
        }
        
        guard tableLines.count >= 2 else { return (nil, i) }
        
        // 헤더 파싱
        let headerLine = tableLines[0]
        let headers = headerLine.components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        // 데이터 행 파싱
        var rows: [[String]] = []
        for j in 1..<tableLines.count {
            let rowLine = tableLines[j]
            let rowData = rowLine.components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            
            if !rowData.isEmpty {
                rows.append(rowData)
            }
        }
        
        let tableData = TableData(headers: headers, rows: rows)
        return (tableData, i)
    }
    
    struct Feature: Identifiable, Hashable {
        let id = UUID()
        let title: String
        var description: String?
    }
    
    struct PatchNote: Identifiable, Hashable {
        let id = UUID()
        let version: String
        let date: String
        let title: String
        let features: [Feature]
    }
    
    func fetchAndShowPatchNotes() {
        showPatchNotesSheet = true

        Task {
            await fetchPatchNotes()
        }
    }

    private func fetchPatchNotes() async {
        await MainActor.run {
            isLoadingPatchNotes = true
        }

        defer {
            Task {
                await MainActor.run {
                    isLoadingPatchNotes = false
                }
            }
        }

        guard let url = URL(string: Self.patchNotesURL) else {
            print("Invalid URL")
            return
        }

        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let content = String(data: data, encoding: .utf8) else {
                print("Failed to decode data")
                return
            }

            let parsedNotes = parsePatchNotes(content: content)
            await MainActor.run {
                self.patchNotes = parsedNotes
            }
        } catch {
            print("Failed to fetch patch notes: \(error)")
        }
    }

    private func parsePatchNotes(content: String) -> [PatchNote] {
        var allNotes: [PatchNote] = []
        
        let notesTextBlocks = content.components(separatedBy: "\nv")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { text in text.hasPrefix("v") ? text : "v" + text }

        for noteText in notesTextBlocks {
            let lines = noteText.components(separatedBy: .newlines)
            guard let headerLine = lines.first else { continue }

            let headerContentSplit = headerLine.components(separatedBy: ": ")
            guard headerContentSplit.count > 1 else { continue }
            
            let header = headerContentSplit.first ?? ""
            let title = headerContentSplit.dropFirst().joined(separator: ": ")
            
            let versionDateSplit = header.components(separatedBy: CharacterSet(charactersIn: "()"))
            let version = versionDateSplit.first?.trimmingCharacters(in: .whitespaces) ?? "N/A"
            let date = versionDateSplit.count > 1 ? versionDateSplit[1] : "N/A"

            var currentNoteFeatures: [Feature] = []
            let featureLines = lines.dropFirst()

            for line in featureLines {
                let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                if trimmedLine.isEmpty { continue }

                if line.hasPrefix("    -") { // Indented: Description
                    if !currentNoteFeatures.isEmpty {
                        let descriptionText = String(trimmedLine.dropFirst().trimmingCharacters(in: .whitespaces))
                        let lastIndex = currentNoteFeatures.count - 1
                        
                        // Append to existing description or create a new one
                        if let existingDescription = currentNoteFeatures[lastIndex].description {
                            currentNoteFeatures[lastIndex].description = existingDescription + "\n" + descriptionText
                        } else {
                            currentNoteFeatures[lastIndex].description = descriptionText
                        }
                    }
                } else if trimmedLine.hasPrefix("-") { // Not indented: New Feature
                    let featureTitle = String(trimmedLine.dropFirst().trimmingCharacters(in: .whitespaces))
                    currentNoteFeatures.append(Feature(title: featureTitle, description: nil))
                }
            }
            allNotes.append(PatchNote(version: version, date: date, title: title, features: currentNoteFeatures))
        }
        return allNotes
    }
    
    // MARK: - 이용약관 불러오기
    
    func fetchAndShowTerms() {
        // 데이터가 이미 로드되었다면 다시 로드하지 않고 시트만 보여줍니다.
        if !termsElements.isEmpty {
            showTermsSheet = true
            return
        }
        
        Task {
            await fetchTerms()
            await MainActor.run {
                self.showTermsSheet = true
            }
        }
    }
    
    func fetchTerms() async {
        await MainActor.run {
            isLoadingTerms = true
        }

        defer {
            Task {
                await MainActor.run {
                    isLoadingTerms = false
                }
            }
        }

        guard let url = URL(string: Self.termsURL) else {
            print("Invalid Terms URL")
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let content = String(data: data, encoding: .utf8) else {
                print("Failed to decode terms data")
                return
            }
            
            let (elements, tables) = parseMarkdown(content)
            await MainActor.run {
                self.termsContent = content
                self.termsElements = elements
                self.termsTables = tables
            }
        } catch {
            print("Failed to fetch terms: \(error)")
        }
    }
    
    // MARK: - 개인정보 취급방침 불러오기
    
    func fetchAndShowPrivacyPolicy() {
        // 데이터가 이미 로드되었다면 다시 로드하지 않고 시트만 보여줍니다.
        if !privacyPolicyElements.isEmpty {
            showPrivacyPolicySheet = true
            return
        }
        
        Task {
            await fetchPrivacyPolicy()
            await MainActor.run {
                self.showPrivacyPolicySheet = true
            }
        }
    }
    
    func fetchPrivacyPolicy() async {
        await MainActor.run {
            isLoadingPrivacyPolicy = true
        }

        defer {
            Task {
                await MainActor.run {
                    isLoadingPrivacyPolicy = false
                }
            }
        }

        guard let url = URL(string: Self.privacyPolicyURL) else {
            print("Invalid Privacy Policy URL")
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let content = String(data: data, encoding: .utf8) else {
                print("Failed to decode privacy policy data")
                return
            }
            
            let (elements, tables) = parseMarkdown(content)
            await MainActor.run {
                self.privacyPolicyContent = content
                self.privacyPolicyElements = elements
                self.privacyPolicyTables = tables
            }
        } catch {
            print("Failed to fetch privacy policy: \(error)")
        }
    }
}
