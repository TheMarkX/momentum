import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:momentum/services/notification_service.dart';
import 'package:timezone/timezone.dart' as tz;

import '../models/day_plan.dart';
import '../models/scheduler_state.dart';
import '../models/task.dart';

class SchedulerService {
  final DayPlan plan;
  final bool startImmediately;

  SchedulerService(this.plan, {this.startImmediately = true});

  // ---------------------------------------------------------------------------
  // IN-APP TIMERS
  // ---------------------------------------------------------------------------

  Timer? _timer;
  Timer? _rescheduleTimer;

  SchedulerState state = const SchedulerState(
    stage: ScheduleStage.waiting,
    currentTaskIndex: 0,
    remaining: Duration.zero,
  );

  VoidCallback? onStateChanged;

  bool _paused = false;

  // ---------------------------------------------------------------------------
  // ACCOUNTABILITY STATE
  // ---------------------------------------------------------------------------

  final Random _random = Random();

  bool _answeredYes = false;
  int _noCount = 0;

  DateTime? _currentTaskEndsAt;

  // ---------------------------------------------------------------------------
  // NOTIFICATION IDS
  // ---------------------------------------------------------------------------

  //
  // We use different IDs for different notification types.
  //
  // Accountability:
  //   1000 + task index
  //
  // Completion:
  //   2000 + task index
  //
  // Rescheduled:
  //   3000 + task index
  //
  // Break:
  //   4000 + task index
  //

  int _accountabilityNotificationId(int taskIndex) {
    return 1000 + taskIndex;
  }

  int _completionNotificationId(int taskIndex) {
    return 2000 + taskIndex;
  }

  int _rescheduledNotificationId(int taskIndex) {
    return 3000 + taskIndex;
  }

  int _breakNotificationId(int taskIndex) {
    return 4000 + taskIndex;
  }

  // ---------------------------------------------------------------------------
  // GETTERS
  // ---------------------------------------------------------------------------

  DayPlan get dayPlan => plan;

  Task get currentTask => plan.tasks[state.currentTaskIndex];

  Task? get nextTask {
    if (state.currentTaskIndex + 1 >= plan.tasks.length) {
      return null;
    }

    return plan.tasks[state.currentTaskIndex + 1];
  }

  bool get isRunning => state.stage == ScheduleStage.task;

  bool get isOnBreak => state.stage == ScheduleStage.breakTime;

  bool get isInCompletionGrace =>
      state.stage == ScheduleStage.taskCompletionGrace;

  bool get isFinished => state.stage == ScheduleStage.finished;

  bool get isPaused => _paused;

  // ---------------------------------------------------------------------------
  // PUBLIC API
  // ---------------------------------------------------------------------------

  void start() {
    stop();

    if (plan.tasks.isEmpty) {
      return;
    }

    if (startImmediately) {
      _startTask(0);
      return;
    }

    final now = DateTime.now();

    final start = DateTime(
      now.year,
      now.month,
      now.day,
      plan.startTime.hour,
      plan.startTime.minute,
    );

    final wait = start.difference(now);

    if (wait <= Duration.zero) {
      _startTask(0);
      return;
    }

    _setState(stage: ScheduleStage.waiting, taskIndex: 0, remaining: wait);

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final remaining = state.remaining - const Duration(seconds: 1);

      if (remaining <= Duration.zero) {
        _timer?.cancel();
        _timer = null;

        _startTask(0);
        return;
      }

      _setState(
        stage: ScheduleStage.waiting,
        taskIndex: 0,
        remaining: remaining,
      );
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;

    _rescheduleTimer?.cancel();
    _rescheduleTimer = null;

    _paused = false;

    _cancelCurrentTaskNotifications();
  }

  void pause() {
    if (_paused) {
      return;
    }

    _paused = true;

    _timer?.cancel();
    _timer = null;

    _cancelCurrentTaskNotifications();

    _notify();
  }

