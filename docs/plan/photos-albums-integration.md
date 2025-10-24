# iOS Photos Album Integration Plan

## Context & Current Findings
- The app already persists `Tape` (JSON on disk) with clip metadata, carousel logic, export, and AirPlay flows fully functional. Media insertion lives in `TapesStore` (`insertMedia`, `insertClip…`) while `TapeCardView` drives UX side-effects (first content sentinel, empty tape creation).
- Capture goes through `CameraCoordinator` (UIKit camera). Videos get a placeholder `localIdentifier`, but photos are returned as raw `UIImage` with no identifier. Saving uses `PHPhotoLibrary.performChanges` with default auth, logging via `TapesLog.camera`.
- Imports use PHPicker via `PhotoImportCoordinator` and helpers in `Platform/Photos/MediaProviderLoader`. Picker results are copied into our sandbox and wrapped in `PickedMedia`; videos remember `assetIdentifier`, images do not.
- Export relies on two `TapeExporter` implementations (`ios/` and `Tapes/Export/`). Both create a global "Tapes" album via `ensureAlbum(named:)` and always request full access through `PHPhotoLibrary`.
- `TapesStore` is the single source of truth for persistence, auto-saving after every mutation. No feature-flag system exists yet. Logging categories are defined in `Tapes/Platform/Photos/TapesLog.swift`.
- Permissions today: camera flow uses legacy `PHPhotoLibrary.requestAuthorization(_:)` (effectively `.readWrite`). Export uses `.addOnly`. Limited library access is not explicitly handled; failures fall back to returning media without album coordination.

## Architecture Fit
- **PhotoLibraryAccess** (new) – lightweight wrapper around `PHPhotoLibrary` that centralises permission requests (`.addOnly` for add flows, `.readWrite` when we need to delete albums or rescan) and provides async helpers (`performChanges`, `fetchCollection`, `addAssets`). Injected where needed to improve testability.
- **TapeAlbumService** – orchestrates album lifecycle per tape. Responsibilities: create/find album (`Tapes – <TapeTitle>`), add asset identifiers, verify existence, and (feature-flagged) delete albums. Stores `albumLocalIdentifier` back onto `Tape` via `TapesStore`. Emits structured results for UI messaging/logging.
- **AlbumAssociationCoordinator** (logic layer inside `TapesStore`) – hooks into clip insertion and deletion. When first clip is committed it calls `TapeAlbumService.ensureAlbum(for:)`, stores the identifier, and passes collected asset IDs to `addAssets`. On removal, no action unless album deletion flag is enabled.
- **PickedMedia enhancements** – extend model to carry `assetIdentifier` for photos as well. Adjust capture/import pipelines so every media item added to a tape can be linked to a PHAsset.
- **Feature gating** – introduce a simple enum (`FeatureFlags`) for the "Delete Photos Album" capability. Service methods check the flag so UI can remain dormant while infrastructure exists.

This approach keeps album management confined to platform/Photos infrastructure and the store, avoiding regressions in view code or carousel logic.

## File Inventory (planned)
- `Tapes/Models/Tape.swift` – add optional `albumLocalIdentifier` (Codable/back-compat) and helper for album-bound state.
- `Tapes/ViewModels/TapesStore.swift` – inject `TapeAlbumService`, trigger album ensures on first clip insert, enqueue asset additions, handle migration catch-up, persist album ID, and (flagged) album deletion on tape removal.
- `Tapes/Platform/Photos/TapeAlbumService.swift` (new) – implement album CRUD, permission glue, retry/missing-album handling, and limited access fallbacks.
- `Tapes/Platform/Photos/PhotoLibraryAccess.swift` (new) – async helper/protocol abstraction over `PHPhotoLibrary` for unit testing and authorisation management.
- `Tapes/Platform/Photos/TapesLog.swift` – add `Logger` category `photos` for album operations.
- `Tapes/Features/Camera/CameraCoordinator.swift` – capture photo placeholder identifiers, thread through `PickedMedia.photo(assetIdentifier:)` so albums can reference the saved asset.
- `Tapes/Platform/Photos/MediaProviderLoader.swift` & `Tapes/Features/Import/PhotoImportCoordinator.swift` – propagate `assetIdentifier` for images when available, keep sandbox copy fallback, surface missing identifiers gracefully.
- `Tapes/Platform/Photos/PHPickerVideo.swift` (if needed) – ensure new metadata plumbs through.
- `Tapes/Export/TapeExporter.swift` & `ios/TapeExporter.swift` – replace global album logic with `TapeAlbumService` usage; add error reporting when album add fails.
- `Tapes/ViewModels/FeatureFlags.swift` (new) – simple static toggles for Photos album deletion (default `false`).
- `Tapes/Views/TapesListView.swift` or shared toast presenter – show non-blocking message when album add/delete soft-fails (flagged until UI finalised).
- `Info.plist` – verify/adjust `NSPhotoLibraryAddUsageDescription` + `NSPhotoLibraryUsageDescription` copy if wording needs album mention.
- `TapesTests` – add unit coverage for `TapeAlbumService` with mocked `PhotoLibraryAccess` and persistence migration tests.

