import Photos

public protocol PhotosPermissionManaging {
    func currentReadWriteStatus() -> PHAuthorizationStatus
    func requestReadWriteAccess() async -> PHAuthorizationStatus
}

public final class PhotosPermissionManager: PhotosPermissionManaging {
    public init() {}
    
    public func currentReadWriteStatus() -> PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    public func requestReadWriteAccess() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }
}
