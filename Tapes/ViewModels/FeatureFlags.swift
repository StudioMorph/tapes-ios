import Foundation

enum FeatureFlags {
    /// Controls whether deleting a Tape also deletes its associated Photos album.
    /// Default is `false` to avoid changing current behaviour until the feature is fully vetted.
    static var deleteAssociatedPhotoAlbum: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "FeatureFlag.deleteAssociatedPhotoAlbum")
        #else
        return false
        #endif
    }
}
