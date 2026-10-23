import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

void main(){
  tearDown(()=>S.setLanguage('fr'));

  test('French and English, English for other languages',(){
    S.setLanguage('fr');
    expect(S.t('tracking.title'),'Suivi de position');
    S.setLanguage('en');
    expect(S.t('tracking.title'),'Beacon');
    S.setLanguage('system',systemLanguage:'de');
    expect(S.lang,'en');
    S.setLanguage('system',systemLanguage:'fr');
    expect(S.lang,'fr');
  });

  test('placeholders and missing keys',(){
    S.setLanguage('fr');
    expect(S.t('sync.alert',{'n':3,'min':7}),'3 élément(s) non envoyé(s) depuis 7 min');
    expect(S.t('no.such.key'),'no.such.key');
  });
}
