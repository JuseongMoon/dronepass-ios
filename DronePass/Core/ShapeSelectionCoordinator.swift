//
//  ShapeSelectionCoordinator.swift
//  DronePass
//
//  Created by 문주성 on 5/13/25.
//

import Foundation // Foundation 프레임워크를 가져옵니다. (기본적인 데이터 타입과 기능을 사용하기 위함)
import CoreLocation // CoreLocation 프레임워크를 가져옵니다. (위치 관련 기능을 사용하기 위함)

final class ShapeSelectionCoordinator { // 도형 선택을 관리하는 코디네이터 클래스입니다.
    static let shared = ShapeSelectionCoordinator() // 싱글톤 인스턴스를 생성합니다.
    private init() {} // 외부에서 인스턴스 생성을 막기 위해 초기화 메서드를 private으로 설정합니다.

    static let shapeSelectedOnList = Notification.Name("shapeSelectedOnList") // 리스트에서 도형이 선택되었을 때 사용할 알림 이름을 정의합니다.
    static let shapeSelectedOnMap = Notification.Name("shapeSelectedOnMap") // 지도에서 도형이 선택되었을 때 사용할 알림 이름을 정의합니다.

    func selectShapeOnList(_ shape: ShapeModel) { // 리스트에서 도형이 선택되었을 때 호출되는 메서드입니다.
        NotificationCenter.default.post(name: Self.shapeSelectedOnList, object: shape) // 선택된 도형 정보를 포함한 알림을 전송합니다.
    }

    func selectShapeOnMap(_ shape: ShapeModel) { // 지도에서 도형이 선택되었을 때 호출되는 메서드입니다.
        NotificationCenter.default.post(name: Self.shapeSelectedOnMap, object: shape) // 선택된 도형 정보를 포함한 알림을 전송합니다.
    }
} 
