# Repository Guidelines

## Project Structure & Module Organization

Syawla is a Flutter application for bottle registration, refills, rider deliveries, pickups, and payments, backed by a PHP/MySQL API.

- `lib/main.dart` starts `SyawlaApp`; `lib/screens/` groups interfaces by role or workflow.
- `lib/models/` holds data models, `lib/services/` handles API access, `lib/widgets/` contains reusable UI, and `lib/theme/` defines shared styling.
- `syawla_api/api/` groups PHP endpoints into `auth`, `bottles`, `refill`, and `rider`; `syawla_api/config/database.php` configures PDO.
- `test/` contains Flutter tests. Images live in `assets/images/` and are registered in `pubspec.yaml`.
- Platform folders contain Flutter runners. Do not edit generated `build/` or `.dart_tool/` files.

## Build, Test, and Development Commands

Use a Flutter SDK compatible with the Dart constraint `^3.13.2` in `pubspec.yaml`. Run from the repository root:

- `flutter pub get` — install dependencies.
- `flutter run` — launch on an available device or emulator.
- `flutter analyze` — run static analysis and configured Flutter lints.
- `dart format lib test` — format Dart sources and tests.
- `flutter test` — run the Flutter test suite.
- `flutter build apk` — build an Android release APK.
- `php -l syawla_api/api/bottles/register_bottle.php` — syntax-check a PHP endpoint; repeat for changed PHP files.

## Coding Style & Naming Conventions

Use two-space Dart indentation, `snake_case.dart` filenames, `UpperCamelCase` types, and `lowerCamelCase` members. Follow `flutter_lints` in `analysis_options.yaml`. Reuse theme constants and common widgets. Keep HTTP access in services and the base URL centralized in `ApiService`. Follow existing PHP four-space indentation and snake_case endpoint filenames.

## Testing Guidelines

Use `flutter_test` and name tests `*_test.dart`. Add regression coverage for changed workflows and error handling. No coverage threshold is configured. Run `php syawla_api/tests/bottle_condition_test.php` and `php syawla_api/tests/bottle_cycle_test.php` against a development database; fixtures are rolled back. Manually verify affected scanning and payment flows against a development API.

## Commit & Pull Request Guidelines

History uses informal action-oriented summaries such as “fix” and “added”; no strict prefix convention is evident. Write concise, focused summaries. PRs should describe behavior changes, link relevant issues, list validation results and limitations, and include screenshots for UI changes. Explain any API or database dependencies.

## Local Configuration

Serve `syawla_api/` through PHP/Apache with MySQL. Set the device-accessible URL in `lib/services/api_service.dart` and local database settings in `syawla_api/config/database.php`. Obtain the base database schema separately and apply SQL migrations in `syawla_api/migrations/` before using new endpoints. Never commit production credentials.
