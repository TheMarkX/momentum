import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin notifications =
      FlutterLocalNotificationsPlugin();

  // ===========================================================================
  // INITIALIZATION
  // ===========================================================================

  Future<void> initialize({
    required Future<void> Function(String actionId, String? payload) onAction,
  }) async {
    // -------------------------------------------------------------------------
    // TIMEZONE
    // -------------------------------------------------------------------------

    tz.initializeTimeZones();

    final timezoneInfo = await FlutterTimezone.getLocalTimezone();

    tz.setLocalLocation(tz.getLocation(timezoneInfo.identifier));

    // -------------------------------------------------------------------------
    // ANDROID INITIALIZATION
    // -------------------------------------------------------------------------

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');

    await notifications.initialize(
      const InitializationSettings(android: android),
      onDidReceiveNotificationResponse: (response) async {
        await onAction(response.actionId ?? '', response.payload);
      },
    );
    await notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();

    // -------------------------------------------------------------------------
    // PERMISSIONS
    // -------------------------------------------------------------------------

    final androidPlugin = notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    await androidPlugin?.requestNotificationsPermission();

    await androidPlugin?.requestExactAlarmsPermission();
  }

  // ===========================================================================
  // SCHEDULE NOTIFICATION
  // ===========================================================================

  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledAt,
    required String channelId,
    required String channelName,
    List<AndroidNotificationAction>? actions,
    String? payload,
  }) async {
    final scheduledDate = tz.TZDateTime.from(scheduledAt, tz.local);

    await notifications.zonedSchedule(
      id,
      title,
      body,
      scheduledDate,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          importance: Importance.max,
          priority: Priority.high,
          actions: actions,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: payload,
    );
  }

  // ===========================================================================
  // SHOW IMMEDIATELY
  // ===========================================================================

  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    required String channelId,
    required String channelName,
    List<AndroidNotificationAction>? actions,
    String? payload,
  }) async {
    await notifications.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          importance: Importance.max,
          priority: Priority.high,
          actions: actions,
        ),
      ),
      payload: payload,
    );
  }

  // ===========================================================================
  // CANCEL
  // ===========================================================================

  Future<void> cancel(int id) async {
    await notifications.cancel(id);
  }

  Future<void> cancelAll() async {
    await notifications.cancelAll();
  }
}
