# Portable Media Library (Flutter) — V1.3 Desktop

Aplikacja Flutter (Windows + macOS) — **desktop-only** (bez iOS/Android) zgodna ze specyfikacją z rozmowy:
- tryb portable: **/App** + **/Library** na jednym nośniku
- import (kopiowanie do /Library/files)
- 2-poziomowe kategorie (poziom 2 obowiązkowy) + **Stash**
- jeden element w dokładnie jednej subkategorii
- tagi globalne (tekstowe), filtrowanie AND
- duplikaty: pytanie (dodaj jako osobny plik do Stash / nie dodawaj)
- notatki + załączniki obrazów (kopiowane do /Library/attachments)
- masowe operacje: tagi, przenoszenie, usuwanie

> Uwaga: w V1 podgląd wideo jest przez **Otwórz w systemie** (open_filex).
> Podgląd obrazów jest wbudowany. (Wideo player można dodać później jako V1.1)

## Zakres platform
- Wspierane: **Windows, macOS**
- Niewspierane: iOS/Android (dostęp mobilny przez MEGA/itp.)

## Wymagania
- Flutter SDK (stable)
- Windows: Visual Studio (Desktop development with C++)
- macOS: Xcode

## Uruchomienie (dev)
```bash
flutter pub get
flutter run -d windows
# albo
flutter run -d macos
```

## Tryb portable
Aplikacja przy starcie próbuje znaleźć folder `Library` obok uruchamialnego pliku:
- jeśli istnieje: używa go jako biblioteki
- jeśli nie: poprosi o wybranie/utworzenie biblioteki

Zalecany układ na pendrive:
- /App  -> build aplikacji
- /Library -> dane (db, files, thumbs, attachments)

## Build (release)
```bash
flutter build windows --release
flutter build macos --release
```

Skopiuj wynik do `/App` na nośniku oraz utwórz `/Library`.

## Struktura /Library
- db/library.sqlite
- files/...
- thumbs/...
- attachments/...
- settings.json (zapisywany automatycznie)

## Licencja
Do własnego użytku / prototypu.
