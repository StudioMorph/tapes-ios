import SwiftUI

typealias TapeFrameMap = [UUID: CGRect]

struct TapeFramePreferenceKey: PreferenceKey {
    static var defaultValue: TapeFrameMap = [:]
    static func reduce(value: inout TapeFrameMap, nextValue: () -> TapeFrameMap) {
        value.merge(nextValue()) { _, new in new }
    }
}
