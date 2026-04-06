# BabyLove

A beautifully minimal iOS app for tracking your baby's daily life — feedings, sleep, diapers, growth, and milestones — all in one place.

## Features

- **Quick Log** — Record feedings, sleep, and diaper changes in 2 taps from the home screen
- **Today Dashboard** — At-a-glance summary of daily feedings, sleep time, and diaper count
- **Growth Tracking** — Log weight, height, and head circumference with visual charts
- **Milestone Timeline** — Capture first smiles, first steps, and every precious moment
- **Unit Support** — Metric (kg/cm/mL) and Imperial (lbs/in/oz) with seamless switching
- **Privacy First** — All data stored locally on device via CoreData

## Tech Stack

| | |
|---|---|
| Platform | iOS 26.0+ |
| Language | Swift 6.0 |
| UI | SwiftUI |
| Data | CoreData |
| Architecture | MVVM |
| Project | XcodeGen (`project.yml`) |

## Getting Started

### Requirements

- Xcode 16+
- iOS 26 Simulator or device
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

### Setup

```bash
git clone https://github.com/xenonyu/babylove.git
cd babylove
xcodegen generate
open BabyLove.xcodeproj
```

Select the **BabyLove** scheme and run on an iPhone 17 simulator (iOS 26).

## Project Structure

```
BabyLove/
├── App/                    # App entry point, launch arg handling
├── Design/                 # DesignSystem: colors, reusable components
├── Models/                 # Baby profile, tracking enums
├── Services/               # PersistenceController (CoreData)
├── ViewModels/             # AppState, TrackViewModel
└── Views/
    ├── Onboarding/         # First-launch onboarding flow
    ├── Home/               # Today dashboard
    ├── Track/              # Log feeding / sleep / diaper / growth
    ├── Growth/             # Growth chart view
    ├── Memory/             # Milestone timeline
    └── Settings/           # Preferences, units, baby profile

BabyLoveTests/              # XCTest unit tests (22 tests)
BabyLoveUITests/            # XCUITest UI automation
agent/                      # Auto-iteration agent (Claude Opus 4.6)
```

## Design System

| Token | Color | Use |
|---|---|---|
| Primary | `#FF7B6B` | Coral — brand accent |
| Background | `#FFF9F5` | Warm white |
| Feeding | `#4BAEE8` | Sky blue |
| Sleep | `#9B8EC4` | Lavender |
| Diaper | `#55C189` | Mint green |
| Growth | `#F5A623` | Amber |

## Testing

```bash
# Unit tests
xcodebuild test \
  -project BabyLove.xcodeproj \
  -scheme BabyLoveTests \
  -destination 'platform=iOS Simulator,name=iPhone 17'

# UI tests
xcodebuild test \
  -project BabyLove.xcodeproj \
  -scheme BabyLoveUITests \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Auto-Iteration Agent

The `agent/` directory contains a Python loop that uses Claude Opus 4.6 to continuously analyse and improve the app:

```bash
cd agent
source venv/bin/activate
python loop.py        # iterate every 10s
python loop.py 30     # iterate every 30s
```

Press `Ctrl+C` once to stop gracefully after the current iteration, twice to force quit.

## License

MIT
