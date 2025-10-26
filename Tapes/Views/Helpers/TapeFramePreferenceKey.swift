import SwiftUI

typealias TapeFrameMap = [UUID: CGRect]

struct TapeFramePreferenceKey: PreferenceKey {
    static var defaultValue: TapeFrameMap = [:]
    static func reduce(value: inout TapeFrameMap, nextValue: () -> TapeFrameMap) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct ViewportFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}
