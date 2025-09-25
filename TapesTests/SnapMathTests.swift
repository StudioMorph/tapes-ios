import XCTest
@testable import Tapes

final class SnapMathTests: XCTestCase {
    
    func testNearestGapIndex() {
        // Test case 1: Container width 300, gaps at [50, 150, 250]
        let gapCenters1: [CGFloat] = [50, 150, 250]
        let containerWidth1: CGFloat = 300
        let result1 = nearestGapIndex(containerWidth: containerWidth1, gapCenters: gapCenters1)
        XCTAssertEqual(result1, 1, "Should return index 1 (gap at 150) as it's closest to center (150)")
        
        // Test case 2: Container width 200, gaps at [30, 80, 130, 180]
        let gapCenters2: [CGFloat] = [30, 80, 130, 180]
        let containerWidth2: CGFloat = 200
        let result2 = nearestGapIndex(containerWidth: containerWidth2, gapCenters: gapCenters2)
        XCTAssertEqual(result2, 1, "Should return index 1 (gap at 80) as it's closest to center (100)")
        
        // Test case 3: Container width 400, gaps at [100, 200, 300]
        let gapCenters3: [CGFloat] = [100, 200, 300]
        let containerWidth3: CGFloat = 400
        let result3 = nearestGapIndex(containerWidth: containerWidth3, gapCenters: gapCenters3)
        XCTAssertEqual(result3, 1, "Should return index 1 (gap at 200) as it's closest to center (200)")
        
        // Test case 4: Single gap
        let gapCenters4: [CGFloat] = [150]
        let containerWidth4: CGFloat = 300
        let result4 = nearestGapIndex(containerWidth: containerWidth4, gapCenters: gapCenters4)
        XCTAssertEqual(result4, 0, "Should return index 0 for single gap")
        
        // Test case 5: Edge case - gap at exact center
        let gapCenters5: [CGFloat] = [50, 100, 150]
        let containerWidth5: CGFloat = 200
        let result5 = nearestGapIndex(containerWidth: containerWidth5, gapCenters: gapCenters5)
        XCTAssertEqual(result5, 1, "Should return index 1 (gap at 100) as it's exactly at center (100)")
    }
    
    func testNearestGapIndexEdgeCases() {
        // Test case: Empty gaps array
        let gapCenters: [CGFloat] = []
        let containerWidth: CGFloat = 300
        let result = nearestGapIndex(containerWidth: containerWidth, gapCenters: gapCenters)
        XCTAssertEqual(result, 0, "Should return 0 for empty gaps array")
        
        // Test case: Very small container
        let gapCenters2: [CGFloat] = [10, 20, 30]
        let containerWidth2: CGFloat = 20
        let result2 = nearestGapIndex(containerWidth: containerWidth2, gapCenters: gapCenters2)
        XCTAssertEqual(result2, 0, "Should return index 0 for very small container")
    }
}

// MARK: - Helper Function
/// Pure function to find the nearest gap index
/// - Parameters:
///   - containerWidth: Width of the container
///   - gapCenters: Array of gap center X positions
/// - Returns: Index of the nearest gap to the container center
func nearestGapIndex(containerWidth: CGFloat, gapCenters: [CGFloat]) -> Int {
    guard !gapCenters.isEmpty else { return 0 }
    
    let containerCenter = containerWidth / 2
    
    var nearestIndex = 0
    var minDistance = abs(gapCenters[0] - containerCenter)
    
    for (index, gapCenter) in gapCenters.enumerated() {
        let distance = abs(gapCenter - containerCenter)
        if distance < minDistance {
            minDistance = distance
            nearestIndex = index
        }
    }
    
    return nearestIndex
}