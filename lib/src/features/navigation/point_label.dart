/// Default name of a point shown in the language of each device (card
/// « Vers Map point », 31 Oct 2026): a default name used to be stored in the
/// language of the device that created the object (« Map point » from a
/// computer in English). Empty names and the former stored defaults read
/// « Point de la carte » here, « Map point » on a device in English.
library;

import '../../l10n/strings.dart';

/// Default names stored before 31 Oct 2026 (every language of SARCADE).
const storedDefaultNames={'map point','point de la carte','point'};

bool isDefaultPointName(String? raw)=>raw==null||raw.trim().isEmpty||storedDefaultNames.contains(raw.trim().toLowerCase());

String pointLabel(String? raw)=>isDefaultPointName(raw)?S.t('nav.point'):raw!.trim();
