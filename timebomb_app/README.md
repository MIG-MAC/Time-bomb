# timebomb_app

Application Flutter pour le jeu Time Bomb avec intégration du core Rust via FFI.

## Architecture

- **Flutter/Dart** : Interface utilisateur cross-platform
- **Rust (time_bomb_core)** : Logique métier et communication BLE
- **FFI Bridge** : 
  - iOS : MethodChannel (Swift ↔ Rust)
  - Android/macOS : FFI direct (Dart ↔ Rust)

## Structure des bibliothèques natives

```
libtime_bomb/
├── ios/
│   ├── libtime_bomb_core_ios_arm64.a          # Device
│   ├── libtime_bomb_core_ios_sim_arm64.a      # Simulator (Apple Silicon)
│   ├── libtime_bomb_core_ios_sim_x86_64.a     # Simulator (Intel)
│   └── libtime_bomb_core_ios_sim_universal.a  # Simulator (universal)
└── android/
    ├── arm64-v8a/libtime_bomb_core.so
    ├── armeabi-v7a/libtime_bomb_core.so
    └── x86_64/libtime_bomb_core.so
```

## Rebuilding Native Libraries

Pour recompiler les bibliothèques Rust et les synchroniser automatiquement :

```bash
./scripts/build_native_libs.sh
```

Ce script :
1. Compile les libs iOS (device + simulator)
2. Crée la lib universelle pour le simulator
3. Compile les libs Android (3 ABIs)
4. Synchronise `android/app/src/main/jniLibs/`

**Prérequis** :
- Rust : `rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios`
- Android : `cargo install cargo-ndk` + Android NDK installé

## Installation & Lancement

### iOS
```bash
flutter doctor
flutter pub get
cd ios && pod install && cd ..
flutter run
```

### Android
```bash
flutter pub get
flutter build apk --debug
# ou
flutter run
```

## Développement

- **FFI Service** : `lib/services/time_bomb_core_ffi.dart`
- **BLE Wrapper** : `lib/services/nearby_service_wrapper.dart`
- **iOS Bridge** : `ios/Runner/AppDelegate.swift`
- **Rust Core** : `../../time_bomb_core/`