/// Voice messaging in the car, background side (lot 1a): answers sent at
/// once, real text after a wake-up. See car_context.dart.
library;

export 'car_context.dart';
export 'car_background_io.dart'
    if (dart.library.js_interop) 'car_background_web.dart';
