import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'ui/app.dart';
import 'config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize configuration
  await AppConfig.initialize();
  
  runApp(
    ProviderScope(
      child: TradingBotApp(),
    ),
  );
}

class TradingBotApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Multi-Agent Trading Platform',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        textTheme: GoogleFonts.interTextTheme(
          Theme.of(context).textTheme,
        ),
      ),
      home: DashboardApp(),
    );
  }
}