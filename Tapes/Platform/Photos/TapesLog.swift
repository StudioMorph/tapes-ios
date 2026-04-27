import Foundation
import os

struct TapesLog {
    static let mediaPicker = Logger(subsystem: "com.studiomorph.tapes", category: "MediaPicker")
    static let player = Logger(subsystem: "com.studiomorph.tapes", category: "Player")
    static let store = Logger(subsystem: "com.studiomorph.tapes", category: "Store")
    static let camera = Logger(subsystem: "com.studiomorph.tapes", category: "Camera")
    static let ui = Logger(subsystem: "com.studiomorph.tapes", category: "UI")
    static let photos = Logger(subsystem: "com.studiomorph.tapes", category: "Photos")
    static let export = Logger(subsystem: "com.studiomorph.tapes", category: "Export")
    static let api = Logger(subsystem: "com.studiomorph.tapes", category: "API")
    static let upload = Logger(subsystem: "com.studiomorph.tapes", category: "Upload")
    static let music = Logger(subsystem: "com.studiomorph.tapes", category: "Music")
    static let transfer = Logger(subsystem: "com.studiomorph.tapes", category: "Transfer")
}
