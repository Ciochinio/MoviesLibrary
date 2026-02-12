## Uwaga: projekt desktop-only
Ten projekt celowo wspiera tylko **Windows + macOS**.

## Pierwsze przygotowanie projektu (jeśli pobierasz jako ZIP)

Ten ZIP zawiera kod w `lib/` i `pubspec.yaml`. Aby wygenerować pliki platformowe (windows/macos),
wykonaj w katalogu projektu:

```bash
flutter create .
flutter pub get
```

Następnie uruchom:
```bash
flutter run -d windows
# lub
flutter run -d macos
```

Jeśli `flutter create .` nadpisze część plików, zachowaj istniejące `lib/` i `pubspec.yaml` z tego projektu.
