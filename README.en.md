# Sonorynth

An Android music player built with Flutter, featuring online playback, playlists, and word-synchronized lyrics.

[简体中文](README.md) · English

[Download](https://github.com/CLCTY/Sonorynth/releases) · [Report an issue](https://github.com/CLCTY/Sonorynth/issues) · [Contribute](CONTRIBUTING.md)

## Features

- Online search and recommendations, account sign-in, playlists, and favorites.
- Playback queue, audio-quality selection, sleep timer, and full-screen lyrics.
- LRC, QRC, YRC, and TTML lyrics with word highlighting, translations, and source ordering.
- Artwork-derived colors and a dark theme.

Tap the artwork on the player page to open full-screen lyrics. Alternative lyrics can be searched, and source priority can be changed in settings.

## Downloads and versions

Choose a version and architecture from [Releases](https://github.com/CLCTY/Sonorynth/releases). Pre-releases are preview builds. Where provided, SHA-256 files can check download integrity; they do not replace checking the release source.

The main branch, preview branches, and released APKs may differ. Include the version and installation source in bug reports. See [maintenance notes](docs/MAINTENANCE.md) for the recorded release history.

Online availability and audio quality depend on the service, endpoints, and account entitlements. Custom playback endpoints must be ones you are authorized to use; see the [endpoint format](docs/CUSTOM_AUDIO.md). Code licensing does not grant rights to music, lyrics, artwork, or third-party services.

## Development

Use Flutter with Dart 3.10 or later, Android SDK, and JDK 17. The Flutter SDK must satisfy the constraints in `pubspec.yaml`.

```sh
git clone https://github.com/CLCTY/Sonorynth.git
cd Sonorynth
flutter pub get
flutter analyze
flutter test
flutter run
```

Existing tests cover lyric parsing, cache models, request encryption, source resolution, and selected UI behavior. They do not establish live-service compatibility or verification of every device and release APK.

See [Android builds](docs/BUILDING.md) for release signing and APK generation. Keep signing material, account cookies, passwords, and personal data out of commits and issue reports.

## Contributions

Reproducible bug reports, test cases, documentation fixes, and focused patches are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.

## Licensing and third-party sources

The project-wide license has not yet been specified by the maintainer. Public source availability alone does not grant redistribution rights. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for identified third-party code, retained notices, and the review scope. The QRC decoder's MIT notice is retained.
