import 'package:flutter/material.dart';
import 'config/app_config.dart';
import 'features/map/operational_map_page.dart';
import 'services/sarcade_api.dart';
import 'offline/local_store.dart';

class SarcadeApp extends StatelessWidget {
  final LocalStore store;
  const SarcadeApp({super.key,required this.store});

  @override
  Widget build(BuildContext context){
    final c=AppConfig.fromEnvironment();
    return MaterialApp(
      title:'SARCADE',
      debugShowCheckedModeBanner:false,
      theme:ThemeData(colorScheme:ColorScheme.fromSeed(seedColor:const Color(0xFF173A6A)),useMaterial3:true),
      home:c.eventId.trim().isEmpty
        ? _ConfigurationRequired(serverUrl:c.serverUrl)
        : OperationalMapPage(api:SarcadeApi(baseUrl:c.serverUrl),eventId:c.eventId,deviceId:c.deviceId,store:store),
    );
  }
}

class _ConfigurationRequired extends StatelessWidget {
  final String serverUrl;
  const _ConfigurationRequired({required this.serverUrl});
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('SARCADE')),
    body:Center(child:ConstrainedBox(
      constraints:const BoxConstraints(maxWidth:560),
      child:Card(child:Padding(
        padding:const EdgeInsets.all(24),
        child:Column(mainAxisSize:MainAxisSize.min,children:[
          const Icon(Icons.map_outlined,size:56),
          const SizedBox(height:16),
          Text('Aucun événement configuré',style:Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height:12),
          const Text('Cette V0.1 de développement doit être lancée avec un identifiant d’événement. La sélection d’événement sera intégrée à l’écran d’accueil.'),
          const SizedBox(height:12),
          SelectableText('Serveur : $serverUrl'),
        ]),
      )),
    )),
  );
}
