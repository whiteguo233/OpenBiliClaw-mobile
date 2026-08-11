# Repository Guidelines

## Project Structure & Module Organization

This repository is currently a Flutter-client bootstrap. The root contains project guidance (`README.md`, `CONTRIBUTING.md`), licensing, and the GitHub PR template. When the client is imported, keep the Flutter project at the repository root and use the conventional layout:

- `lib/`: application code, organized by feature or screen.
- `test/`: unit and widget tests; `integration_test/` for device-level flows.
- `assets/`: bundled images, fonts, and other static resources.
- `android/` and `ios/`: platform-specific configuration and native code.

Do not commit `.dart_tool/`, `build/`, local configuration, or generated signing material.

## Build, Test, and Development Commands

Run commands from the repository root after Flutter files are present:

```bash
flutter pub get                 # Install Dart/Flutter dependencies
flutter run                     # Launch on a connected device or emulator
flutter analyze                 # Run static analysis and lint checks
flutter test                    # Run unit and widget tests
flutter build apk --release     # Build a release Android APK
```

The current bootstrap does not yet contain a `pubspec.yaml`, so Flutter commands will become available when the client is added.

## Coding Style & Naming Conventions

Use Dart null safety, two-space indentation, and `dart format` before committing (`dart format .`). Name files and directories with `lower_snake_case`; use `UpperCamelCase` for classes, widgets, and enums, and `lowerCamelCase` for variables, methods, and parameters. Prefer small feature-focused widgets, immutable state where practical, and `const` constructors. Keep analyzer warnings at zero and follow the repository’s configured `flutter_lints` rules when added.

## Testing Guidelines

Name tests `*_test.dart` and place them beside the relevant test category under `test/`. Add regression coverage for behavior changes, especially API, authentication, and backend compatibility. Run `flutter analyze` and `flutter test`; there is no numeric coverage threshold yet. Manually verify supported platforms and OS versions and record them in the PR.

## Commit & Pull Request Guidelines

Use concise Conventional Commit subjects, matching the existing history and contribution guide: `feat:`, `fix:`, `docs:`, or `chore:` (for example, `feat: import Flutter mobile client`). Open PRs against `main` with a change summary, tested backend version, API/authentication notes, platform and OS coverage, and test results. Include screenshots for UI changes. Never include API keys, cookies, passwords, backend credentials, personal configuration, certificates, or signing files.
