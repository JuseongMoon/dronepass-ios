//
//  KPInfoView.swift
//  DronePass
//
//  Created by Claude Code
//

import SwiftUI

/// KP 지수 정보 설명 뷰
struct KPInfoView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // KP 지수란? 섹션
                    kpIndexInfoSection

                    // 레벨별 설명 섹션
                    levelDescriptionSection
                }
                .padding()
            }
            .navigationTitle(NSLocalizedString("kpInfo.navigation.title", comment: "KP Index Information"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("kpInfo.close", comment: "Close")) {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - KP 지수란? 섹션

    private var kpIndexInfoSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text(NSLocalizedString("kpInfo.section.what", comment: "What is KP Index?"))
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 16) {
                // 기본 설명
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("kpInfo.what.text1", comment: "KP Index description"))
                        .font(.body)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(NSLocalizedString("kpInfo.what.bullet1", comment: "Range description"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(NSLocalizedString("kpInfo.what.bullet2", comment: "Measurement description"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                }

                Divider()

                // 드론과의 관계
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("kpInfo.section.relation", comment: "Relationship with Drone Flight"))
                        .font(.body)
                        .fontWeight(.semibold)

                    Text(NSLocalizedString("kpInfo.relation.text", comment: "GPS impact description"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(NSLocalizedString("kpInfo.relation.bullet1", comment: "GPS accuracy degradation"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(NSLocalizedString("kpInfo.relation.bullet2", comment: "Position tracking errors"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(NSLocalizedString("kpInfo.relation.bullet3", comment: "RTH accuracy"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .font(.subheadline)
                            .foregroundColor(.red)
                        Text(NSLocalizedString("kpInfo.relation.bullet4", comment: "KP 5+ caution"))
                            .font(.subheadline)
                            .foregroundColor(.red)
                            .fontWeight(.medium)
                    }
                }

                Divider()

                // 데이터 출처 및 차이점
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("kpInfo.section.source", comment: "Data Sources"))
                        .font(.body)
                        .fontWeight(.semibold)

                    Text(NSLocalizedString("kpInfo.source.text", comment: "Two organizations"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("•")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text(NSLocalizedString("kpInfo.source.gfz", comment: "GFZ description"))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("•")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text(NSLocalizedString("kpInfo.source.noaa", comment: "NOAA description"))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.leading, 8)

                    Text(NSLocalizedString("kpInfo.source.difference", comment: "Why values differ"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fontWeight(.semibold)
                        .padding(.top, 4)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(NSLocalizedString("kpInfo.source.reason1", comment: "Station differences"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, 8)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(NSLocalizedString("kpInfo.source.reason2", comment: "Update interval"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, 8)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(NSLocalizedString("kpInfo.source.reason3", comment: "Forecast values"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, 8)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("💡")
                            .font(.caption)
                        Text(NSLocalizedString("kpInfo.source.note", comment: "Values usually similar"))
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .padding(.top, 4)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(16)
        }
    }

    // MARK: - 레벨별 설명 섹션

    private var levelDescriptionSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text(NSLocalizedString("kpInfo.section.levels", comment: "Geomagnetic Storm Scale"))
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
            }

            VStack(spacing: 12) {
                // Normal 레벨
                levelCard(
                    level: .normal,
                    range: NSLocalizedString("kpInfo.level.normal.range", comment: "KP = 0 ~ 4"),
                    description: NSLocalizedString("kpInfo.level.normal.desc", comment: "Low geomagnetic activity"),
                    droneAdvice: NSLocalizedString("kpInfo.level.normal.advice", comment: "Safe flight possible")
                )

                // G1 레벨
                levelCard(
                    level: .g1,
                    range: NSLocalizedString("kpInfo.level.g1.range", comment: "KP = 5"),
                    description: NSLocalizedString("kpInfo.level.g1.desc", comment: "Minor geomagnetic storm"),
                    droneAdvice: NSLocalizedString("kpInfo.level.g1.advice", comment: "Generally safe")
                )

                // G2 레벨
                levelCard(
                    level: .g2,
                    range: NSLocalizedString("kpInfo.level.g2.range", comment: "KP = 6"),
                    description: NSLocalizedString("kpInfo.level.g2.desc", comment: "Moderate geomagnetic storm"),
                    droneAdvice: NSLocalizedString("kpInfo.level.g2.advice", comment: "Caution recommended")
                )

                // G3 레벨
                levelCard(
                    level: .g3,
                    range: NSLocalizedString("kpInfo.level.g3.range", comment: "KP = 7"),
                    description: NSLocalizedString("kpInfo.level.g3.desc", comment: "Strong geomagnetic storm"),
                    droneAdvice: NSLocalizedString("kpInfo.level.g3.advice", comment: "Flight caution needed")
                )

                // G4 레벨
                levelCard(
                    level: .g4,
                    range: NSLocalizedString("kpInfo.level.g4.range", comment: "KP = 8"),
                    description: NSLocalizedString("kpInfo.level.g4.desc", comment: "Severe geomagnetic storm"),
                    droneAdvice: NSLocalizedString("kpInfo.level.g4.advice", comment: "Avoid flight recommended")
                )

                // G5 레벨
                levelCard(
                    level: .g5,
                    range: NSLocalizedString("kpInfo.level.g5.range", comment: "KP = 9"),
                    description: NSLocalizedString("kpInfo.level.g5.desc", comment: "Extreme geomagnetic storm"),
                    droneAdvice: NSLocalizedString("kpInfo.level.g5.advice", comment: "GPS unusable")
                )
            }
        }
    }

    // MARK: - Helper Views

    private func levelCard(level: KPLevel, range: String, description: String, droneAdvice: String) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // 아이콘
                Image(systemName: level.icon)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(level.color)
                    .frame(width: 50)

                VStack(alignment: .leading, spacing: 4) {
                    // 레벨 이름
                    Text(level.localizedName)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(level.color)

                    // KP 범위
                    Text("\(range)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                // 의미 설명
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // 드론 비행 권장사항
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•")
                        .font(.subheadline)
                        .foregroundColor(level == .g5 || level == .g4 || level == .g3 ? .red : .secondary)
                    Text(droneAdvice)
                        .font(.subheadline)
                        .foregroundColor(level == .g5 || level == .g4 || level == .g3 ? .red : .secondary)
                        .fontWeight(level == .g5 || level == .g4 || level == .g3 ? .medium : .regular)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(level.color.opacity(0.1))
        .cornerRadius(16)
    }
}

#Preview {
    KPInfoView()
}
