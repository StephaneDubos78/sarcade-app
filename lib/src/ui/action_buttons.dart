/// Charte des boutons par rôle (validated on 30 Oct 2026, 10 h 46), rule 5:
/// an icon-only button (+ of APRS, grid / list of Fichiers, pencils…) is the
/// icon in a small discreet round, the same everywhere.
library;

import 'package:flutter/material.dart';

import 'theme.dart';

class RoundIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  const RoundIconButton({super.key,required this.icon,required this.tooltip,required this.onPressed,this.size=36});

  @override
  Widget build(BuildContext context){
    final s=Theme.of(context).colorScheme;
    return IconButton(tooltip:tooltip,onPressed:onPressed,icon:Icon(icon,size:size*0.55),
      style:IconButton.styleFrom(fixedSize:Size(size,size),minimumSize:Size(size,size),padding:EdgeInsets.zero,shape:const CircleBorder(),
        backgroundColor:roundIconBackground(s),foregroundColor:s.onSurface,
        disabledBackgroundColor:s.onSurface.withValues(alpha:0.06),disabledForegroundColor:s.onSurface.withValues(alpha:0.38)));
  }
}
