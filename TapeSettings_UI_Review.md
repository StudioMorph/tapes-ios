# Tape Settings Modal UI Review & Rebuild Plan

## Current Implementation Summary

### Key Files
- **Primary View**: `Tapes/Components/TapeSettingsSheet.swift` (256 lines)
- **Design System**: `Tapes/DesignSystem/Tokens.swift` (63 lines)
- **Data Models**: `Tapes/Models/Tape.swift` (TransitionType, TapeOrientation, ScaleMode enums)
- **Integration**: `Tapes/Views/TapesListView.swift` (settingsSheet computed property)

### Current Structure
```swift
NavigationView {
    ScrollView {
        VStack(spacing: 32) {
            transitionSection          // "Choose default transition"
            transitionDurationSection  // Conditional slider
            deleteSection             // Destructive action
        }
    }
}
.toolbar { Cancel/Save buttons }
.alert { Delete confirmation }
```

## HIG Alignment Check

### ✅ Compliant Areas
- **Modal Presentation**: Uses `.sheet()` presentation with proper dismissal
- **Navigation**: Standard toolbar with Cancel/Save pattern
- **Destructive Actions**: Proper red styling and confirmation dialog
- **Spacing**: Consistent use of design tokens (32pt, 24pt, 16pt, 8pt)
- **Colour Contrast**: Adequate contrast ratios with dark theme

### ❌ Non-Compliant Areas

#### High Severity Issues

1. **Typography Ignores Dynamic Type** (High)
   - **Evidence**: `TapeSettingsSheet.swift:87,101,119,150,186,190`
   - **Code**: `.font(.system(size: 18, weight: .semibold))`
   - **Impact**: Violates iOS HIG accessibility requirements
   - **Fix**: Use semantic font styles (`.title2`, `.headline`, `.body`)

2. **Missing Accessibility Labels on Interactive Elements** (High)
   - **Evidence**: `TapeSettingsSheet.swift:179-207` (transitionOption buttons)
   - **Code**: No `.accessibilityLabel` or `.accessibilityHint`
   - **Impact**: VoiceOver users cannot understand button purposes
   - **Fix**: Add comprehensive accessibility labels and hints

3. **Inconsistent Hit Target Sizes** (High)
   - **Evidence**: `TapeSettingsSheet.swift:179-207` (transition buttons)
   - **Code**: No explicit frame sizing for touch targets
   - **Impact**: Violates 44×44pt minimum touch target guidance
   - **Fix**: Ensure all interactive elements meet minimum size requirements

#### Medium Severity Issues

4. **Hard-coded Font Sizes Throughout** (Medium)
   - **Evidence**: Multiple locations using `.font(.system(size: X))`
   - **Impact**: Poor Dynamic Type support, accessibility barriers
   - **Fix**: Replace with semantic font styles

5. **Missing Focus Management** (Medium)
   - **Evidence**: No `.accessibilitySortPriority` or focus order
   - **Impact**: Poor VoiceOver navigation experience
   - **Fix**: Implement proper focus order and grouping

6. **Inconsistent Button Styling** (Medium)
   - **Evidence**: Mix of `Button` and `Image` with `onTapGesture`
   - **Impact**: Inconsistent interaction patterns
   - **Fix**: Standardize on `Button` components

#### Low Severity Issues

7. **Missing RTL Support** (Low)
   - **Evidence**: No RTL-specific layout considerations
   - **Impact**: Poor experience for RTL languages
   - **Fix**: Add RTL-aware layout modifiers

8. **Limited Preview Coverage** (Low)
   - **Evidence**: Single preview with default state
   - **Impact**: Difficult to test various states and configurations
   - **Fix**: Add comprehensive previews for all states

## Accessibility Audit

### Current State
- **Labels**: Only delete button has proper accessibility label
- **Hints**: Only delete button has accessibility hint
- **Traits**: Missing button traits on transition options
- **Focus Order**: No explicit focus management
- **Dynamic Type**: Not supported (hard-coded font sizes)
- **Contrast**: Adequate but not tested with accessibility settings
- **Reduce Motion**: Not implemented

### Required Improvements
- Add `.accessibilityLabel` and `.accessibilityHint` to all interactive elements
- Implement `.accessibilitySortPriority` for logical focus order
- Add `.accessibilityAddTraits(.isButton)` to transition options
- Support Dynamic Type with semantic font styles
- Test with VoiceOver and accessibility settings
- Implement Reduce Motion support

## Design System Consistency

### ✅ Consistent Usage
- **Spacing**: Proper use of `Tokens.Spacing` (s, m, l)
- **Colours**: Consistent use of `Tokens.Colors` palette
- **Corner Radius**: Proper use of `Tokens.Radius.card`
- **Background**: Consistent elevated surface styling

### ❌ Inconsistencies
- **Typography**: Hard-coded font sizes instead of design tokens
- **Button Styles**: Mix of different button implementations
- **Icon Sizes**: Inconsistent icon sizing (17pt, 20pt, etc.)
- **Missing Tokens**: No typography tokens defined in design system

