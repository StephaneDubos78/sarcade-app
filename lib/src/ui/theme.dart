/// SARCADE look (mock-up « Interface futuriste », validated 27 Oct 2026):
/// « salle de crise » night theme, map first, panels over it; a light day
/// theme for sunlight on the field. Three colours carry the meaning, each
/// with a label or an icon too: cyan normal, amber urgent or to watch, red
/// immediate.
library;

import 'package:flutter/material.dart';

class SarcadeColors {
  static const ground=Color(0xFF070B10), panel=Color(0xFF0C1219), panelBorder=Color(0xFF1E2C38);
  static const cyan=Color(0xFF3DD6F5), onCyan=Color(0xFF04232C), amber=Color(0xFFFFB020), red=Color(0xFFFF4D5E);
  static const aprs=Color(0xFFB48CFF), text=Color(0xFFE6EEF5), muted=Color(0xFFB9C6D2);
}

/// Day or night, chosen on the device; « system » follows the device.
final themeMode=ValueNotifier<ThemeMode>(ThemeMode.system);

/// Automatic by default (decision of the project owner, 28 Oct 2026).
ThemeMode themeModeFrom(String? v)=>switch(v){'light'=>ThemeMode.light,'dark'=>ThemeMode.dark,_=>ThemeMode.system};
String themeModeName(ThemeMode m)=>switch(m){ThemeMode.light=>'light',ThemeMode.system=>'system',_=>'dark'};

ThemeData nightTheme(){
  const scheme=ColorScheme(brightness:Brightness.dark,
    primary:SarcadeColors.cyan,onPrimary:SarcadeColors.onCyan,
    primaryContainer:Color(0xFF0D2630),onPrimaryContainer:Color(0xFFBFF1FF),
    secondary:SarcadeColors.aprs,onSecondary:Color(0xFF1B1430),
    secondaryContainer:Color(0xFF1B1430),onSecondaryContainer:Color(0xFFE6DCFF),
    tertiary:SarcadeColors.amber,onTertiary:Color(0xFF2A1C05),
    tertiaryContainer:Color(0xFF2A1C05),onTertiaryContainer:Color(0xFFFFE2A8),
    error:SarcadeColors.red,onError:Colors.white,errorContainer:Color(0xFF3A0E15),onErrorContainer:Color(0xFFFFD6DA),
    surface:SarcadeColors.panel,onSurface:SarcadeColors.text,onSurfaceVariant:SarcadeColors.muted,
    surfaceContainerLowest:SarcadeColors.ground,surfaceContainerLow:Color(0xFF0A0F15),surfaceContainer:Color(0xFF0F1720),
    surfaceContainerHigh:Color(0xFF121B24),surfaceContainerHighest:Color(0xFF16212B),
    outline:Color(0xFF2A3A48),outlineVariant:SarcadeColors.panelBorder);
  return _base(scheme);
}

ThemeData dayTheme()=>_base(ColorScheme.fromSeed(seedColor:const Color(0xFF0E7490),brightness:Brightness.light));

ThemeData _base(ColorScheme scheme)=>ThemeData(useMaterial3:true,colorScheme:scheme,
  scaffoldBackgroundColor:scheme.brightness==Brightness.dark?SarcadeColors.ground:scheme.surface,
  cardTheme:CardThemeData(color:scheme.surfaceContainer,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(16),side:BorderSide(color:scheme.outlineVariant))),
  chipTheme:ChipThemeData(shape:StadiumBorder(side:BorderSide(color:scheme.outline))),
  floatingActionButtonTheme:FloatingActionButtonThemeData(backgroundColor:scheme.surfaceContainerHigh,foregroundColor:scheme.onSurface,
    shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14),side:BorderSide(color:scheme.outlineVariant))),
);

/// Panel floating over the map: rounded, bordered, nearly opaque (no blur:
/// too slow in the web app and on old phones).
BoxDecoration glass(BuildContext context,{double radius=20,Color? border}){
  final s=Theme.of(context).colorScheme;
  return BoxDecoration(color:s.surface.withValues(alpha:0.92),borderRadius:BorderRadius.circular(radius),
    border:Border.all(color:border??s.outlineVariant),
    boxShadow:const [BoxShadow(blurRadius:12,color:Color(0x33000000))]);
}
