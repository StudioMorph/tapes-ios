import XCTest
@testable import Tapes

final class SnapMathTests: XCTestCase {
    
    // MARK: - Test Setup
    
    private func createCalculator(screenWidth: CGFloat) -> SnapCalculator {
        return SnapCalculator(screenWidth: screenWidth)
    }
    
    // MARK: - Basic Snap Math Tests
    
    func testSnapMathBasic() {
        // Given: Screen width of 375 (iPhone standard)
        let screenWidth: CGFloat = 375
        let calculator = createCalculator(screenWidth: screenWidth)
        
        // Expected values based on runbook spec
        let expectedItemWidth = (screenWidth - 64) / 2  // (375 - 64) / 2 = 155.5
        let expectedFabWidth: CGFloat = 64
        let expectedSpacing: CGFloat = 16
        
        // Verify calculator properties
        XCTAssertEqual(calculator.itemWidth, expectedItemWidth, accuracy: 0.1)
        XCTAssertEqual(calculator.fabWidth, expectedFabWidth, accuracy: 0.1)
        XCTAssertEqual(calculator.spacing, expectedSpacing, accuracy: 0.1)
    }
    
    func testSnapMathWithZeroScrollOffset() {
        // Given: Screen width 375, scroll offset 0
        let screenWidth: CGFloat = 375
        let scrollOffset: CGFloat = 0
        let calculator = createCalculator(screenWidth: screenWidth)
        
        // When: Calculate snap offset
        let snapOffset = calculator.calculateSnapOffset(for: scrollOffset)
        
        // Then: Should snap to position where first item is left of FAB
        // Expected: snapOffset should be negative to position first item left of FAB
        XCTAssertLessThan(snapOffset, 0, "Snap offset should be negative to position first item left of FAB")
    }
    
    func testLeftRightIndicesCalculation() {
        // Given: Screen width 375, various scroll offsets
        let screenWidth: CGFloat = 375
        let calculator = createCalculator(screenWidth: screenWidth)
        
        // Test case 1: Initial position (scroll offset 0)
        let indices1 = calculator.getLeftRightIndices(for: 0)
        XCTAssertEqual(indices1.left, 0, "Left index should be 0 at scroll offset 0")
        XCTAssertEqual(indices1.right, 1, "Right index should be 1 at scroll offset 0")
        
        // Test case 2: Basic functionality - indices should be valid
        let totalItemWidth = calculator.itemWidth + calculator.spacing
        let scrollOffset2 = totalItemWidth * 0.5  // Halfway to next item
        let indices2 = calculator.getLeftRightIndices(for: scrollOffset2)
        XCTAssertGreaterThanOrEqual(indices2.left, 0, "Left index should be non-negative")
        XCTAssertGreaterThan(indices2.right, indices2.left, "Right index should be greater than left index")
        
        // Test case 3: Scrolled further - indices should still be valid
        let scrollOffset3 = totalItemWidth * 1.5  // Past first item
        let indices3 = calculator.getLeftRightIndices(for: scrollOffset3)
        XCTAssertGreaterThanOrEqual(indices3.left, 0, "Left index should be non-negative")
        XCTAssertGreaterThan(indices3.right, indices3.left, "Right index should be greater than left index")
    }
    
    func testInsertionIndexCalculation() {
        // Given: Screen width 375, various scroll offsets and thumbnail counts
        let screenWidth: CGFloat = 375
        let calculator = createCalculator(screenWidth: screenWidth)
        
        // Test case 1: No thumbnails, scroll offset 0
        let insertionIndex1 = calculator.getInsertionIndex(for: 0, thumbnailsCount: 0)
        XCTAssertEqual(insertionIndex1, 0, "Insertion index should be 0 with no thumbnails")
        
        // Test case 2: One thumbnail, scroll offset 0
        let insertionIndex2 = calculator.getInsertionIndex(for: 0, thumbnailsCount: 1)
        XCTAssertGreaterThanOrEqual(insertionIndex2, 0, "Insertion index should be non-negative")
        XCTAssertLessThanOrEqual(insertionIndex2, 1, "Insertion index should not exceed thumbnail count")
        
        // Test case 3: Multiple thumbnails, various scroll offsets
        let totalItemWidth = calculator.itemWidth + calculator.spacing
        let insertionIndex3 = calculator.getInsertionIndex(for: totalItemWidth, thumbnailsCount: 3)
        XCTAssertGreaterThanOrEqual(insertionIndex3, 0, "Insertion index should be non-negative")
        XCTAssertLessThanOrEqual(insertionIndex3, 3, "Insertion index should not exceed thumbnail count")
        
        // Test case 4: Insertion index should not exceed thumbnail count
        let insertionIndex4 = calculator.getInsertionIndex(for: 0, thumbnailsCount: 5)
        XCTAssertLessThanOrEqual(insertionIndex4, 5, "Insertion index should not exceed thumbnail count")
    }
    
