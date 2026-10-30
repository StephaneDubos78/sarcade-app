import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/messages/conversations.dart';
import 'package:sarcade_app/src/ui/choice_pills.dart';
import 'package:sarcade_app/src/ui/overlay_page.dart';
import 'package:sarcade_app/src/ui/theme.dart';
import 'package:sarcade_app/src/ui/action_buttons.dart';

void main(){
  test('avatar initials: name, terminal or callsign',(){
    expect(avatarInitials('device-demo'),'DD');
    expect(avatarInitials('PCO-Web'),'PW');
    expect(avatarInitials('F4JPO'),'JPO');
    expect(avatarInitials('F4JPO-9'),'JPO');
    expect(avatarInitials('TEST'),'TE');
  });

  test('one acknowledgement: read / received',(){
    expect(ackCount(read:3,received:4),'3/4');
    expect(ackCount(read:0,received:2),'2');
  });

  test('other actions: discreet dark pill without border, day and night (lot 9)',(){
    for(final t in [dayTheme(),nightTheme()]){
      final st=t.outlinedButtonTheme.style!;
      expect(st.side?.resolve({}),BorderSide.none);
      expect(st.backgroundColor?.resolve({}),t.colorScheme.surfaceContainerHighest);
      expect(st.foregroundColor?.resolve({}),t.colorScheme.onSurface);
      expect(t.chipTheme.side,BorderSide.none);
    }
  });

  testWidgets('icon-only button: a small round, tooltip kept',(tester) async {
    var n=0;
    await tester.pumpWidget(MaterialApp(theme:nightTheme(),home:Scaffold(body:Center(child:RoundIconButton(icon:Icons.add,tooltip:'Ajouter',onPressed:()=>n++)))));
    await tester.tap(find.byTooltip('Ajouter'));
    expect(n,1);
    expect(tester.getSize(find.byType(IconButton)).width,lessThanOrEqualTo(48));
  });

  testWidgets('choice pills: a check on the chosen one, a touch chooses',(tester) async {
    var v='b';
    await tester.pumpWidget(MaterialApp(theme:dayTheme(),home:Scaffold(body:StatefulBuilder(builder:(c,set)=>ChoicePills<String>(
      choices:const [(value:'a',label:'Silencieux',icon:null),(value:'b',label:'Normal',icon:null)],
      selected:v,onSelected:(x)=>set(()=>v=x))))));
    expect(find.byIcon(Icons.check),findsOneWidget);
    await tester.tap(find.text('Silencieux'));
    await tester.pump();
    expect(v,'a');
  });

  testWidgets('overlay page: a window on a computer, closed by Escape',(tester) async {
    tester.view.physicalSize=const Size(1400,900); tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home:Builder(builder:(c)=>Scaffold(body:Center(child:FilledButton(
      onPressed:()=>showOverlayPage<void>(c,(_)=>Scaffold(appBar:AppBar(title:const Text('Main courante')))),child:const Text('Ouvrir')))))));
    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog),findsOneWidget);
    expect(find.byIcon(Icons.close),findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog),findsNothing);
  });
}
