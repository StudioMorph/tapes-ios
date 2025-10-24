import SwiftUI

struct TapeEditOverlayState {
    struct Actions {
        let onSettings: () -> Void
        let onPlay: () -> Void
        let onAirPlay: () -> Void
        let onThumbnailDelete: (Clip) -> Void
        let onClipInserted: (Clip, Int) -> Void
        let onClipInsertedAtPlaceholder: (Clip, CarouselItem) -> Void
        let onMediaInserted: ([PickedMedia], InsertionStrategy) -> Void
    }

    let tapeID: UUID
    let binding: Binding<Tape>
    let frame: CGRect
    let actions: Actions

    var tape: Tape {
        binding.wrappedValue
    }
}
