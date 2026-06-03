# Mentis iOS App

Swift/SwiftUI native iOS app for the Mentis spatial memory palace backend.

## Requirements

- Xcode 15+
- iOS 16+ device (or simulator for UI work)
- LiDAR-equipped device (iPhone 12 Pro+) for RoomPlan scanning
- Any modern iPhone for AR anchor placement (non-LiDAR)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the `.xcodeproj`

## Setup

### 1. Install XcodeGen

```bash
brew install xcodegen
```

### 2. Generate the Xcode project

```bash
cd IOS_app
xcodegen generate
```

This creates `Mentis.xcodeproj` from `project.yml`.

### 3. Open in Xcode

```bash
open Mentis.xcodeproj
```

Set your **Development Team** in the project settings (required for running on a real device).

### 4. Start the backend

```bash
cd ..
python app.py
```

The server runs on `http://localhost:5001`.

### 5. Configure the server URL in the app

- **Simulator**: `http://localhost:5001` works out of the box.
- **Real device**: Use your Mac's LAN IP, e.g. `http://192.168.1.x:5001`.
  You can change the URL in the Login screen before signing in.

---

## Features

### Room Scanning
| Device | Flow |
|---|---|
| **LiDAR (iPhone 12 Pro+)** | Full RoomPlan scan → exports USDZ → uploads to backend |
| **Non-LiDAR** | Creates a virtual placeholder room so you can still use AR anchors |

### AR Anchor Placement
- Works on all modern iPhones (A12+)
- Detects horizontal and vertical planes
- Tap any detected surface to place an anchor
- Labels float above anchor points and always face the camera
- **World map persistence**: ARKit saves the spatial map per room so anchors appear in their original physical positions on subsequent sessions (requires being in the same physical space)

### Review Mode
- Spaced repetition using the SM-2 algorithm (handled by backend)
- Cards show the question, tap "Show Answer" to reveal
- Grade with: **Again** (0) · **Hard** (3) · **Good** (4) · **Easy** (5)

---

## File Structure

```
IOS_app/
├── project.yml                     # XcodeGen config
├── Mentis/
│   ├── MentisApp.swift             # App entry point
│   ├── AppState.swift              # Auth state (ObservableObject)
│   ├── Info.plist                  # Permissions + metadata
│   ├── Models/
│   │   └── Models.swift            # Codable data models
│   ├── Network/
│   │   └── APIClient.swift         # URLSession async/await API layer
│   ├── Views/
│   │   ├── LoginView.swift
│   │   ├── ContentView.swift       # TabView root
│   │   ├── RoomListView.swift      # Room list + RoomDetailView
│   │   ├── ScanView.swift          # RoomPlan (LiDAR) + virtual room
│   │   └── ReviewView.swift        # Spaced repetition cards
│   └── AR/
│       ├── ARSceneCoordinator.swift  # ARSCNViewDelegate + world map
│       ├── ARPlacementView.swift     # UIViewRepresentable bridge
│       └── ARPlacementHostView.swift # SwiftUI host + all AR sheets
```

## Notes

- `RoomPlan.framework` is linked as a **weak framework** so the app runs on non-LiDAR devices without crashing.
- LiDAR availability is checked at runtime via `ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)`.
- World maps are stored in the app's Documents directory as `mentis_worldmap_<roomId>.arworldmap`.
