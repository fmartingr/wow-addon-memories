import 'package:flutter/material.dart';

class WowJourneyApp extends StatelessWidget {
  const WowJourneyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WoW Journey',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8A6D3B)),
      ),
      home: Scaffold(
        appBar: AppBar(title: const Text('WoW Journey')),
        body: const SizedBox.shrink(),
      ),
    );
  }
}
