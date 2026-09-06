//
//  NotiName.swift
//  DronePass
//
//  Created by 문주성 on 5/26/25.
//

import Foundation

extension Notification.Name {
//    static let SwiftUIShapeSelected = Notification.Name("SwiftUIShapeSelected")
//    static let UIKitShapeSelected = Notification.Name("UIKitShapeSelected")
    static let shapesDidUpdate = Notification.Name("shapesDidUpdate")
    static let shapesDidChange = Notification.Name("shapesDidChange")

    // 드론 관련 알림
    static let dronesDidChange = Notification.Name("DronesDidChange")
    static let droneSelectionChanged = Notification.Name("DroneSelectionChanged")
    static let droneFilterChanged = Notification.Name("DroneFilterChanged")
    static let droneHighlightChanged = Notification.Name("DroneHighlightChanged")
}
