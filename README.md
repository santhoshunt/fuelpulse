# ⛽ FuelPulse

**Offline fuel fill-up tracker with segment-based km/L efficiency analysis and brand comparison.**

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.11-0175C2?logo=dart)](https://dart.dev)
[![License: GPL-3.0](https://img.shields.io/badge/License-GPL--3.0-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20Web%20%7C%20Desktop-green)]()

---

## Overview

FuelPulse helps you track every fuel fill-up, calculate **real-world mileage** per segment, compare efficiency across fuel brands, and estimate how much fuel is left in your tank — all **100 % offline** with no accounts or cloud sync.

A companion **PWA** (Progressive Web App) is also included for quick browser-based access.

## Features

| Feature | Description |
|---|---|
| **Segment-based efficiency** | Calculates km/L between consecutive full-tank entries — shows the exact *"X km ÷ Y L"* breakdown |
| **Brand comparison** | Ranks fuel brands by average efficiency with visual bars and delta indicators |
| **Tank level estimation** | Forward-walk model estimates remaining litres at each fill-up |
| **Full / Partial fill tracking** | Handles both full-tank and partial-fill entries correctly |
| **CSV import / export** | Backup and restore your data via CSV files |
| **Custom brand colours** | Assign a colour to each fuel brand for quick visual identification |
| **Dark glossy UI** | Performant CustomPaint-based glossy card design — no BackdropFilter overhead |
| **Smooth transitions** | Fade + slide page routes, scroll-aware staggered list animations |
| **Offline-first** | SQLite local database — works without internet |
| **PWA companion** | Lightweight browser version using localStorage |

## Screenshots

<!-- Add your screenshots here -->
<!-- ![Home Screen](screenshots/home.png) -->
<!-- ![Stats Screen](screenshots/stats.png) -->

## Tech Stack

- **Framework:** Flutter (Dart)
- **Database:** SQLite via [sqflite](https://pub.dev/packages/sqflite)
- **State management:** StatefulWidget + setState (lightweight, no external state library)
- **Preferences:** [shared_preferences](https://pub.dev/packages/shared_preferences)
- **CSV:** [csv](https://pub.dev/packages/csv) + [share_plus](https://pub.dev/packages/share_plus)
- **Theming:** Custom `ThemeManager` with dynamic brand colours via [flutter_colorpicker](https://pub.dev/packages/flutter_colorpicker)
- **PWA:** Vanilla HTML/CSS/JS + Service Worker

## Project Structure

```
lib/
├── main.dart                  # App entry, theme setup, DB init
├── db/
│   └── database_helper.dart   # SQLite CRUD operations
├── models/
│   ├── fuel_log.dart          # FuelLog data model
│   └── theme_preference.dart  # Theme/colour preferences model
├── screens/
│   ├── home_screen.dart       # Main log list + summary banner
│   ├── add_entry_screen.dart  # Add new fuel entry
│   ├── edit_entry_screen.dart # Edit existing entry
│   ├── stats_screen.dart      # Brand ranking + stat cards
│   └── settings_screen.dart   # Tank capacity, CSV, theme
├── utils/
│   ├── efficiency_calculator.dart  # Segment-based km/L calculator
│   ├── tank_level_calculator.dart  # Estimated fuel-in-tank model
│   ├── csv_helper.dart             # CSV import/export
│   ├── page_routes.dart            # Smooth fade+slide transitions
│   ├── theme_manager.dart          # Dynamic theme/colour manager
│   └── constants.dart              # App-wide constants
└── widgets/
    ├── glossy_card.dart        # CustomPaint glossy card container
    ├── fuel_log_tile.dart      # Individual log entry tile
    ├── stat_card.dart          # Summary statistic card
    ├── brand_rank_tile.dart    # Brand ranking row
    ├── brand_badge.dart        # Colour-coded brand chip
    ├── fuel_gauge.dart         # Fuel gauge visual
    ├── color_swatch_picker.dart # Brand colour picker
    └── mode_switch.dart        # Theme mode toggle
```

## Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) ≥ 3.11
- Android Studio / VS Code with Flutter extension
- An Android/iOS device or emulator

### Install & Run

```bash
# Clone the repository
git clone https://github.com/santhoshunt/fuelpulse.git
cd fuelpulse

# Install dependencies
flutter pub get

# Run on connected device / emulator
flutter run
```

### Build Release APK

```bash
flutter build apk --split-per-abi
```

The ARM64 APK will be at:
```
build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

## PWA

A standalone Progressive Web App lives in the `../fuel-efficiency-pwa/` directory. Open `index.html` in any browser or deploy to any static host.

## How Efficiency Is Calculated

FuelPulse uses **segment-based calculation** between consecutive full-tank entries:

1. A *segment* starts when you fill the tank to FULL.
2. It ends at the **next** FULL fill-up.
3. **Efficiency = distance driven in segment ÷ litres pumped at the closing fill-up.**
4. Partial fills within a segment are accumulated into the closing total.

This gives you the truest real-world mileage per fuel brand.

## Contributing

Contributions are welcome! Please open an issue first to discuss what you'd like to change.

1. Fork the repo
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the **GNU General Public License v3.0** — see the [LICENSE](LICENSE) file for details.

---

<p align="center">
  Built with ❤️ and Flutter
</p>
