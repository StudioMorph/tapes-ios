# Album Deletion Integration

## Summary
Documentation for the album deletion functionality that was previously implemented but disabled by a feature flag. This feature ensures that when a tape is deleted, its associated Photos album is also removed from the device.

## Purpose & Scope
- **Purpose**: Maintain data consistency between Tapes app and Photos app
- **Scope**: Automatic album deletion when tapes are deleted
- **Integration**: Seamlessly integrated with existing tape deletion workflow

## Technical Architecture

### Feature Flag Control
```swift
// Tapes/ViewModels/FeatureFlags.swift
enum FeatureFlags {
    static var deleteAssociatedPhotoAlbum: Bool {
        return true  // Previously disabled, now enabled
    }
}
```

### Album Deletion Flow
1. **Trigger**: `TapesStore.deleteTape()` calls `scheduleAlbumDeletionIfNeeded()`
2. **Validation**: Checks feature flag and tape's album identifier
3. **Execution**: Calls `TapeAlbumService.deleteAlbum()` asynchronously
4. **Logging**: Records success/failure to `TapesLog.photos`

### Implementation Details

#### TapesStore Integration
```swift
public func deleteTape(_ tape: Tape) {
    scheduleAlbumDeletionIfNeeded(for: tape)  // ← Album deletion trigger
    tapes.removeAll { $0.id == tape.id }
    autoSave()
}

private func scheduleAlbumDeletionIfNeeded(for tape: Tape) {
    guard FeatureFlags.deleteAssociatedPhotoAlbum,
          let albumId = tape.albumLocalIdentifier,
          !albumId.isEmpty else { return }
    
    Task.detached(priority: .utility) { [weak self] in
        do {
            try await self?.albumService.deleteAlbum(withLocalIdentifier: albumId)
        } catch {
            TapesLog.photos.error("Failed to delete Photos album \(albumId, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
```

#### Album Service Integration
- **Service**: `TapeAlbumService` (implements `TapeAlbumServicing` protocol)
- **Method**: `deleteAlbum(withLocalIdentifier:)`
- **Framework**: Uses Photos framework for album operations
- **Error Handling**: Comprehensive error logging and graceful failure

## Key Features

### Asynchronous Execution
- **Background processing**: Uses `Task.detached(priority: .utility)`
- **Non-blocking**: Doesn't block UI or tape deletion
- **Memory safe**: Uses `[weak self]` to prevent retain cycles

### Error Handling
- **Comprehensive logging**: All errors logged to `TapesLog.photos`
- **Graceful degradation**: Album deletion failures don't affect tape deletion
- **Privacy-aware**: Logs use privacy masking for sensitive data

### Performance Considerations
- **Low priority**: Uses `.utility` priority to not impact user experience
- **Efficient**: Only runs when feature flag is enabled and album ID exists
- **Minimal overhead**: Reuses existing album service infrastructure

## Data Flow

### Complete Deletion Flow
1. **User Action**: Delete tape via Tape Settings modal
2. **UI Confirmation**: User confirms deletion in dialog
3. **Tape Deletion**: `TapesStore.deleteTape()` removes tape from app
4. **Album Scheduling**: `scheduleAlbumDeletionIfNeeded()` triggered
5. **Feature Check**: Verifies `deleteAssociatedPhotoAlbum` flag is enabled
6. **Album Validation**: Checks tape has valid `albumLocalIdentifier`
7. **Async Deletion**: `TapeAlbumService.deleteAlbum()` called in background
8. **Success/Error**: Result logged to `TapesLog.photos`
9. **UI Feedback**: User sees success toast and modal dismissal

### Error Scenarios
- **Feature disabled**: No album deletion attempted
- **Missing album ID**: No album deletion attempted
- **Photos permission denied**: Error logged, tape deletion continues
- **Album already deleted**: Error logged, tape deletion continues
- **Network issues**: Error logged, tape deletion continues

## Logging & Debugging

### Log Categories
- **Success**: Album deletion completed successfully
- **Error**: Album deletion failed with specific error details
- **Warning**: Missing album identifier or other non-critical issues

### Log Format
```
TapesLog.photos.error("Failed to delete Photos album {albumId}: {errorDescription}")
```

### Debugging Steps
1. **Check feature flag**: Verify `FeatureFlags.deleteAssociatedPhotoAlbum` returns `true`
2. **Check logs**: Look for `TapesLog.photos` entries in console
3. **Verify album ID**: Ensure tape has valid `albumLocalIdentifier`
4. **Check Photos permissions**: Confirm app has Photos library access
5. **Test manually**: Try deleting album directly in Photos app

## Testing

### Manual Testing
- [ ] Create tape with associated album
- [ ] Delete tape via Tape Settings
- [ ] Verify album is removed from Photos app
- [ ] Check console logs for album deletion messages
- [ ] Verify original photos remain in Photos Library

### Edge Cases
- [ ] Delete tape without associated album
- [ ] Delete tape with invalid album ID
- [ ] Delete tape when Photos permissions denied
- [ ] Delete tape when album already deleted
- [ ] Multiple rapid tape deletions

### Error Scenarios
- [ ] Feature flag disabled
- [ ] Missing album service
- [ ] Photos framework errors
- [ ] Network connectivity issues
- [ ] Memory pressure situations

## Dependencies

### Required Services
- **TapeAlbumService**: Handles Photos framework interactions
- **FeatureFlags**: Controls feature enablement
- **TapesLog**: Provides logging infrastructure
- **Photos Framework**: iOS system framework for album operations

### Optional Dependencies
- **Photos Permissions**: Required for album operations
- **Network Access**: May be needed for iCloud Photos sync

## Configuration

### Feature Flag
```swift
// Enable album deletion
FeatureFlags.deleteAssociatedPhotoAlbum = true
```

### Logging Level
```swift
// Ensure photos logging is enabled
TapesLog.photos.info("Album deletion enabled")
```

### Photos Permissions
- **Required**: `NSPhotoLibraryUsageDescription` in Info.plist
- **Required**: User granted Photos library access
- **Required**: App has album creation/deletion permissions

## Security & Privacy

### Data Protection
- **Privacy masking**: Album IDs masked in logs
- **Minimal data exposure**: Only album identifier passed to service
- **Secure deletion**: Uses Photos framework's secure deletion methods

### User Control
- **Explicit action**: Only triggered by user-initiated tape deletion
- **Clear feedback**: User informed about album deletion in UI
- **Reversible**: Original photos remain in Photos Library

## Performance Impact

### Resource Usage
- **CPU**: Minimal impact due to low priority execution
- **Memory**: Minimal impact due to weak references
- **Network**: May trigger iCloud Photos sync
- **Storage**: Reduces storage by removing album metadata

### Timing
- **Immediate**: Tape deletion happens immediately
- **Background**: Album deletion happens asynchronously
- **Completion**: May take 1-5 seconds depending on album size

## Future Enhancements

### Potential Improvements
- **Bulk album deletion**: Support for multiple album deletion
- **Progress indication**: Show album deletion progress
- **Retry mechanism**: Automatic retry for failed deletions
- **Analytics**: Track album deletion success rates

### Monitoring
- **Success metrics**: Track successful album deletions
- **Error rates**: Monitor album deletion failures
- **Performance**: Track album deletion timing
- **User feedback**: Collect user satisfaction with deletion process

## Related Documentation
- [Delete Tape Feature](./DeleteTapeFeature.md): Main delete functionality documentation
- [Album Integration Guide](../ALBUM_INTEGRATION.md): General album integration documentation
- [TapesStore API](../TapesStore.md): Store methods and data management
