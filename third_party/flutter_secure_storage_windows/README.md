# flutter_secure_storage_windows (SARCADE copy)

Copy of [flutter_secure_storage_windows 3.1.2](https://github.com/juliansteenbakker/flutter_secure_storage/tree/v9.2.4/flutter_secure_storage_windows),
BSD-3-Clause (see LICENSE), used through `dependency_overrides` in `pubspec.yaml`.

Change: the native C++ part is removed. Upstream it only served the backward
compatibility with values stored by older versions in the Windows Credential
Manager, and it needs the ATL component of Visual Studio, missing on some
developer machines (`atlstr.h`, `atls.lib`). Values are stored, as upstream,
in a JSON file encrypted with DPAPI (`CryptProtectData`): only the Windows
user who wrote them can read them.

Remove this copy and the override when every build machine has ATL, or when
a later plugin version no longer needs it.