## Rebuild Plan

### 1. View Hierarchy Proposal

```swift
TapeSettingsView {
    NavigationView {
        ScrollView {
            VStack(spacing: 32) {
                TransitionSection {
                    SectionHeader("Choose default transition")
                    TransitionOptionGrid {
                        TransitionOption(.none)
                        TransitionOption(.crossfade)
                        TransitionOption(.slideLR)
                        TransitionOption(.slideRL)
                    }
                }
                
                TransitionDurationSection {
                    SectionHeader("Transition Duration")
                    DurationSlider()
                    DurationDisplay()
                }
                
                DestructiveActionSection {
                    DeleteTapeButton()
                    DeleteExplanation()
                }
            }
        }
    }
    .toolbar { CancelSaveToolbar() }
    .alert { DeleteConfirmationDialog() }
}
```

### 2. State Management Strategy

```swift
struct TapeSettingsView: View {
    @Binding var tape: Tape
    let onDismiss: () -> Void
    let onTapeDeleted: (() -> Void)?
    
    // UI-only state
    @State private var selectedTransition: TransitionType
    @State private var transitionDuration: Double
    @State private var hasChanges = false
    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false
    
    // No business logic in view
    // All data operations through callbacks
}
```

### 3. Reusable Components

#### TransitionOption Component
```swift
struct TransitionOption: View {
    let transition: TransitionType
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(transition.displayName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(transition.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                        .font(.title2)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44) // HIG compliance
        .accessibilityLabel(transition.displayName)
        .accessibilityHint(transition.description)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
```

#### DestructiveActionSection Component
```swift
struct DestructiveActionSection: View {
    let isDeleting: Bool
    let onDelete: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Button(action: onDelete) {
                HStack(spacing: 8) {
                    if isDeleting {
                        ProgressView()
                            .scaleEffect(0.8)
                            .progressViewStyle(.circular)
                            .tint(.red)
                    } else {
                        Image(systemName: "trash")
                            .font(.headline)
                            .foregroundColor(.red)
                    }
                    
                    Text("Delete Tape")
                        .font(.headline)
                        .foregroundColor(.red)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .disabled(isDeleting)
            .accessibilityLabel("Delete Tape")
            .accessibilityHint("Deletes the tape and its album. Photos and videos remain in your device's Library.")
            .accessibilityAddTraits(.isDestructive)
            
            VStack(spacing: 2) {
                Text("Also deletes the album from your device.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Text("All photos and videos will remain in your device's Library.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}
```

### 4. Styling with Design Tokens

#### Enhanced Tokens
```swift
public enum Typography {
    public static let largeTitle = Font.largeTitle
    public static let title = Font.title2
    public static let headline = Font.headline
    public static let body = Font.body
    public static let caption = Font.caption
    public static let caption2 = Font.caption2
}

public enum Spacing {
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 16
    public static let l: CGFloat = 24
    public static let xl: CGFloat = 32
    public static let xxl: CGFloat = 48
}

public enum HitTarget {
    public static let minimum: CGFloat = 44
    public static let recommended: CGFloat = 48
}
```

### 5. Accessibility Implementation

#### Focus Management
```swift
VStack(spacing: 32) {
    TransitionSection()
        .accessibilitySortPriority(1)
    
    if showDurationSection {
        TransitionDurationSection()
            .accessibilitySortPriority(2)
    }
    
    DestructiveActionSection()
        .accessibilitySortPriority(3)
}
```

#### Dynamic Type Support
```swift
Text("Choose default transition")
    .font(.title2)
    .dynamicTypeSize(.large ... .accessibility3)

Text(transition.description)
    .font(.caption)
    .dynamicTypeSize(.medium ... .accessibility2)
```

#### Reduce Motion Support
```swift
.animation(.easeInOut(duration: 0.3), value: isSelected)
    .animation(.easeInOut(duration: 0.3), value: hasChanges)
    .animation(.none, value: isSelected) // Respect Reduce Motion
```

### 6. Animation & Haptics

#### Subtle Transitions
```swift
// Selection animation
.animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)

// Loading state
.animation(.easeInOut(duration: 0.2), value: isDeleting)

// Respect Reduce Motion
.animation(.none, value: isSelected) // When Reduce Motion enabled
```

#### Haptic Feedback
```swift
private func provideHapticFeedback() {
    #if os(iOS)
    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
    impactFeedback.impactOccurred()
    #endif
}
```

### 7. Comprehensive Previews

