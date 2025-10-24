import Foundation
import Photos

public struct TapeAlbumAssociation {
    let albumLocalIdentifier: String
    let created: Bool
}

public enum TapeAlbumServiceError: LocalizedError {
    case unauthorized
    case albumCreationFailed
    case albumNotFound
    case assetFetchFailed
    case changeRequestFailed(String)
    case insufficientPermissions
    
    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Photos permission is required."
        case .albumCreationFailed:
            return "Failed to create Photos album."
        case .albumNotFound:
            return "Photos album not found."
        case .assetFetchFailed:
            return "Failed to fetch assets for Photos album."
        case .changeRequestFailed(let reason):
            return reason
        case .insufficientPermissions:
            return "Full Photos access is required to update the album title."
        }
    }
}

public protocol TapeAlbumServicing {
    func ensureAlbum(for tape: Tape) async throws -> TapeAlbumAssociation
    func addAssets(withIdentifiers assetLocalIds: [String], to albumLocalIdentifier: String) async throws
    func deleteAlbum(withLocalIdentifier localIdentifier: String) async throws
    /// Returns a new album identifier if the rename operation creates a replacement album.
    func renameAlbum(withLocalIdentifier localIdentifier: String, toMatch tape: Tape) async throws -> String?
}

public final class TapeAlbumService: TapeAlbumServicing {
    private let photoLibrary: PhotoLibraryAccessing
    private let permissionManager: PhotosPermissionManaging
    private let albumTitlePrefix = "Tapes – "
    
    public init(
        photoLibrary: PhotoLibraryAccessing = PhotoLibraryAccess(),
        permissionManager: PhotosPermissionManaging = PhotosPermissionManager()
    ) {
        self.photoLibrary = photoLibrary
        self.permissionManager = permissionManager
    }
    
    public func ensureAlbum(for tape: Tape) async throws -> TapeAlbumAssociation {
        try await requireAuthorization(for: .addOnly)
        
        if let localIdentifier = tape.albumLocalIdentifier,
           let existing = fetchAlbum(localIdentifier: localIdentifier) {
            TapesLog.photos.debug("Reusing existing album for tape \(tape.id.uuidString, privacy: .public)")
            var identifier = existing.localIdentifier
            if existing.localizedTitle != albumTitle(for: tape) {
                do {
                    if let renamedIdentifier = try await renameAlbum(withLocalIdentifier: identifier, toMatch: tape) {
                        identifier = renamedIdentifier
                    }
                } catch TapeAlbumServiceError.insufficientPermissions {
                    TapesLog.photos.warning("Cannot rename album for tape \(tape.id.uuidString, privacy: .public) without full Photos access.")
                }
                catch {
                    throw error
                }
            }
            return TapeAlbumAssociation(albumLocalIdentifier: identifier, created: false)
        }

        let newIdentifier = try await createAlbum(named: albumTitle(for: tape))
        TapesLog.photos.info("Created Photos album \(newIdentifier, privacy: .public) for tape \(tape.id.uuidString, privacy: .public)")
        return TapeAlbumAssociation(albumLocalIdentifier: newIdentifier, created: true)
    }
    
    public func addAssets(withIdentifiers assetLocalIds: [String], to albumLocalIdentifier: String) async throws {
        guard !assetLocalIds.isEmpty else { return }
        try await requireAuthorization(for: .addOnly)
        
        guard let album = fetchAlbum(localIdentifier: albumLocalIdentifier) else {
            TapesLog.photos.error("Album not found for identifier \(albumLocalIdentifier, privacy: .public)")
            throw TapeAlbumServiceError.albumNotFound
        }
        
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: assetLocalIds, options: nil)
        guard assets.count > 0 else {
            TapesLog.photos.error("No assets fetched for identifiers: \(assetLocalIds.joined(separator: ","), privacy: .public)")
            throw TapeAlbumServiceError.assetFetchFailed
        }
        if assets.count < assetLocalIds.count {
            TapesLog.photos.warning("Partial asset fetch for album add. Requested: \(assetLocalIds.count, privacy: .public) | Retrieved: \(assets.count, privacy: .public)")
        }
        
        var fetchedAssets: [PHAsset] = []
        fetchedAssets.reserveCapacity(assets.count)
        assets.enumerateObjects { asset, _, _ in
            fetchedAssets.append(asset)
        }
        
