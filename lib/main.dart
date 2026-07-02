import 'package:flutter/material.dart';
import 'ui/dashboard.dart';

void main() => runApp(const FluxBoardApp());

class FluxBoardApp extends StatelessWidget {
  const FluxBoardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FluxBoard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0E17),
      ),
      home: const Dashboard(),
    );
  }
}
