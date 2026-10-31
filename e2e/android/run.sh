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
# Notifications are read while the test runs: the app is removed at the end.
mkdir -p e2e/android/out
(
  for i in $(seq 1 1800); do
    adb shell dumpsys notification --noredact 2>/dev/null | grep -E "android.title=|android.text=" >> e2e/android/out/notifications.txt
    sleep 1
  done
) &
WATCHER=$!
adb emu geo fix 2.1204 48.8049 >/dev/null 2>&1 || true

flutter test integration_test/field_terminal_test.dart -d emulator-5554 \
  --dart-define=SARCADE_E2E_URL=http://10.0.2.2:8000 \
  --dart-define=SARCADE_E2E_EVENT_NAME="$SARCADE_E2E_EVENT_NAME" 2>&1 | tee /tmp/e2e-android.log
status=${PIPESTATUS[0]}
# The raw log is not always readable: surface the failure as annotations.
if [ "$status" -ne 0 ]; then
  # One annotation (GitHub keeps 10 per step): lines joined with %0A.
  msg=$(awk '/EXCEPTION CAUGHT/{on=1} on && NF{print; n++} n>=40{exit}' /tmp/e2e-android.log | sed 's/%/%25/g' | awk '{printf "%s%%0A", $0}')
  echo "::error title=integration test::${msg}"
fi
kill $GRANTER $WATCHER 2>/dev/null

mkdir -p e2e/android/out
if [ "$status" -ne 0 ]; then
  logs=$(adb logcat -d -s flutter:V | tail -40 | sed 's/%/%25/g' | awk '{printf "%s%%0A", $0}')
  echo "::notice title=flutter logcat::${logs}"
fi
adb exec-out screencap -p > e2e/android/out/last-screen.png 2>/dev/null || true
if grep -q "E2E urgent from PCO" e2e/android/out/notifications.txt; then
  echo "::notice title=notification::$(grep -m1 -B1 'E2E urgent from PCO' e2e/android/out/notifications.txt | tr -d '\r' | tr '\n' ' ')"
else
  # The integration test already checked the notification through the
  # plugin (getActiveNotifications): only a missed sample remains here.
  echo "::error title=notification::urgent message notification not shown by the app (watcher: $(wc -l < e2e/android/out/notifications.txt) lines read)"
  status=1
fi
exit $status
