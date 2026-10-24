# Routes and navigation on the client — v0.1

Client side of server PRs #11 (routes) and #13 (navigation).

- **Routes**: « Routes et navigation » panel; new route (name, profile on foot
  or vehicle, legs straight or along paths), points added by tapping the map,
  one synchronised object per point (ADR-001). Per point: type (start,
  passage, checkpoint, supply, finish), approach radius (50 m by default),
  comment, leg drawing, order (up/down, `base_point_order` sent), deletion.
  Lengths per leg and cumulated. Legs along paths are computed by the server
  (asked at once when online, else later) and drawn dotted meanwhile.
- **Assigned routes**: assignment to a group (its team), changed only by the
  author and the PCO; the team receives the urgent message from the server.
- **Passages**: automatic within the approach radius of the next points of an
  active route while the Beacon is on; manual; « impracticable » report to
  the PCO. GPX export from the server.
- **Road closures** (PCO): drawn on the map, named, reopened or closed again;
  red dashed lines; avoided by every itinerary of the event.
- **Navigation**: long press on the map or « Navigate here » from a waypoint;
  by car, on foot, off-road (server, Valhalla) or straight line (distance and
  bearing). When the engine cannot be reached, a straight line is shown with
  a notice. Remaining distance, estimated arrival, next instruction; the
  itinerary is shared with the PCO (at start, every 30 s, arrival within
  30 m, cancellation).

## Navigation on the device (level 3) — decisions of 10 Oct 2026, 12 h
- The road graph prepared by the server (« SRG1 », department + 10 km) is
  downloaded automatically on Wi-Fi or on the local network of the PCO when
  the map opens, never on mobile data without consent (a banner offers it
  with its size); kept on the device, parsed off the main thread.
- The server stays first; when it cannot be reached, the itinerary is
  computed here (A* on travel time, same speeds as the server), with the
  mention « computed on the device ». Closed roads already received are
  avoided (roads meeting a closure at its ends stay open). Car, foot,
  off-road; simple instructions (start, turns, change of road, arrival).
- New itinerary when the operator leaves the planned one by more than 60 m
  (at most every 30 s), server first, device otherwise.

## Navigation app of the organisation (level 1)
- Setting received with `/clients/check` and the heartbeat, kept offline.
- The chosen app opens directly (Organic Maps `om://`, OsmAnd and Google
  Maps links, Apple Maps, Waze); when it is missing, a notice with the Play
  Store link, then the usual chooser. Google warning kept; Google Maps and
  Waze hidden from the iPhone list when the organisation hides them (the
  Android system chooser cannot be filtered).

## Variants and follow mode (decisions of 10 Oct 2026)

- **Up to two variants**, drawn in grey under the itinerary, with a chip
  each in the navigation card (« Variant 1 · +4 min · 12.3 km »); a tap on
  the grey line or on the chip makes it the itinerary followed (shared again
  with the PCO).
- From the server (Valhalla alternates, between two points), or computed on
  the device by **penalty**: the edges of the itineraries already found cost
  1.8 times more, then the variants nearly identical (85 % of their length
  within 30 m) or much longer (over 1.6 times the time) are dropped. No
  variants after an automatic re-route.
- **Follow mode**: the map stays centred on the operator and turns in the
  direction of travel, by the GPS course when moving (over 5 km/h), by the
  compass when stationary (true north, WMM declination).
  - **Phones and tablets**: automatic at the start of the navigation; when
    variants are shown, it starts as soon as the operator moves off (25 m)
    or taps a variant.
  - **Computers**: north up by default, « Turn in the direction of travel »
    option in the navigation card (kept on the device).
  - A gesture on the map (drag, pinch, wheel, keyboard) leaves the mode;
    **« Re-centre »** in the card comes back to it.
  - Drawing is off in follow mode (drawn shapes assume north up); the map
    comes back north up when the mode ends.
