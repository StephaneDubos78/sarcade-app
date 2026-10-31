/// Stable identifiers for the automated tests (card B of the cinématique
/// review, 31 Oct 2026): every button that opens something carries one,
/// so the tests find it whatever the language or the wording. Read as the
/// `flt-semantics-identifier` attribute on the web and through
/// [Semantics.properties] in the Flutter tests; never shown to the user.
library;

import 'package:flutter/widgets.dart';

/// Wraps [child] in a semantics node named [id] (for example `nav.tools`).
Widget withId(String id,Widget child)=>Semantics(container:true,identifier:id,child:child);

/// Finder predicate of the Flutter tests.
bool hasTestId(Widget w,String id)=>w is Semantics&&w.properties.identifier==id;
