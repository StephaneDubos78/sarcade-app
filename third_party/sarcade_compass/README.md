# sarcade_compass

Small SARCADE plugin: the heading computed by the system instead of the raw
accelerometer and magnetometer.

- Android: `Sensor.TYPE_ROTATION_VECTOR` (accelerometer + magnetometer +
  gyroscope fused by Android), `TYPE_GEOMAGNETIC_ROTATION_VECTOR` without
  gyroscope; accuracy from `values[4]` (estimated heading accuracy) and the
  sensor status.
- iPhone: `CLLocationManager` heading (`magneticHeading`, `headingAccuracy`),
  calibration screen of iOS allowed.

Events of the channel `org.sarcade/compass`: `[heading, accuracy, status]`,
heading in degrees from magnetic north (−1: not valid yet), accuracy in
degrees (−1: unknown), status 0–3 of Android (−1 on iPhone).
