import SwiftUI

struct SavedShapeViewCell: View {
    let shape: ShapeModel
    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(shape.title)
                    .font(.headline)
                Text(shape.shapeType.koreanName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(Self.dateFormatter.string(from: shape.flightStartDate))
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    SavedShapeViewCell(shape: ShapeModel(
        title: "테스트 구역",
        baseCoordinate: CoordinateManager(latitude: 37.56, longitude: 126.97),
        radius: 300,
        memo: "메모 예시",
        address: "서울특별시 어딘가",
        flightEndDate: Date(),
        flightStartDate: Date(),
        color: "#007AFF"
    ))
}
