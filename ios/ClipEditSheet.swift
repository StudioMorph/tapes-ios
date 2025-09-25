import SwiftUI
import PhotosUI
import AVFoundation

// MARK: - Clip Edit Actions

public enum ClipEditAction {
    case trim
    case rotate
    case fitFill
    case share
    case remove
}

// MARK: - Fit/Fill Mode

public enum FitFillMode: String, CaseIterable {
    case fit = "Fit"
    case fill = "Fill"
    
    var description: String {
        switch self {
        case .fit:
            return "Shows entire clip, may have black bars"
        case .fill:
            return "Fills entire frame, may crop content"
        }
    }
}

// MARK: - Clip Edit Sheet

public struct ClipEditSheet: View {
    let thumbnail: ClipThumbnail
    let onAction: (ClipEditAction) -> Void
    let onDismiss: () -> Void
    
    @State private var rotation: Double = 0
    @State private var fitFillMode: FitFillMode = .fit
    @State private var showingRemoveConfirmation = false
    @State private var showingShareSheet = false
    @State private var showingTrimEditor = false
    
    public init(
        thumbnail: ClipThumbnail,
        onAction: @escaping (ClipEditAction) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.thumbnail = thumbnail
        self.onAction = onAction
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: DesignTokens.Spacing.s16) {
                    HStack {
                        Text("Edit Clip")
                            .font(DesignTokens.Typography.title)
                            .foregroundColor(DesignTokens.Colors.onSurface(.light))
                        
                        Spacer()
                        
                        Button("Done") {
                            onDismiss()
                        }
                        .font(DesignTokens.Typography.body)
                        .foregroundColor(DesignTokens.Colors.primaryRed)
                    }
                    
                    // Clip info
                    HStack {
                        Text(thumbnail.displayLabel)
                            .font(DesignTokens.Typography.caption)
                            .foregroundColor(DesignTokens.Colors.muted(60))
                        
                        Spacer()
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.s20)
                .padding(.top, DesignTokens.Spacing.s20)
                
                Divider()
                    .padding(.vertical, DesignTokens.Spacing.s16)
                
                // Actions
                VStack(spacing: DesignTokens.Spacing.s8) {
                    // Trim Action
                    ClipEditActionRow(
                        icon: "scissors",
                        title: "Trim",
                        subtitle: "Edit start and end points",
                        action: {
                            onAction(.trim)
                            onDismiss()
                        }
                    )
                    
                    Divider()
                        .padding(.horizontal, DesignTokens.Spacing.s20)
                    
                    // Rotate Action
                    ClipEditActionRow(
                        icon: "rotate.right",
                        title: "Rotate 90°",
                        subtitle: "Rotate clip clockwise",
                        action: {
                            onAction(.rotate)
                        }
                    )
                    
                    Divider()
                        .padding(.horizontal, DesignTokens.Spacing.s20)
                    
                    // Fit/Fill Toggle
                    VStack(spacing: DesignTokens.Spacing.s12) {
                        HStack {
                            Image(systemName: "aspectratio")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(DesignTokens.Colors.primaryRed)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s4) {
                                Text("Aspect Ratio")
                                    .font(DesignTokens.Typography.body)
                                    .foregroundColor(DesignTokens.Colors.onSurface(.light))
                                
                                Text(fitFillMode.description)
                                    .font(DesignTokens.Typography.caption)
                                    .foregroundColor(DesignTokens.Colors.muted(60))
                            }
                            
                            Spacer()
                            
                            Picker("Fit/Fill", selection: $fitFillMode) {
                                ForEach(FitFillMode.allCases, id: \.self) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(SegmentedPickerStyle())
                            .frame(width: 120)
                            .onChange(of: fitFillMode) { _ in
                                onAction(.fitFill)
                            }
                        }
                        .padding(.horizontal, DesignTokens.Spacing.s20)
                        .padding(.vertical, DesignTokens.Spacing.s12)
                    }
                    
                    Divider()
                        .padding(.horizontal, DesignTokens.Spacing.s20)
                    
                    // Share Action
                    ClipEditActionRow(
                        icon: "square.and.arrow.up",
                        title: "Share",
                        subtitle: "Export or AirDrop this clip",
                        action: {
                            onAction(.share)
                            onDismiss()
                        }
                    )
                    
                    Divider()
                        .padding(.horizontal, DesignTokens.Spacing.s20)
                    
                    // Remove Action
                    ClipEditActionRow(
                        icon: "trash",
                        title: "Remove",
                        subtitle: "Delete this clip from tape",
                        isDestructive: true,
                        action: {
                            showingRemoveConfirmation = true
                        }
                    )
                }
                
                Spacer()
            }
            .background(DesignTokens.Colors.surface(.light))
        }
        .alert("Remove Clip", isPresented: $showingRemoveConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                onAction(.remove)
                onDismiss()
            }
        } message: {
            Text("Are you sure you want to remove this clip from the tape? This action cannot be undone.")
        }
    }
}

// MARK: - Clip Edit Action Row

private struct ClipEditActionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let isDestructive: Bool
    let action: () -> Void
    
    init(
        icon: String,
        title: String,
        subtitle: String,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.isDestructive = isDestructive
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignTokens.Spacing.s16) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(isDestructive ? .red : DesignTokens.Colors.primaryRed)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.s4) {
                    Text(title)
                        .font(DesignTokens.Typography.body)
                        .foregroundColor(isDestructive ? .red : DesignTokens.Colors.onSurface(.light))
                    
                    Text(subtitle)
                        .font(DesignTokens.Typography.caption)
                        .foregroundColor(DesignTokens.Colors.muted(60))
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(DesignTokens.Colors.muted(40))
            }
            .padding(.horizontal, DesignTokens.Spacing.s20)
            .padding(.vertical, DesignTokens.Spacing.s12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Clip Edit Sheet Presenter

public struct ClipEditSheetPresenter: View {
    @Binding var isPresented: Bool
    let thumbnail: ClipThumbnail
    let onAction: (ClipEditAction) -> Void
    
    public init(
        isPresented: Binding<Bool>,
        thumbnail: ClipThumbnail,
        onAction: @escaping (ClipEditAction) -> Void
    ) {
        self._isPresented = isPresented
        self.thumbnail = thumbnail
        self.onAction = onAction
    }
    
    public var body: some View {
        if isPresented {
            ClipEditSheet(
                thumbnail: thumbnail,
                onAction: { action in
                    onAction(action)
                },
                onDismiss: {
                    isPresented = false
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Preview

struct ClipEditSheet_Previews: PreviewProvider {
    static var previews: some View {
        ClipEditSheet(
            thumbnail: ClipThumbnail(
                id: "preview-clip",
                index: 1,
                tapeName: "My Tape"
            ),
            onAction: { action in
                print("Action: \(action)")
            },
            onDismiss: {
                print("Dismissed")
            }
        )
        .previewDisplayName("Clip Edit Sheet")
    }
}
