import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/bearings/bearing_mouse_hud.dart';
import 'package:sarcade_app/src/features/settings/diagnostics_panel.dart';
import 'package:sarcade_app/src/features/tools/tools_page.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

void main(){
  setUp(()=>S.setLanguage('fr'));
  tearDown(()=>S.setLanguage('fr'));

  test('Diagnostic: the problems are the lines in red or orange',(){
    const lines=<DiagLine>[
      (block:'Liaisons',label:'Éléments non envoyés',value:'2',state:'red'),
      (block:'Liaisons',label:'Temps de réponse',value:'40 ms',state:'green'),
      (block:'Cet appareil',label:'GPS',value:'—',state:'orange'),
      (block:'Cet appareil',label:'Réseau',value:'wifi',state:null),
    ];
    expect(diagnosticProblems(lines).map((l)=>l.label),['Éléments non envoyés','GPS']);
    expect(diagnosticProblems(lines.where((l)=>l.state!='red'&&l.state!='orange')),isEmpty);
    expect(S.t('diag.allGood'),'Tout fonctionne');
    expect(diagnosticsAlert(),isFalse);
  });

  test('Outils: « Itinéraires » and the two groups',(){
    expect(S.t('routes.menu'),'Itinéraires');
    expect(S.t('tools.groupField'),'Sur le terrain');
    expect(S.t('tools.groupPc'),'Au PC');
  });

  testWidgets('Outils: « Sur le terrain » then « Au PC », in the given order',(tester) async {
    void none(){}
    await tester.pumpWidget(MaterialApp(home:ToolsPage(items:[
      ToolItem(icon:Icons.cloud_outlined,title:'Météo',subtitle:'',color:Colors.orange,onTap:none),
      ToolItem(icon:Icons.tv,title:'Afficher sur une TV',subtitle:'',color:Colors.purple,onTap:none,group:ToolGroup.pc),
      ToolItem(icon:Icons.route,title:'Itinéraires',subtitle:'',color:Colors.green,onTap:none),
    ])));
    double y(String text)=>tester.getTopLeft(find.text(text)).dy;
    expect(y('Sur le terrain'),lessThan(y('Météo')));
    expect(y('Itinéraires'),lessThan(y('Au PC')));
    expect(y('Au PC'),lessThan(y('Afficher sur une TV')));
  });

  testWidgets('Relevé à la souris: one line, help behind the ⓘ',(tester) async {
    S.setLanguage('fr');
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:MouseBearingHud(trueDeg:42,magneticDeg:40,position:null,accuracyM:null,
      time:DateTime(2026,10,30,12,44,5),onClose:(){},decoration:const BoxDecoration()))));
    expect(find.text('042°'),findsOneWidget);
    expect(find.textContaining('12:44:05'),findsOneWidget);
    expect(find.byTooltip(S.t('bearings.aimMouseHelp')),findsOneWidget);
    expect(find.textContaining('SOURIS'),findsNothing);
  });
}
