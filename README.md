# Hockey Shot Tracker

A hockey shot-practice app that counts shots automatically by listening for the sound of a stick hitting the puck, instead of requiring a manual tap per shot.

Flutter app, Android + iOS.

## Ticket 01 status: mic capture proof-of-concept

This slice proves continuous raw PCM mic capture end to end with a debug level
meter, including while backgrounded/locked. It was built **without a local
Flutter SDK install** (not present on the build machine), so the Dart-only
parts (`pubspec.yaml`, `lib/`, `test/`) were hand-written and are otherwise
complete, but nothing has been run through `flutter pub get` / `analyze` /
`test` yet. See the parent task report for full detail; short version below.

### One-time setup a human needs to run

1. Install the Flutter SDK, then from this directory:
   ```
   flutter pub get
   flutter create .
   ```
   `flutter create .` fills in files intentionally left out by hand because
   they're generated/binary boilerplate that's risky to fake correctly:
   - `android/gradlew`, `gradlew.bat`, `gradle/wrapper/gradle-wrapper.jar`
   - `android/local.properties` (machine-specific, must not be committed)
   - Android launcher icons (`android/app/src/main/res/mipmap-*`)
   - `ios/Runner.xcodeproj/`, `ios/Runner.xcworkspace/` (Xcode's generated
     project format — not safely hand-authorable)
   - `ios/Runner/Base.lproj/*.storyboard`, `ios/Flutter/*.xcconfig`

   `flutter create .` does not overwrite files that already exist, so the
   hand-written `AndroidManifest.xml`, `build.gradle`, `Info.plist`, `Podfile`,
   `MainActivity.kt`, and `AppDelegate.swift` in this repo should survive —
   diff them against what a fresh `flutter create` would produce if anything
   looks off.
2. `cd ios && pod install` (iOS only, needs a Mac).
3. `flutter analyze` and `dart format --output=none --set-exit-if-changed .`
4. `flutter test`
5. `flutter run` on a physical device to verify the debug meter screen, and
   manually check background/lock-screen persistence (emulators/simulators
   are unreliable for real mic input and OS background-kill behavior).