## Permissions Strategy
- Request `.addOnly` when ensuring an album or adding assets during capture/import/export. If status is `.limited`, proceed but expect some assets to be inaccessible; warn via toast/log.
- Request `.readWrite` only for album deletion or scanning for missing albums (one-off migration). Defer the prompt until the user turns on the deletion feature flag (internal use) or a background reconciliation requires it.
- Surface permission errors via the existing alert/toast pattern without interrupting clip insertion; failures should not block tape workflows.

## Edge Cases & Handling
- **iCloud-only assets** – allow `PHPhotoLibrary` to fetch asynchronously; set `isNetworkAccessAllowed = true` on requests. If fetching fails, log and continue without album reference.
- **Duplicate album titles** – always rely on stored `albumLocalIdentifier`. When creating, check for existing collections with matching `localIdentifier`; if missing, create new even if another album shares the title. Document in logs to aid debugging.
- **Album missing or deleted externally** – on ensure, if fetch by localIdentifier fails, recreate the album and update `albumLocalIdentifier`.
- **Tape rename** – do not rename the Photos album. If a user duplicates titles, albums remain with their original `Tapes – <Title>` names.
- **Failure to add asset to album** – log (`TapesLog.photos.warning`), surface a soft toast (“Saved, but couldn’t group in Photos album”), and continue. Keep the clip in the tape.
- **Limited Photos access** – if album creation is denied, mark tape with a `albumAssociationStatus` (enum) so future attempts can be retried when permission changes.

## Telemetry & User Messaging
- Extend `TapesLog` with a `photos` category for album ensure/add/delete operations.
- Hook into existing toast/alert pattern: reuse the `CompletionToast` style for success (optional future UI) and add a lightweight `Alert` for soft failures when feature-flagged.
- Record minimal analytics hooks (if any) via existing logging only – no external telemetry system identified.

## Feature Flagging
- Add `FeatureFlags.deleteAssociatedPhotoAlbum` (default `false`).
- Wrap album deletion logic inside this check so removing a tape keeps the Photos album intact until the flag is enabled.
- Provide a debug/backdoor (e.g., environment override or QA checklist toggle) for internal validation without shipping UI changes.

## Testing Strategy
- **Unit**: mock `PhotoLibraryAccess` to cover album creation, fetch, add asset flows, limited access fallback, and deletion branch. Test `TapesStore` migration path ensures album ID persists.
- **Integration**: add a test harness in `TapesTests` to simulate inserting media and verifying service calls. Ensure exporter uses stored album ID path.
- **Manual checklist**: camera capture (photo + video), PHPicker import (photo + video, including limited access), first clip insertion creating album, incremental additions, exporter pipeline, tape deletion with flag on/off, limited-permission scenarios, offline/iCloud-only asset retrieval, rename tape, duplicate titles, AirPlane mode, background relaunch.

## Rollout & Fallback
- Ship infrastructure guarded by feature flag for deletion and by silent failure handling for album adds.
- Monitor logs for album errors. If issues arise, disable album deletion via flag and, if necessary, short-circuit calls to `TapeAlbumService.addAssets` behind a runtime toggle.
- Ensure reverting is limited to flipping the flag or, in worst case, removing the album service binding (minimal diff).

## Migration Strategy
- Add `albumLocalIdentifier` (optional) to `Tape`; decoder defaults to `nil` for existing users.
- On app launch, run a lightweight reconciliation: for each tape with clips but no `albumLocalIdentifier`, mark as `pendingAssociation`. The next media add/export will call `ensureAlbum` and persist the identifier. Avoid mass creation to keep launch cheap.
- Provide a background task (optional) that batches album creation when the device is idle and permissions allow; skip if permission is limited.

## Acceptance Criteria
- First media added to a tape creates (or reuses) a Photos album titled `Tapes – <TapeTitle>` and saves its `localIdentifier` on the tape record.
- Every captured or imported asset is added as a reference to that album without moving or duplicating the underlying asset.
- Album deletion capability exists behind a feature flag; when disabled, tape deletion leaves the Photos album untouched.
- All current MVP behaviours continue to function: carousel/FAB insertion, thumbnails, edit tray, delete gesture semantics, settings adjustments, play/export, cast/AirPlay.

## Non-Regression Checklist
- FAB insertion point logic.
- Thumbnail sizing/caching and async generation.
- Edit tray trim/rotate/fill-fit operations.
- Long-press + flick-up delete (ensuring last clip leaves start placeholder only).
- Settings sheet (orientation, fit/fill, transitions).
- Play action sheet (Preview vs Merge & Save) and subsequent exporter behaviour.
- AirPlay/Cast interactions.
- Build/compile with existing CI (`xcodebuild`, tests) unaffected by new dependencies.

## Open Risks & Mitigations
- Captured photos currently discard asset identifiers → adjust `CameraCoordinator` to capture placeholders; fallback to guidance toast if unavailable.
- PHPicker images may lack identifiers under limited access → continue without album association but queue a retry once identifiers become available.
- Duplicate album names may confuse users → rely on stored identifier and document behaviour; consider adding debug menu to inspect associations.

