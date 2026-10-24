# Measure to a designated point and « Open in… » — v0.1

Spec: « Mesure de distance vers un point désigné » (validated 10 Oct 2026)
and navigation level 1 of « Navigation ».

- Designate a point: long press (phone, tablet) or right click (PC,
  Chromebook) → « Measure to here »; or « Go to coordinates » in any of the
  three formats.
- Dashed line from my position (updated continuously) with distance and
  true azimuth; card with distance and GPS accuracy (« ± 8 m »), azimuth
  true and magnetic, the point in decimal degrees (default), degrees and
  decimal minutes, and QTH locator, each copyable; main format chosen by the
  operator.
- Magnetic declination from the World Magnetic Model 2025 embedded in the
  app (NOAA/BGS, public domain, valid until 2030), checked in the tests
  against the NOAA reference implementation; manual override kept in the
  controller (setting screen to come).
- Guidance arrow oriented by the phone compass (accelerometer and
  magnetometer, tilt compensated).
- Without GPS: origin chosen among my position, an operator or team, or a
  point of the map; « position unknown » / « position X min old » shown.
- Actions: save as POI, send in a message (coordinates, distance, azimuth at
  sending time), fit, open in another app.
- Personal: nothing shared or logged unless saved as POI or sent.
- « Open in… »: Android chooser (`geo:` link: Organic Maps, OsmAnd, Google
  Maps, Waze…), on iPhone Organic Maps and OsmAnd first, Apple Maps, and
  Google with a warning; PC and browser: OpenStreetMap. The organisation
  setting of the recommended app is not done yet.
