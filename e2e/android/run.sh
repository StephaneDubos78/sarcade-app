#!/usr/bin/env bash
# Runs inside the Android emulator job (android-emulator-runner).
# 1. Grants the runtime permissions as soon as the test app is installed, so
#    that no system dialog (notifications, location) waits for a tap.
# 2. Runs the integration test against the server of the CI machine.
# 3. Reads the notifications shown by the app (scenario 9).
set -uo pipefail
PKG=org.sarcade.sarcade_app
(
  for i in $(seq 1 600); do
    if adb shell pm list packages | grep -q "$PKG"; then
      adb shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS 2>/dev/null
      adb shell pm grant "$PKG" android.permission.ACCESS_FINE_LOCATION 2>/dev/null
      adb shell pm grant "$PKG" android.permission.ACCESS_COARSE_LOCATION 2>/dev/null
    fi
    sleep 1
  done
) &
GRANTER=$!
adb emu geo fix 2.1204 48.8049 >/dev/null 2>&1 || true

flutter test integration_test/field_terminal_test.dart -d emulator-5554 \
  --dart-define=SARCADE_E2E_URL=http://10.0.2.2:8000 \
  --dart-define=SARCADE_E2E_EVENT_NAME="$SARCADE_E2E_EVENT_NAME"
status=$?
kill $GRANTER 2>/dev/null

mkdir -p e2e/android/out
adb shell dumpsys notification --noredact > e2e/android/out/notifications.txt 2>&1 || true
adb exec-out screencap -p > e2e/android/out/last-screen.png 2>/dev/null || true
if grep -q "E2E urgent from PCO" e2e/android/out/notifications.txt; then
  echo "Notification of the urgent message found"
else
  echo "::warning::Urgent message notification not found in dumpsys (app closed at the end of the test?) - see notifications.txt"
fi
exit $status
