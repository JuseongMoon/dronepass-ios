import SwiftUI

struct AppInfoView: View {
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            List {
                // 앱 소개 섹션
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Spacer()
                            Image(systemName: "airplane.circle.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.blue, .cyan],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            Spacer()
                        }

                        Text(AppInfo.Description.intro)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal)
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text(NSLocalizedString("appInfo.section.intro", comment: "About the App"))
                        .font(.headline)
                }

                // 드론 관리 기능
                Section {
                    FeatureRow(
                        icon: "paperplane.circle.fill",
                        iconColor: .blue,
                        title: NSLocalizedString("appInfo.feature.multiDrone.title", comment: "Multi-Drone Management"),
                        description: NSLocalizedString("appInfo.feature.multiDrone.description", comment: "Register and manage multiple drones")
                    )

                    FeatureRow(
                        icon: "map.circle.fill",
                        iconColor: .green,
                        title: NSLocalizedString("appInfo.feature.visualization.title", comment: "Drone Flight Zone Visualization"),
                        description: NSLocalizedString("appInfo.feature.visualization.description", comment: "Display drone flight permitted areas on map")
                    )

                    FeatureRow(
                        icon: "bell.circle.fill",
                        iconColor: .orange,
                        title: NSLocalizedString("appInfo.feature.expirationAlert.title", comment: "Expiration-Based Notifications"),
                        description: NSLocalizedString("appInfo.feature.expirationAlert.description", comment: "Automatic notification 7 days before flight end date")
                    )
                } header: {
                    Text(NSLocalizedString("appInfo.section.droneManagement", comment: "Drone Management"))
                        .font(.headline)
                }

                // 환경 정보 기능
                Section {
                    FeatureRow(
                        icon: "cloud.sun.fill",
                        iconColor: .cyan,
                        title: NSLocalizedString("appInfo.feature.weather.title", comment: "Real-Time Weather Information"),
                        description: NSLocalizedString("appInfo.feature.weather.description", comment: "Wind direction, speed, gusts, dew point risk index, etc.")
                    )

                    FeatureRow(
                        icon: "antenna.radiowaves.left.and.right",
                        iconColor: .purple,
                        title: NSLocalizedString("appInfo.feature.kpIndex.title", comment: "KP Index Monitoring"),
                        description: NSLocalizedString("appInfo.feature.kpIndex.description", comment: "Geomagnetic activity index affecting GPS accuracy")
                    )

                    FeatureRow(
                        icon: "sunrise.fill",
                        iconColor: .pink,
                        title: NSLocalizedString("appInfo.feature.sunriseSunset.title", comment: "Sunrise/Sunset Info and Notifications"),
                        description: NSLocalizedString("appInfo.feature.sunriseSunset.description", comment: "Sunrise/sunset times and notifications for current location")
                    )
                } header: {
                    Text(NSLocalizedString("appInfo.section.environmentalInfo", comment: "Environmental Information"))
                        .font(.headline)
                }

                // 도형 및 지도 기능
                Section {
                    FeatureRow(
                        icon: "circle.circle.fill",
                        iconColor: .indigo,
                        title: NSLocalizedString("appInfo.feature.shapeManagement.title", comment: "Radius-Based Shape Creation and Management"),
                        description: NSLocalizedString("appInfo.feature.shapeManagement.description", comment: "Create/edit circles, rectangles, polygons, lines")
                    )

                    FeatureRow(
                        icon: "doc.on.doc.fill",
                        iconColor: .teal,
                        title: NSLocalizedString("appInfo.feature.shapeDuplicate.title", comment: "Shape Duplication and Alignment"),
                        description: NSLocalizedString("appInfo.feature.shapeDuplicate.description", comment: "Copy shapes and various alignment options")
                    )

                    FeatureRow(
                        icon: "magnifyingglass.circle.fill",
                        iconColor: .mint,
                        title: NSLocalizedString("appInfo.feature.search.title", comment: "Address Search and Navigation"),
                        description: NSLocalizedString("appInfo.feature.search.description", comment: "Search locations by address and navigation")
                    )
                } header: {
                    Text(NSLocalizedString("appInfo.section.shapesAndMap", comment: "Shapes and Map"))
                        .font(.headline)
                }

                // 클라우드 및 동기화
                Section {
                    FeatureRow(
                        icon: "icloud.fill",
                        iconColor: .blue,
                        title: NSLocalizedString("appInfo.feature.cloudSync.title", comment: "Cloud Real-Time Synchronization"),
                        description: NSLocalizedString("appInfo.feature.cloudSync.description", comment: "Real-time data synchronization across multiple devices")
                    )

                    FeatureRow(
                        icon: "checkmark.seal.fill",
                        iconColor: .green,
                        title: NSLocalizedString("appInfo.feature.droneOnestop.title", comment: "Drone One-Stop Integration"),
                        description: NSLocalizedString("appInfo.feature.droneOnestop.description", comment: "Data structure for drone one-stop service integration")
                    )
                } header: {
                    Text(NSLocalizedString("appInfo.section.cloudAndData", comment: "Cloud and Data"))
                        .font(.headline)
                }

                // 버전 정보 섹션
                Section {
                    HStack {
                        Label(NSLocalizedString("appInfo.version.app", comment: "App Version"), systemImage: "info.circle")
                            .foregroundColor(.primary)
                        Spacer()
                        Text(AppInfo.Version.current)
                            .foregroundColor(.secondary)
                            .fontWeight(.medium)
                    }

                    HStack {
                        Label(NSLocalizedString("appInfo.version.build", comment: "Build Number"), systemImage: "number.circle")
                            .foregroundColor(.primary)
                        Spacer()
                        Text(AppInfo.Version.buildNumber)
                            .foregroundColor(.secondary)
                            .fontWeight(.medium)
                    }
                } header: {
                    Text(NSLocalizedString("appInfo.section.version", comment: "Version Info"))
                        .font(.headline)
                }

                // 연락처 정보 섹션
                Section {
                    let contactInfo = AppInfo.Description.contact.components(separatedBy: "\n")
                    let companyName = contactInfo.first ?? ""
                    let email = contactInfo.count > 1 ? contactInfo[1] : ""

                    if !companyName.isEmpty {
                        HStack {
                            Label(companyName, systemImage: "building.2.fill")
                                .foregroundColor(.primary)
                            Spacer()
                        }
                    }

                    if !email.isEmpty, let emailURL = URL(string: "mailto:\(email)") {
                        Link(destination: emailURL) {
                            HStack {
                                Label(email, systemImage: "envelope.fill")
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text(NSLocalizedString("appInfo.section.contact", comment: "Contact"))
                        .font(.headline)
                } footer: {
                    Text(NSLocalizedString("appInfo.contact.message", comment: "Please feel free to contact us with any questions."))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle(NSLocalizedString("appInfo.title", comment: "App Info"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("appInfo.close", comment: "Close")) {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Feature Row Component
struct FeatureRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(iconColor)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview
struct AppInfoView_Previews: PreviewProvider {
    static var previews: some View {
        AppInfoView()
    }
}
