import 'package:flutter/material.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:momentum/providers/scheduler_provider.dart';
import 'package:provider/provider.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'screens/dashboard.dart';
import 'services/notification_service.dart';
import 'utils/theme.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize timezone database.

  // Load timezone database.
  tz.initializeTimeZones();

  // Get the actual device timezone.
  final timezoneInfo = await FlutterTimezone.getLocalTimezone();

  // Tell timezone package which timezone is local.
  tz.setLocalLocation(tz.getLocation(timezoneInfo.identifier));

  final schedulerProvider = SchedulerProvider();

  await NotificationService.instance.initialize(
    onAction: (actionId, payload) {
      switch (actionId) {
        case "accountability_yes":
          schedulerProvider.answeredYes();
          break;

        case "accountability_no":
          schedulerProvider.answeredNo();
          break;

        case "task_completed_yes":
          schedulerProvider.taskCompletedYes();
          break;

        case "task_completed_no":
          schedulerProvider.taskCompletedNo();
          break;
      }
    },
  );

  runApp(
    ChangeNotifierProvider.value(
      value: schedulerProvider,
      child: const MomentumApp(),
    ),
  );
}

class MomentumApp extends StatelessWidget {
  const MomentumApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: "Momentum",
      theme: AppTheme.dark,
      home: const Dashboard(),
    );
  }
}
