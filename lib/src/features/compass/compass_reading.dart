/// One reading of the compass given by the system (card « Boussole
/// instable », 30 Oct 2026): degrees from magnetic north, clockwise; accuracy
/// in degrees when the system gives it; [status] of Android (0 unreliable,
/// 1 low, 2 medium, 3 high; -1 elsewhere). [headingDeg] null: the system has
/// no valid heading yet (iPhone to calibrate).
class CompassReading {
  final double? headingDeg; final double? accuracyDeg; final int status;
  const CompassReading(this.headingDeg,{this.accuracyDeg,this.status=-1});
}
