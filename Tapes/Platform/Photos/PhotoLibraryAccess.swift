import Foundation
import Photos

public protocol PhotoLibraryAccessing {
    func authorizationStatus(for accessLevel: PHAccessLevel) -> PHAuthorizationStatus
    func requestAuthorization(for accessLevel: PHAccessLevel) async -> PHAuthorizationStatus
    func performChanges(_ changes: @escaping () -> Void) async throws
    func performChangesAndWait(_ changes: @escaping () -> Void) throws
    func fetchAssetCollections(withLocalIdentifiers identifiers: [String]) -> PHFetchResult<PHAssetCollection>
    func fetchAssetCollections(with type: PHAssetCollectionType, subtype: PHAssetCollectionSubtype, options: PHFetchOptions?) -> PHFetchResult<PHAssetCollection>
}

public final class PhotoLibraryAccess: PhotoLibraryAccessing {
    public init() {}
    
    public func authorizationStatus(for accessLevel: PHAccessLevel) -> PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: accessLevel)
    }
    
    public func requestAuthorization(for accessLevel: PHAccessLevel) async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: accessLevel) { status in
                continuation.resume(returning: status)
            }
        }
    }
    
    public func performChanges(_ changes: @escaping () -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges(changes) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: NSError(domain: "PhotoLibraryAccess", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown Photos change failure"]))
                }
            }
        }
    }
    
    public func performChangesAndWait(_ changes: @escaping () -> Void) throws {
        try PHPhotoLibrary.shared().performChangesAndWait(changes)
    }
    
    public func fetchAssetCollections(withLocalIdentifiers identifiers: [String]) -> PHFetchResult<PHAssetCollection> {
        PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: identifiers, options: nil)
    }
    
    public func fetchAssetCollections(with type: PHAssetCollectionType, subtype: PHAssetCollectionSubtype, options: PHFetchOptions?) -> PHFetchResult<PHAssetCollection> {
        PHAssetCollection.fetchAssetCollections(with: type, subtype: subtype, options: options)
    }
}