  void resume() {
    if (!_paused) {
      return;
    }

    _paused = false;

    switch (state.stage) {
      case ScheduleStage.waiting:
        _resumeWaiting();
        break;

      case ScheduleStage.task:
        _resumeTask();
        break;

      case ScheduleStage.taskCompletionGrace:
        _resumeCompletionGrace();
        break;

      case ScheduleStage.breakTime:
        _resumeBreak();
        break;

      case ScheduleStage.finished:
        break;
    }

    _notify();
  }

  // ===========================================================================
  // ACCOUNTABILITY NOTIFICATIONS
  // ===========================================================================

  //
  // IMPORTANT:
  //
  // This does NOT use Timer.
  //
  // Android receives the notification schedule directly.
  //

  Future<void> _scheduleAccountabilityNotification() async {
    if (_answeredYes) {
      return;
    }

    if (state.stage != ScheduleStage.task) {
      return;
    }

    final taskIndex = state.currentTaskIndex;

    final taskEnd = _currentTaskEndsAt;

    if (taskEnd == null) {
      return;
    }

    final delay = _getAccountabilityDelay();

    final now = DateTime.now();

    //
    // Don't schedule past the task's end.
    //
    final remainingUntilEnd = taskEnd.difference(now);

    if (remainingUntilEnd <= Duration.zero) {
      return;
    }

    //
    // If the random delay would take us to/past the task end,
    // don't schedule the notification.
    //
    if (delay >= remainingUntilEnd) {
      return;
    }

    final scheduledTime = now.add(delay);

    final notificationId = _accountabilityNotificationId(taskIndex);

    final message = _getAccountabilityMessage();

    await NotificationService.instance.notifications.zonedSchedule(
      notificationId,
      'Momentum',
      message,
      tz.TZDateTime.from(scheduledTime, tz.local),
      NotificationDetails(
        android: AndroidNotificationDetails(
          'momentum_accountability',
          'Accountability',
          channelDescription: 'Momentum accountability notifications',
          importance: Importance.max,
          priority: Priority.high,
          actions: const [
            AndroidNotificationAction(
              'accountability_yes',
              'Yes',
              showsUserInterface: true,
            ),
            AndroidNotificationAction(
              'accountability_no',
              'No',
              showsUserInterface: true,
            ),
          ],
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: 'accountability:$taskIndex:$_noCount',
    );
  }

  void _scheduleRandomNotification() {
    _answeredYes = false;
    _noCount = 0;

    _cancelAccountabilityNotification();

    _scheduleAccountabilityNotification();
  }

  Duration _getAccountabilityDelay() {
    switch (_noCount) {
      case 0:
        // First:
        // 0–15 minutes
        return Duration(seconds: _random.nextInt(15 * 60 + 1));

      case 1:
        // Second:
        // 0–10 minutes
        return Duration(seconds: _random.nextInt(10 * 60 + 1));

      case 2:
        // Third:
        // 0–5 minutes
        return Duration(seconds: _random.nextInt(5 * 60 + 1));

      case 3:
        // Fourth:
        // 0–4 minutes
        return Duration(seconds: _random.nextInt(4 * 60 + 1));

      case 4:
        // Fifth:
        // 0–3 minutes
        return Duration(seconds: _random.nextInt(3 * 60 + 1));

      case 5:
        // Sixth:
        // 0–2 minutes
        return Duration(seconds: _random.nextInt(2 * 60 + 1));

      case 6:
        // Seventh:
        // 0–1 minute
        return Duration(seconds: _random.nextInt(60 + 1));

      case 7:
        return const Duration(seconds: 30);

      case 8:
        return const Duration(seconds: 15);

      case 9:
        return const Duration(seconds: 10);

      default:
        // Never below 5 seconds.
        return const Duration(seconds: 5);
    }
  }

  String _getAccountabilityMessage() {
    switch (_noCount) {
      case 0:
        return 'Are you working?';

      case 1:
        return 'Have you started now?';

      case 2:
        return 'Ready to begin?';

      case 3:
        return 'You planned this. Start now.';

      default:
        return "Don't give up.\n"
            'Your future self is counting on you.';
    }
  }

  // ---------------------------------------------------------------------------
  // ACCOUNTABILITY ACTIONS
  // ---------------------------------------------------------------------------

  //
  // Called by NotificationService when the user presses YES.
  //

  Future<void> answeredYes() async {
    if (_answeredYes) {
      return;
    }

    _answeredYes = true;

    await _cancelAccountabilityNotification();
  }

  //
  // Called by NotificationService when the user presses NO.
  //
  // This schedules another Android notification.
  //

  Future<void> answeredNo() async {
    if (_answeredYes) {
      return;
    }

    _noCount++;

    await _cancelAccountabilityNotification();

    //
    // Check whether the task has already ended.
    //
    if (state.stage != ScheduleStage.task) {
      return;
    }

    if (_currentTaskEndsAt == null) {
      return;
    }

    await _scheduleAccountabilityNotification();
  }

  Future<void> _cancelAccountabilityNotification() async {
    final taskIndex = state.currentTaskIndex;

    await NotificationService.instance.notifications.cancel(
      _accountabilityNotificationId(taskIndex),
    );
  }

  void _cancelAccountability() {
    _cancelAccountabilityNotification();

    _answeredYes = false;
    _noCount = 0;
  }

  // ===========================================================================
  // TASK COMPLETION GRACE PERIOD
  // ===========================================================================

  //
  // This notification is ALSO scheduled through Android.
  //
  // It fires exactly when the task timer ends.
  //

  Future<void> _scheduleTaskCompletionNotification() async {
    final taskIndex = state.currentTaskIndex;

    final taskEnd = _currentTaskEndsAt;

    if (taskEnd == null) {
      return;
    }

    await NotificationService.instance.notifications.zonedSchedule(
      _completionNotificationId(taskIndex),
      'Task Time Finished',
      'Have you done your task?',
      tz.TZDateTime.from(taskEnd, tz.local),
      NotificationDetails(
        android: AndroidNotificationDetails(
          'momentum_task_completion',
          'Task Completion',
          channelDescription: 'Task completion confirmation notifications',
          importance: Importance.max,
          priority: Priority.high,
          actions: const [
            AndroidNotificationAction(
              'task_completed_yes',
              'Yes',
              showsUserInterface: true,
            ),
            AndroidNotificationAction(
              'task_completed_no',
              'No',
              showsUserInterface: true,
            ),
          ],
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: 'task_completion:$taskIndex',
    );
  }

  //
  // When the app itself reaches the task end while running.
  //
  // We move into the 5-minute grace state.
  //

  void _startCompletionGrace() {
    _cancelAccountability();

    final index = state.currentTaskIndex;

    _setState(
      stage: ScheduleStage.taskCompletionGrace,
      taskIndex: index,
      remaining: const Duration(minutes: 5),
    );

    //
    // The notification should already have been scheduled for task end.
    //
    // Now the app gives the user five minutes to answer it.
    //

    _timer = Timer(const Duration(minutes: 5), () {
      if (state.stage != ScheduleStage.taskCompletionGrace) {
        return;
      }

      _taskFailed();
    });
  }

  void _resumeCompletionGrace() {
    _timer?.cancel();

    _timer = Timer(state.remaining, () {
      if (state.stage != ScheduleStage.taskCompletionGrace) {
        return;
      }

      _taskFailed();
    });
  }

  //
  // YES on:
  //
  // "Task Time Finished
  //  Have you done your task?"
  //

  Future<void> taskCompletedYes() async {
    if (state.stage != ScheduleStage.taskCompletionGrace) {
      return;
    }

    _timer?.cancel();
    _timer = null;

    final index = state.currentTaskIndex;

    await NotificationService.instance.notifications.cancel(
      _completionNotificationId(index),
    );

    _taskCompleted();
  }

  //
  // NO on the completion notification.
  //
  // This is the ONLY NO that fails the task.
  //

  Future<void> taskCompletedNo() async {
    if (state.stage != ScheduleStage.taskCompletionGrace) {
      return;
    }

    _timer?.cancel();
    _timer = null;

    final index = state.currentTaskIndex;

    await NotificationService.instance.notifications.cancel(
      _completionNotificationId(index),
    );

    _taskFailed();
  }

  // ===========================================================================
  // COMPLETED TASK
  // ===========================================================================

  void _taskCompleted() {
    final index = state.currentTaskIndex;

    NotificationService.instance.notifications.cancel(
      _completionNotificationId(index),
    );

    //
    // No next task.
    //
    if (index + 1 >= plan.tasks.length) {
      _finishSchedule();
      return;
    }

    //
    // Start the configured break.
    //
    _startBreak(index);
  }

  // ===========================================================================
  // FAILED / RESCHEDULED TASK
  // ===========================================================================

  Future<void> _taskFailed() async {
    final index = state.currentTaskIndex;

    await NotificationService.instance.notifications.cancel(
      _completionNotificationId(index),
    );

    final taskEnd = _currentTaskEndsAt;

    if (taskEnd == null) {
      _moveToNextTaskOrFinish(index);
      return;
    }

    //
    // Reschedule 10 minutes after the ORIGINAL task end.
    //
    final rescheduledStart = taskEnd.add(const Duration(minutes: 10));

    final workingEnd = DateTime(
      taskEnd.year,
      taskEnd.month,
      taskEnd.day,
      plan.endTime.hour,
      plan.endTime.minute,
    );

    //
    // If the new start would be outside working hours,
    // don't reschedule it.
    //
    if (rescheduledStart.isAfter(workingEnd)) {
      _moveToNextTaskOrFinish(index);
      return;
    }

    await _scheduleTaskRescheduledNotification(
      plan.tasks[index],
      rescheduledStart,
    );

    final wait = rescheduledStart.difference(DateTime.now());

    _setState(stage: ScheduleStage.waiting, taskIndex: index, remaining: wait);

    _rescheduleTimer?.cancel();

    if (wait <= Duration.zero) {
      _startTask(index);
      return;
    }

    _rescheduleTimer = Timer(wait, () {
      _rescheduleTimer = null;

      if (state.currentTaskIndex != index) {
        return;
      }

      _startTask(index);
    });
  }

  Future<void> _scheduleTaskRescheduledNotification(
    Task task,
    DateTime scheduledTime,
  ) async {
    final time = _formatTime(scheduledTime);

    await NotificationService.instance.notifications.zonedSchedule(
      _rescheduledNotificationId(state.currentTaskIndex),
      'Task Rescheduled',
      'Task time finished. '
          '${task.title} has been rescheduled for $time.',
      tz.TZDateTime.from(scheduledTime, tz.local),
      NotificationDetails(
        android: AndroidNotificationDetails(
          'momentum_rescheduled',
          'Rescheduled Tasks',
          channelDescription: 'Notifications for rescheduled tasks',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: 'task_rescheduled:${state.currentTaskIndex}',
    );
  }

  void _moveToNextTaskOrFinish(int index) {
    if (index + 1 >= plan.tasks.length) {
      _finishSchedule();
    } else {
      _startTask(index + 1);
    }
  }

  // ===========================================================================
  // TASK START
  // ===========================================================================

  void _startTask(int index) {
    stop();

    final now = DateTime.now();

    final duration = Duration(minutes: plan.tasks[index].duration);

    _currentTaskEndsAt = now.add(duration);

    _setState(stage: ScheduleStage.task, taskIndex: index, remaining: duration);

    //
    // Schedule the accountability notification through Android.
    //
    _scheduleRandomNotification();

    //
    // Schedule the task-finished notification through Android.
    //
    _scheduleTaskCompletionNotification();

    //
    // Keep the in-app countdown running.
    //
    _resumeTask();
  }

  // ===========================================================================
  // TASK TIMER
  // ===========================================================================

  void _resumeTask() {
    _timer?.cancel();

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final remaining = state.remaining - const Duration(seconds: 1);

      if (remaining <= Duration.zero) {
        _timer?.cancel();
        _timer = null;

        _startCompletionGrace();
        return;
      }

      _setState(
        stage: ScheduleStage.task,
        taskIndex: state.currentTaskIndex,
        remaining: remaining,
      );
    });
  }

  // ===========================================================================
  // WAITING
  // ===========================================================================

  void _resumeWaiting() {
    _timer?.cancel();

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final remaining = state.remaining - const Duration(seconds: 1);

      if (remaining <= Duration.zero) {
        _timer?.cancel();
        _timer = null;

        _startTask(state.currentTaskIndex);
        return;
      }

      _setState(
        stage: ScheduleStage.waiting,
        taskIndex: state.currentTaskIndex,
        remaining: remaining,
      );
    });
  }

  // ===========================================================================
  // BREAK
  // ===========================================================================

  void _startBreak(int index) {
    stop();

    _setState(
      stage: ScheduleStage.breakTime,
      taskIndex: index,
      remaining: Duration(minutes: plan.breaks[index]),
    );

    _scheduleBreakNotification(index);

    _resumeBreak();
  }

  Future<void> _scheduleBreakNotification(int index) async {
    final breakMinutes = plan.breaks[index];

    final nextIndex = index + 1;

    String body;

    if (nextIndex >= plan.tasks.length) {
      body = 'Task completed, enjoy your $breakMinutes minute break.';
    } else {
      final upcomingStart = DateTime.now().add(Duration(minutes: breakMinutes));

      final time = _formatTime(upcomingStart);

      final taskName = plan.tasks[nextIndex].title;

      body =
          'Task completed, enjoy your $breakMinutes minute break.\n'
          'Upcoming task at $time: $taskName';
    }

    await NotificationService.instance.notifications.zonedSchedule(
      _breakNotificationId(index),
      'Task Completed',
      body,
      tz.TZDateTime.from(DateTime.now(), tz.local),
      NotificationDetails(
        android: AndroidNotificationDetails(
          'momentum_break',
          'Breaks',
          channelDescription: 'Task completion and break notifications',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: 'break:$index',
    );
  }

  void _resumeBreak() {
    _timer?.cancel();

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final remaining = state.remaining - const Duration(seconds: 1);

      if (remaining <= Duration.zero) {
        _timer?.cancel();
        _timer = null;

        final nextIndex = state.currentTaskIndex + 1;

        if (nextIndex >= plan.tasks.length) {
          _finishSchedule();
          return;
        }

        _startTask(nextIndex);
        return;
      }

      _setState(
        stage: ScheduleStage.breakTime,
        taskIndex: state.currentTaskIndex,
        remaining: remaining,
      );
    });
  }

  // ===========================================================================
  // CANCEL SCHEDULED NOTIFICATIONS
  // ===========================================================================

  Future<void> _cancelCurrentTaskNotifications() async {
    final index = state.currentTaskIndex;

    await NotificationService.instance.notifications.cancel(
      _accountabilityNotificationId(index),
    );

    await NotificationService.instance.notifications.cancel(
      _completionNotificationId(index),
    );

    await NotificationService.instance.notifications.cancel(
      _rescheduledNotificationId(index),
    );

    await NotificationService.instance.notifications.cancel(
      _breakNotificationId(index),
    );
  }

  // ===========================================================================
  // FINISH
  // ===========================================================================

  void _finishSchedule() {
    stop();

    _setState(
      stage: ScheduleStage.finished,
      taskIndex: plan.tasks.length - 1,
      remaining: Duration.zero,
    );
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  String _formatTime(DateTime time) {
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;

    final minute = time.minute.toString().padLeft(2, '0');

    final period = time.hour >= 12 ? 'PM' : 'AM';

    return '$hour:$minute $period';
  }

  // ===========================================================================
  // STATE
  // ===========================================================================

  void _setState({
    required ScheduleStage stage,
    required int taskIndex,
    required Duration remaining,
  }) {
    state = SchedulerState(
      stage: stage,
      currentTaskIndex: taskIndex,
      remaining: remaining,
    );

    _notify();
  }

  void _notify() {
    onStateChanged?.call();
  }
}
