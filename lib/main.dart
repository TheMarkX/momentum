import 'package:flutter/material.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:momentum/providers/scheduler_provider.dart';
import 'package:momentum/services/scheduler_persistance.dart';
import 'package:provider/provider.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'screens/dashboard.dart';
import 'services/notification_service.dart';
import 'utils/theme.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------------------
  // TIMEZONE
  // ---------------------------------------------------------------------------

  tz.initializeTimeZones();

  final timezoneInfo = await FlutterTimezone.getLocalTimezone();

  tz.setLocalLocation(tz.getLocation(timezoneInfo.identifier));

  // ---------------------------------------------------------------------------
  // SCHEDULER
  // ---------------------------------------------------------------------------

  await SchedulerPersistence.instance.load();

  final schedulerProvider = SchedulerProvider();

  // ---------------------------------------------------------------------------
  // NOTIFICATIONS
  // ---------------------------------------------------------------------------

  await NotificationService.instance.initialize(
    onAction: (actionId, payload) async {
      if (actionId == 'task_completed_yes') {
        schedulerProvider.taskCompletedYes();
        return;
      }

      if (actionId == 'task_completed_no') {
        schedulerProvider.taskCompletedNo();
        return;
      }

      if (actionId == 'accountability_yes') {
        schedulerProvider.answeredYes();
        return;
      }

      if (actionId == 'accountability_no') {
        schedulerProvider.answeredNo();
        return;
      }

      if (payload != null && payload.startsWith('completion_grace_expired:')) {
        schedulerProvider.completionGraceExpired();
        return;
      }
    },
  );

  // ---------------------------------------------------------------------------
  // APP
  // ---------------------------------------------------------------------------

  runApp(
    ChangeNotifierProvider<SchedulerProvider>.value(
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
      title: 'Momentum',
      theme: AppTheme.dark,
      home: const Dashboard(),
    );
  }
}
