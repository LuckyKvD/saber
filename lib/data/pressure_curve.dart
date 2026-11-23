import 'dart:math' as math;

import 'package:saber/data/prefs.dart';

/// Wendet die eingestellte Druckkurve auf einen normierten Stiftdruck
/// (0 bis 1) an.
///
/// Die Kurve ist `druck ^ (prozent / 100)`:
/// - unter 100 (weich): schon leichter Druck ergibt kräftige Striche,
/// - 100 (normal): unverändert,
/// - über 100 (hart): es braucht mehr Druck für kräftige Striche.
///
/// Wirkt nur auf Werkzeuge, die den Druck auswerten (z. B. Füller).
double applyPressureCurve(double pressure) {
  final percent = stows.pressureCurve.value;
  if (percent == 100) return pressure;
  final clamped = pressure.clamp(0.0, 1.0);
  return math.pow(clamped, percent / 100).toDouble();
}