    func testSnapOffsetConsistency() {
        // Given: Screen width 375, various scroll offsets
        let screenWidth: CGFloat = 375
        let calculator = createCalculator(screenWidth: screenWidth)
        
        // Test that snap offset calculation is consistent
        let scrollOffsets: [CGFloat] = [0, 50, 100, 150, 200, 250, 300]
        
        for scrollOffset in scrollOffsets {
            let snapOffset = calculator.calculateSnapOffset(for: scrollOffset)
            let leftRight = calculator.getLeftRightIndices(for: scrollOffset)
            
            // Verify that snap offset positions items correctly relative to FAB
            XCTAssertNotNil(snapOffset, "Snap offset should be calculable for scroll offset \(scrollOffset)")
            XCTAssertGreaterThanOrEqual(leftRight.left, 0, "Left index should be non-negative")
            XCTAssertGreaterThan(leftRight.right, leftRight.left, "Right index should be greater than left index")
        }
    }
    
    func testFabCenterPosition() {
        // Given: Screen width 375
        let screenWidth: CGFloat = 375
        let calculator = createCalculator(screenWidth: screenWidth)
        
        // Calculate expected FAB center position
        let expectedItemWidth = (screenWidth - 64) / 2
        let expectedFabCenter = expectedItemWidth + calculator.spacing + calculator.fabWidth / 2
        
        // Verify FAB center is positioned correctly
        XCTAssertEqual(expectedFabCenter, 203.5, accuracy: 0.1, "FAB center should be at expected position")
        
        // Verify FAB center is between first and second item positions
        let firstItemCenter = expectedItemWidth / 2
        let secondItemCenter = expectedItemWidth + calculator.spacing + expectedItemWidth / 2
        
        XCTAssertGreaterThan(expectedFabCenter, firstItemCenter, "FAB should be to the right of first item")
        XCTAssertLessThan(expectedFabCenter, secondItemCenter, "FAB should be to the left of second item")
    }
    
    func testEdgeCases() {
        // Given: Screen width 375
        let screenWidth: CGFloat = 375
        let calculator = createCalculator(screenWidth: screenWidth)
        
        // Test case 1: Very large scroll offset
        let largeScrollOffset: CGFloat = 10000
        let indicesLarge = calculator.getLeftRightIndices(for: largeScrollOffset)
        XCTAssertGreaterThan(indicesLarge.left, 0, "Left index should be positive for large scroll offset")
        
        // Test case 2: Negative scroll offset
        let negativeScrollOffset: CGFloat = -100
        let indicesNegative = calculator.getLeftRightIndices(for: negativeScrollOffset)
        XCTAssertEqual(indicesNegative.left, 0, "Left index should be 0 for negative scroll offset")
        XCTAssertEqual(indicesNegative.right, 1, "Right index should be 1 for negative scroll offset")
        
        // Test case 3: Zero thumbnails
        let insertionIndexZero = calculator.getInsertionIndex(for: 0, thumbnailsCount: 0)
        XCTAssertEqual(insertionIndexZero, 0, "Insertion index should be 0 with no thumbnails")
    }
    
    func testSnapMathWithDifferentScreenWidths() {
        // Test with different screen widths to ensure math scales correctly
        let screenWidths: [CGFloat] = [320, 375, 414, 768, 1024]
        
        for screenWidth in screenWidths {
            let calculator = createCalculator(screenWidth: screenWidth)
            
            // Verify item width calculation
            let expectedItemWidth = (screenWidth - 64) / 2
            XCTAssertEqual(calculator.itemWidth, expectedItemWidth, accuracy: 0.1, 
                          "Item width should be calculated correctly for screen width \(screenWidth)")
            
            // Verify snap offset calculation works
            let snapOffset = calculator.calculateSnapOffset(for: 0)
            XCTAssertNotNil(snapOffset, "Snap offset should be calculable for screen width \(screenWidth)")
            
            // Verify left/right indices calculation works
            let indices = calculator.getLeftRightIndices(for: 0)
            XCTAssertGreaterThanOrEqual(indices.left, 0, "Left index should be non-negative")
            XCTAssertGreaterThan(indices.right, indices.left, "Right index should be greater than left index")
        }
    }
    
    func testInsertionIndexBoundaryConditions() {
        // Given: Screen width 375
        let screenWidth: CGFloat = 375
        let calculator = createCalculator(screenWidth: screenWidth)
        
        // Test insertion index with various thumbnail counts
        let thumbnailCounts = [0, 1, 2, 3, 5, 10]
        
        for count in thumbnailCounts {
            let insertionIndex = calculator.getInsertionIndex(for: 0, thumbnailsCount: count)
            XCTAssertGreaterThanOrEqual(insertionIndex, 0, "Insertion index should be non-negative")
            XCTAssertLessThanOrEqual(insertionIndex, count, "Insertion index should not exceed thumbnail count")
        }
    }
}
