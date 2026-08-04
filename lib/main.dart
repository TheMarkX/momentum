import 'package:flutter/material.dart';

import 'screens/dashboard.dart';
import 'utils/theme.dart';

void main() {
  runApp(const MomentumApp());
}

class MomentumApp extends StatelessWidget {
  const MomentumApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "Momentum",
      theme: AppTheme.dark,
      home: const Dashboard(),
    );
  }
}