# Hockey Shot Tracker

A hockey shot-practice app that counts and analyses shots automatically with the phone's camera, using the sound of the stick hitting the puck to confirm them, instead of requiring a manual tap per shot.

Flutter app, Android + iOS.

## How shots are detected

Mount the phone sideways behind or beside the shooter so the shooting spot
and the net are both in view, then mark both once under
Settings → Camera setup. The app only captures while it's open, and keeps the
screen on during a session.

- **Shot (camera, `lib/video/`):** each frame's luma plane is shrunk to a
  192-wide grid. A dark, puck-sized, compact blob sitting in the shooting spot
  that vanishes (a released puck blurs out of the frame almost at once) and
  doesn't reappear within 400 ms is a shot. If it reappears, it was only
  hidden by the stick or a skate. The first movement inside the net area
  afterwards gives flight time, speed (using the shooting distance you set)
  and a 3×3 target zone.
- **Confirmation (mic):** a camera shot counts only if the mic heard an impact
  within 350 ms of release. This can be turned off in Settings.
- **Bar down (mic):** unchanged. It still comes from the sound classifier
  (bar ping + "Eww").
- **Fallback:** if the camera isn't set up or can't open, shots are counted
  by the sound classifier alone, as before.

Known limits of this first, untrained version: it needs a light shooting pad
against a black puck; the shooter shouldn't stand between the camera and the
net; and speed is coarse, since 30–60 fps frame timing limits it to roughly
±10%.

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
