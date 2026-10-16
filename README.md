# syawla

A new Flutter project.

## CodeIgniter mobile API

The app uses the CodeIgniter backend at
`http://192.168.1.76/alwaysweb-ci4/mobile/` by default. On a physical phone,
connect to the same Wi-Fi as the XAMPP computer. If its LAN address changes,
start the app with:

```text
flutter run --dart-define=SYAWLA_API_BASE_URL=http://YOUR_COMPUTER_IP/alwaysweb-ci4/mobile/
```

`ApiService` supplies this base URL to all mobile services. Login sends the
username and password to `api/auth/login.php`; the backend verifies the stored
password hash and returns a token. The app sends that token as a Bearer header
on later bottle, refill, and rider requests. Logging out clears it.

Android debug builds permit HTTP for local XAMPP testing. A deployed app should
use an HTTPS backend URL.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
