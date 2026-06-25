# PairPods Codebase Memory & Rule Guide

This ruleset file helps AI assistants (LLMs) understand the structure, tools, conventions, and configuration of the PairPods workspace.

---

## 1. Project Overview & Features
[PairPods](file:///Users/luketou/Documents/Github/PairPods/README.md) is a native macOS menubar utility app built with SwiftUI, Swift, and Cocoa's CoreAudio framework.
Its main goal is to share audio between multiple Bluetooth devices simultaneously by dynamically creating a Core Audio **Aggregate Device** and designating it as the system's default output.

### Key Features:
- Multi-device audio sharing using Cocoa Core Audio APIs (`AudioHardwareCreateAggregateDevice`, etc.).
- Auto-reconnect flow when Bluetooth devices disconnect.
- Individual device volume adjustments and master clock selection.
- Sample rate mismatched warning and layout adjustments.

---

## 2. Directory & Core Architecture

Here are the key paths and structural descriptions of files inside the `PairPods/` folder:

### UI & Lifecycle
- [PairPodsApp.swift](file:///Users/luketou/Documents/Github/PairPods/PairPods/PairPodsApp.swift): The main application entry point. Implements `MenuBarExtra` with a SwiftUI window structure and coordinates the menu interface. Contains `ContentView`.
- [AboutView.swift](file:///Users/luketou/Documents/Github/PairPods/PairPods/AboutView.swift): Renders the about window with software versioning, credits, and support options.
- [DeviceVolumeView.swift](file:///Users/luketou/Documents/Github/PairPods/PairPods/DeviceVolumeView.swift): Displaying individual device sliders and master clock toggles.
- [MenuToggleItem.swift](file:///Users/luketou/Documents/Github/PairPods/PairPods/MenuToggleItem.swift): Toggle style elements for the custom menubar view.

### Audio Infrastructure & Business Logic
- [AppDependencies.swift](file:///Users/luketou/Documents/Github/PairPods/PairPods/AppDependencies.swift): The central container for MainActor-annotated singleton manager classes.
- [AudioDevice.swift](file:///Users/luketou/Documents/Github/PairPods/PairPods/AudioDevice.swift): Representation of a physical/virtual audio device. Implements extension APIs on `AudioObjectID` to fetch properties (UID, sample rate, battery level, bluetooth address) from CoreAudio and control volume scalars.
- [AudioDeviceManager.swift](file:///Users/luketou/Documents/Github/PairPods/PairPods/AudioDeviceManager.swift): Orchestrates aggregate device creation and destruction. Filters compatible devices, tracks selection/exclusion states in `UserDefaults`, and manages audio hardware property listeners.
- [AudioSharingManager.swift](file:///Users/luketou/Documents/Github/PairPods/PairPods/AudioSharingManager.swift): Monitors Core Audio configuration notifications. Toggles sharing state (`inactive`, `starting`, `active`, `stopping`) and triggers auto-reconnect logic.
- [AudioVolumeManager.swift](file:///Users/luketou/Documents/Github/PairPods/PairPods/AudioVolumeManager.swift): Observes volume updates and synchronizes volume settings across shared components.
- [CoreAudioSystem.swift](file:///Users/luketou/Documents/Github/PairPods/PairPods/CoreAudioSystem.swift): Interacts directly with low-level C-APIs of Apple's Core Audio framework. Conforms to [AudioSystemQuerying](file:///Users/luketou/Documents/Github/PairPods/PairPods/AudioSystemQuerying.swift) and [AudioSystemCommanding](file:///Users/luketou/Documents/Github/PairPods/PairPods/AudioSystemCommanding.swift) protocols to support mock injection.

### Testing Setup
All unit/integration tests reside in [PairPodsTests/](file:///Users/luketou/Documents/Github/PairPods/PairPodsTests):
- Manager-level tests verify aggregate creation, device exclusion, selection ordering, and reconnection timeout logic.
- Mocks are located under [PairPodsTests/Mocks/](file:///Users/luketou/Documents/Github/PairPods/PairPodsTests/Mocks).

---

## 3. Development, Build, & Formatting Commands

To build, verify, and maintain code quality, run these commands:

- **Verification of Swift Packages**:
  ```bash
  xcodebuild -resolvePackageDependencies -project PairPods.xcodeproj
  ```
- **Code Formatting**:
  PairPods utilizes SwiftFormat. You can format the workspace using the following command (targeted version `6.0.3`):
  ```bash
  swiftformat --swiftversion 6.0.3 .
  ```
- **Build Scheme**:
  Build target/scheme `PairPods` under `Debug` configuration without code signing constraints:
  ```bash
  xcodebuild clean build -scheme PairPods -configuration Debug -derivedDataPath ./DerivedData CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO ARCHS="x86_64 arm64" ONLY_ACTIVE_ARCH=NO
  ```
- **Running Tests**:
  Runs tests for macOS target:
  ```bash
  xcodebuild test -scheme PairPods -configuration Debug -derivedDataPath ./DerivedData CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO ONLY_ACTIVE_ARCH=YES -destination 'platform=macOS'
  ```

---

## 4. Coding Conventions & Best Practices

1. **Concurrency**: Prefer Swift 6 concurrency patterns (`async/await`, `@MainActor`, `Task`). All UI-touching state management should run on the `@MainActor`.
2. **CoreAudio C-API Wrap**: Wrap direct low-level Core Audio interactions behind protocol abstractions. Avoid executing raw C functions inline within SwiftUI views or core managers; delegate them via [CoreAudioSystem](file:///Users/luketou/Documents/Github/PairPods/PairPods/CoreAudioSystem.swift).
3. **Safety / Pointer Management**: When dealing with `UnsafeMutablePointer` (e.g., `AudioBufferList`), ensure matching `deallocate()` or cleanup blocks. Use `Unmanaged` wisely to prevent memory leaks with Core Foundation (`takeRetainedValue` or `takeUnretainedValue`).
4. **Volume Syncing**: Do not trigger infinite circular updates when syncing volumes. Always separate programmatically set volume events from user-initiated UI slider adjustments.
5. **No Code Sign Errors on CI**: While coding, keep in mind that local builds might sign automatically, but local scripts/CI override code-signing via `CODE_SIGNING_REQUIRED=NO`.