        var changeError: TapeAlbumServiceError?
        try await photoLibrary.performChanges {
            guard let changeRequest = PHAssetCollectionChangeRequest(for: album) else {
                changeError = .changeRequestFailed("Could not obtain change request for album.")
                return
            }
            changeRequest.addAssets(fetchedAssets as NSArray)
        }
        if let changeError {
            throw changeError
        }
    }
    
    public func deleteAlbum(withLocalIdentifier localIdentifier: String) async throws {
        guard !localIdentifier.isEmpty else { return }
        try await requireAuthorization(for: .readWrite)
        
        guard let album = fetchAlbum(localIdentifier: localIdentifier) else {
            TapesLog.photos.warning("Attempted to delete missing album \(localIdentifier, privacy: .public)")
            return
        }
        
        try await photoLibrary.performChanges {
            PHAssetCollectionChangeRequest.deleteAssetCollections([album] as NSArray)
        }
        TapesLog.photos.info("Deleted Photos album \(localIdentifier, privacy: .public)")
    }
    
    public func renameAlbum(withLocalIdentifier localIdentifier: String, toMatch tape: Tape) async throws -> String? {
        guard !localIdentifier.isEmpty else { return nil }
        
        let initialStatus = permissionManager.currentReadWriteStatus()
        let accessStatus: PHAuthorizationStatus
        if initialStatus == .notDetermined {
            accessStatus = await permissionManager.requestReadWriteAccess()
        } else {
            accessStatus = initialStatus
        }
        
        guard accessStatus == .authorized else {
            TapesLog.photos.warning("Unable to rename album \(localIdentifier, privacy: .public); read/write authorization status is \(accessStatus.rawValue, privacy: .public).")
            throw TapeAlbumServiceError.insufficientPermissions
        }
        
        let newTitle = albumTitle(for: tape)
        TapesLog.photos.info("Preparing to rename album \(localIdentifier, privacy: .public) to \(newTitle, privacy: .public).")
        guard let album = fetchAlbum(localIdentifier: localIdentifier) else {
            TapesLog.photos.warning("Attempted to rename missing album \(localIdentifier, privacy: .public)")
            throw TapeAlbumServiceError.albumNotFound
        }
        
        if album.localizedTitle == newTitle {
            TapesLog.photos.info("Album \(localIdentifier, privacy: .public) already has title \(newTitle, privacy: .public); skipping rename.")
            return nil
        }
        
        var changeError: TapeAlbumServiceError?
        if #available(iOS 15.0, *) {
            try await photoLibrary.performChanges {
                guard let changeRequest = PHAssetCollectionChangeRequest(for: album) else {
                    changeError = .changeRequestFailed("Could not obtain change request for album rename.")
                    return
                }
                changeRequest.title = newTitle
            }
            if changeError == nil {
                TapesLog.photos.info("Renamed Photos album \(localIdentifier, privacy: .public) to \(newTitle, privacy: .public)")
                return nil
            }
            // Fall through to recreation fallback if the change request failed.
        }

        // Fallback: create a new album with the desired title, mirror existing assets, then delete the old album.
        if let changeError {
            TapesLog.photos.warning("Rename via change request failed for album \(localIdentifier, privacy: .public): \(changeError.localizedDescription, privacy: .public). Recreating album instead.")
        }
        var assetIdentifiers: [String] = []
        let assetFetch = PHAsset.fetchAssets(in: album, options: nil)
        assetFetch.enumerateObjects { asset, _, _ in
            assetIdentifiers.append(asset.localIdentifier)
        }
        if assetIdentifiers.isEmpty {
            assetIdentifiers = tape.clips.compactMap { $0.assetLocalId }
        }
        let newIdentifier = try await createAlbum(named: newTitle)
        if !assetIdentifiers.isEmpty {
            try await addAssets(withIdentifiers: assetIdentifiers, to: newIdentifier)
        }
        do {
            try await deleteAlbum(withLocalIdentifier: localIdentifier)
        } catch {
            TapesLog.photos.warning("Failed to delete old album \(localIdentifier, privacy: .public) after recreation: \(error.localizedDescription, privacy: .public)")
        }
        TapesLog.photos.info("Recreated Photos album \(localIdentifier, privacy: .public) as \(newIdentifier, privacy: .public) to reflect new title \(newTitle, privacy: .public)")
        return newIdentifier
    }
    
    // MARK: - Helpers
    
    private func requireAuthorization(for accessLevel: PHAccessLevel) async throws {
        let status = photoLibrary.authorizationStatus(for: accessLevel)
        switch status {
        case .authorized, .limited:
            return
        case .notDetermined:
            let newStatus = await photoLibrary.requestAuthorization(for: accessLevel)
            switch newStatus {
            case .authorized, .limited:
                return
            default:
                throw TapeAlbumServiceError.unauthorized
            }
        default:
            throw TapeAlbumServiceError.unauthorized
        }
    }
    
    private func fetchAlbum(localIdentifier: String) -> PHAssetCollection? {
        guard !localIdentifier.isEmpty else { return nil }
        let result = photoLibrary.fetchAssetCollections(withLocalIdentifiers: [localIdentifier])
        return result.firstObject
    }
    
    private func fetchAlbum(named title: String) -> PHAssetCollection? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "localizedTitle == %@", title)
        options.fetchLimit = 1
        let result = photoLibrary.fetchAssetCollections(with: .album, subtype: .any, options: options)
        return result.firstObject
    }
    
    private func albumTitle(for tape: Tape) -> String {
        albumTitle(forTitle: tape.title)
    }
    
    private func albumTitle(forTitle title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = trimmed.isEmpty ? "New Reel" : trimmed
        return albumTitlePrefix + suffix
    }
    
    private func createAlbum(named title: String) async throws -> String {
        var placeholderIdentifier: String?
        
        try await photoLibrary.performChanges {
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
            placeholderIdentifier = request.placeholderForCreatedAssetCollection.localIdentifier
        }
        
        guard let identifier = placeholderIdentifier else {
            throw TapeAlbumServiceError.albumCreationFailed
        }
        
        return identifier
    }
}
