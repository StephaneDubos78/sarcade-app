# Platforms — v0.1

One Flutter code base; the CI builds every platform on each PR.

| Platform | Deliverable | Notes |
|---|---|---|
| **Windows** | `sarcade-windows-setup.exe` (Inno Setup, per-user or per-machine, FR/EN) and a portable ZIP, pre-release `windows-dev` | Unsigned until `WINDOWS_CERT_PFX` (base64) and `WINDOWS_CERT_PASSWORD` are placed in the GitHub secrets by the owner; the CI then signs with signtool and a timestamp. Data in `%LOCALAPPDATA%\SARCADE`. |
| **Android** | APK, pre-release `android-dev` (debug key) | Beacon from a location foreground service (positions screen off, permanent notification); notifications with an « urgent » channel (Android 13+ permission). Release signing key: to place in the secrets before the Play Store. |
| **ChromeOS** | Web app installed (PWA) — main channel; Android app as fallback | Hardware features optional (no touch screen or GPS required). PWA: SARCADE service worker so the app starts without network; installation and location need the server in HTTPS. |
| **Linux** | `sarcade-linux-x86_64.AppImage` and the `tar.gz` bundle | Also in the Linux environment of an x86-64 Chromebook. |
| **Web** | Served by the SARCADE server itself (`web-dev` pre-release embedded in the Docker image) | Browser notifications; local data in IndexedDB. |
| iOS | Unsigned build (proves compilation) | Signing and TestFlight once the Apple account exists. |

## Client updates (note « Mises à jour et sécurité »)
The local server can distribute the Windows installer, the AppImage and the
APK (`PUT /admin/clients/{platform}/package`); the client offers the download
when invited, and requires it 2 hours later outside an active event.

## Not yet tried on a device
The builds are proven by the CI; a manual test on a Windows PC, an Android
phone and a Chromebook is needed before a demonstration.
