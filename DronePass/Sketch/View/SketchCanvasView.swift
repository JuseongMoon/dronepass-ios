//
//  SketchCanvasView.swift
//  DronePass
//
//  Created by Claude on 2024.
//

// 역할: 스케치 제스처 핸들러 - 지도에 직접 제스처를 추가하여 스케치 그리기
// 연관기능: 지도 제스처 → 좌표 변환 → SketchManager

import UIKit
import NMapsMap

/// 스케치 제스처 핸들러 - NMFMapView에 직접 제스처를 추가
@MainActor
class SketchGestureHandler: NSObject {
    static let shared = SketchGestureHandler()

    private var panGesture: UIPanGestureRecognizer?
    private var tapGesture: UITapGestureRecognizer?
    private weak var mapView: NMFMapView?
    private let sketchManager = SketchManager.shared

    // 현재 그리기 중인 라인의 프리뷰 오버레이
    private var previewOverlay: NMFPolylineOverlay?

    private override init() {
        super.init()
    }

    // MARK: - Public Methods

    /// 지도에 스케치 제스처 추가
    func attach(to mapView: NMFMapView) {
        // 기존 제스처가 있으면 제거
        detach()

        self.mapView = mapView

        // 1개 터치 드래그용 Pan Gesture (스케치 그리기)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        pan.minimumNumberOfTouches = 1  // 최소 1개 터치
        pan.maximumNumberOfTouches = 1  // 최대 1개 터치
        pan.delegate = self
        mapView.addGestureRecognizer(pan)
        self.panGesture = pan

        // 지도의 기존 팬 제스처가 스케치 팬 실패 후에만 인식하도록 설정
        // → 1손가락: 스케치 그리기, 2손가락: 지도 이동
        for gesture in mapView.gestureRecognizers ?? [] {
            if let existingPan = gesture as? UIPanGestureRecognizer, existingPan != pan {
                existingPan.require(toFail: pan)
            }
        }

        // 1개 터치 탭용 Tap Gesture (지우개 모드)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.delegate = self
        mapView.addGestureRecognizer(tap)
        self.tapGesture = tap

        print("🎨 스케치 제스처 연결됨")
    }

    /// 지도에서 스케치 제스처 제거
    func detach() {
        // require(toFail:) 관계는 제스처 제거 시 자동 해제됨
        if let pan = panGesture, let mapView = mapView {
            mapView.removeGestureRecognizer(pan)
        }
        if let tap = tapGesture, let mapView = mapView {
            mapView.removeGestureRecognizer(tap)
        }
        panGesture = nil
        tapGesture = nil
        mapView = nil
        clearPreviewOverlay()

        print("🎨 스케치 제스처 해제됨")
    }

    // MARK: - Gesture Handlers

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let mapView = mapView else { return }

        let point = gesture.location(in: mapView)
        let latlng = mapView.projection.latlng(from: point)
        let coordinate = CoordinateManager(latitude: latlng.lat, longitude: latlng.lng)

        switch gesture.state {
        case .began:
            // 지우개 모드: 드래그로 삭제
            if sketchManager.isEraserModeActive {
                _ = sketchManager.deleteSketchAtPoint(coordinate)
                return
            }

            // 그리기 시작
            sketchManager.startDrawing(at: coordinate)
            updatePreviewOverlay()
            print("🖊️ 터치 시작: \(latlng.lat), \(latlng.lng)")

        case .changed:
            // 지우개 모드: 드래그 중에도 삭제
            if sketchManager.isEraserModeActive {
                _ = sketchManager.deleteSketchAtPoint(coordinate)
                return
            }

            // 그리기 계속
            sketchManager.continueDrawing(to: coordinate)
            updatePreviewOverlay()

        case .ended:
            // 지우개 모드: 종료 처리 불필요
            if sketchManager.isEraserModeActive {
                return
            }

            // 그리기 종료
            sketchManager.finishDrawing()
            clearPreviewOverlay()
            print("✅ 터치 종료")

        case .cancelled, .failed:
            // 그리기 취소
            if !sketchManager.isEraserModeActive {
                sketchManager.cancelDrawing()
                clearPreviewOverlay()
                print("❌ 터치 취소")
            }

        default:
            break
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let mapView = mapView else { return }

        // 지우개 모드에서 탭으로 삭제
        if sketchManager.isEraserModeActive {
            let point = gesture.location(in: mapView)
            let latlng = mapView.projection.latlng(from: point)
            let coordinate = CoordinateManager(latitude: latlng.lat, longitude: latlng.lng)
            _ = sketchManager.deleteSketchAtPoint(coordinate)
        }
    }

    // MARK: - Preview Overlay

    /// 프리뷰 오버레이 업데이트 (최적화: 오버레이 재사용)
    /// SketchManager의 샘플링된 포인트를 사용하여 손떨림 필터링
    private func updatePreviewOverlay() {
        let sampledPoints = sketchManager.currentDrawingPoints
        guard let mapView = mapView, sampledPoints.count >= 2 else { return }

        // 샘플링된 좌표를 NMGLatLng로 변환
        let coords = sampledPoints.map { NMGLatLng(lat: $0.latitude, lng: $0.longitude) }

        // 스타일 값 (색상, 두께)
        let baseColor = UIColor(hex: sketchManager.currentColor) ?? .red
        let colorWithOpacity = baseColor.withAlphaComponent(CGFloat(sketchManager.currentOpacity))
        let strokeWidth = CGFloat(sketchManager.currentStrokeWidth)

        if let existingOverlay = previewOverlay {
            // 기존 오버레이가 있으면 좌표만 업데이트 (성능 최적화)
            // NMFPolylineOverlay는 points 속성을 직접 재할당해야 함
            existingOverlay.line = NMGLineString(points: coords)
            existingOverlay.color = colorWithOpacity
            existingOverlay.width = strokeWidth
        } else {
            // 최초 생성
            let overlay = NMFPolylineOverlay(coords)
            overlay?.color = colorWithOpacity
            overlay?.width = strokeWidth
            overlay?.globalZIndex = 100 // 스케치는 최상위
            overlay?.mapView = mapView
            previewOverlay = overlay
        }
    }

    /// 프리뷰 오버레이 제거
    private func clearPreviewOverlay() {
        previewOverlay?.mapView = nil
        previewOverlay = nil
    }
}

// MARK: - UIGestureRecognizerDelegate
extension SketchGestureHandler: UIGestureRecognizerDelegate {
    // 핀치 줌만 동시 인식 허용 (지도 확대/축소)
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                          shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // 핀치 줌(UIPinchGestureRecognizer)만 동시 인식 허용
        if otherGestureRecognizer is UIPinchGestureRecognizer {
            return true
        }
        // 다른 팬 제스처와는 동시 인식 불가
        return false
    }
}