```swift
#Preview("Default State") {
    TapeSettingsView(
        tape: .constant(Tape.sampleTapes[0]),
        onDismiss: {},
        onTapeDeleted: nil
    )
    .environmentObject(TapesStore())
}

#Preview("Dark Mode") {
    TapeSettingsView(
        tape: .constant(Tape.sampleTapes[0]),
        onDismiss: {},
        onTapeDeleted: nil
    )
    .environmentObject(TapesStore())
    .preferredColorScheme(.dark)
}

#Preview("Dynamic Type XL") {
    TapeSettingsView(
        tape: .constant(Tape.sampleTapes[0]),
        onDismiss: {},
        onTapeDeleted: nil
    )
    .environmentObject(TapesStore())
    .environment(\.sizeCategory, .accessibilityExtraLarge)
}

#Preview("RTL") {
    TapeSettingsView(
        tape: .constant(Tape.sampleTapes[0]),
        onDismiss: {},
        onTapeDeleted: nil
    )
    .environmentObject(TapesStore())
    .environment(\.layoutDirection, .rightToLeft)
}

#Preview("Loading State") {
    TapeSettingsView(
        tape: .constant(Tape.sampleTapes[0]),
        onDismiss: {},
        onTapeDeleted: nil
    )
    .environmentObject(TapesStore())
    .onAppear {
        // Simulate loading state
    }
}
```

## Example Code Snippets

### Complete TapeSettingsView Skeleton
```swift
struct TapeSettingsView: View {
    @Binding var tape: Tape
    let onDismiss: () -> Void
    let onTapeDeleted: (() -> Void)?
    
    @State private var selectedTransition: TransitionType
    @State private var transitionDuration: Double
    @State private var hasChanges = false
    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false
    
    init(tape: Binding<Tape>, onDismiss: @escaping () -> Void = {}, onTapeDeleted: (() -> Void)? = nil) {
        self._tape = tape
        self.onDismiss = onDismiss
        self.onTapeDeleted = onTapeDeleted
        self._selectedTransition = State(initialValue: tape.wrappedValue.transition)
        self._transitionDuration = State(initialValue: tape.wrappedValue.transitionDuration)
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 32) {
                    TransitionSection(
                        selectedTransition: $selectedTransition,
                        hasChanges: $hasChanges
                    )
                    
                    if selectedTransition != .none {
                        TransitionDurationSection(
                            duration: $transitionDuration,
                            hasChanges: $hasChanges
                        )
                    }
                    
                    DestructiveActionSection(
                        isDeleting: isDeleting,
                        onDelete: { showingDeleteConfirmation = true }
                    )
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
            }
            .background(Color(.systemBackground))
            .navigationTitle("Tape Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        resetToBindingValues()
                        onDismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveChanges()
                        onDismiss()
                    }
                    .disabled(!hasChanges)
                }
            }
        }
        .alert("Delete this Tape?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteTape()
            }
        } message: {
            Text("This will delete the Tape and its album. Your photos and videos remain in your device's Library.")
        }
    }
    
    private func resetToBindingValues() {
        selectedTransition = tape.transition
        transitionDuration = tape.transitionDuration
        hasChanges = false
    }
    
    private func saveChanges() {
        // Update tape with new values
        hasChanges = false
    }
    
    private func deleteTape() {
        isDeleting = true
        // Perform deletion
        onDismiss()
        onTapeDeleted?()
    }
}
```

## Acceptance Criteria (UI-Only)

### ✅ Accessibility Requirements
- [ ] All interactive elements have proper accessibility labels
- [ ] All interactive elements have accessibility hints where appropriate
- [ ] Focus order is logical and follows UI hierarchy
- [ ] Dynamic Type is supported with semantic font styles
- [ ] Reduce Motion is respected in animations
- [ ] VoiceOver navigation works smoothly
- [ ] All touch targets meet 44×44pt minimum requirement

### ✅ HIG Compliance
- [ ] Typography uses semantic font styles
- [ ] Spacing follows 8pt grid system
- [ ] Colours have adequate contrast ratios
- [ ] Modal presentation follows iOS patterns
- [ ] Destructive actions are clearly marked
- [ ] Button styles are consistent throughout

### ✅ Design System Consistency
- [ ] All spacing uses design tokens
- [ ] All colours use design tokens
- [ ] All typography uses design tokens
- [ ] All corner radii use design tokens
- [ ] No hard-coded values in UI code

### ✅ User Experience
- [ ] Smooth animations that respect user preferences
- [ ] Appropriate haptic feedback
- [ ] Clear visual hierarchy
- [ ] Intuitive interaction patterns
- [ ] Responsive to different screen sizes

### ✅ Code Quality
- [ ] Reusable components with clear APIs
- [ ] Proper state management
- [ ] No business logic in views
- [ ] Comprehensive preview coverage
- [ ] Clean, maintainable code structure

## Implementation Priority

1. **High Priority**: Fix accessibility issues and Dynamic Type support
2. **Medium Priority**: Standardize button styles and hit targets
3. **Low Priority**: Add RTL support and enhanced previews

## Estimated Effort

- **Accessibility fixes**: 4-6 hours
- **Typography updates**: 2-3 hours
- **Component refactoring**: 6-8 hours
- **Preview enhancement**: 2-3 hours
- **Testing and validation**: 4-6 hours

**Total estimated effort**: 18-26 hours

---

*This review focuses exclusively on UI concerns and does not address business logic, data models, or navigation patterns.*
