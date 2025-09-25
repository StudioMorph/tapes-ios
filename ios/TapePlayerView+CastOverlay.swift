import SwiftUI

struct TapePlayer_CastOverlay: View {
    @StateObject private var cast = CastManager.shared
    var body: some View {
        HStack {
            Spacer()
            if cast.hasAvailableDevices {
                AirPlayButton()
                    .frame(width: 28, height: 28)
                    .padding(.trailing, 12)
            }
        }
        .padding(.top, 8)
    }
}
