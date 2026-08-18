import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:momentum/models/rescheduled_task.dart';
import 'package:momentum/services/notification_service.dart';
import 'package:momentum/services/scheduler_persistance.dart';
import 'package:timezone/timezone.dart' as tz;

import '../models/day_plan.dart';
import '../models/scheduler_state.dart';
import '../models/task.dart';

class SchedulerService {
  final DayPlan plan;
  final bool startImmediately;

  SchedulerService(this.plan, {this.startImmediately = true});

  // IN-APP TIMERS
  Timer? _timer;
  Timer? _rescheduleTimer;

  SchedulerState state = const SchedulerState(
    stage: ScheduleStage.waiting,
    currentTaskIndex: 0,
    remaining: Duration.zero,
  );

  VoidCallback? onStateChanged;

  bool _paused = false;

  // ACCOUNTABILITY STATE
  final Random _random = Random();

  bool _answeredYes = false;
  int _noCount = 0;

  DateTime? _currentTaskEndsAt;

  final List<RescheduledTask> _retryQueue = [];

  static const Duration retryBreak = Duration(minutes: 5);

  // NOTIFICATION IDS

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

  int _completionGraceExpiryNotificationId(int taskIndex) {
    return 5000 + taskIndex;
  }

  // GETTERS
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

  // PUBLIC API
  Future<void> _loadRetryQueue() async {
    _retryQueue
      ..clear()
      ..addAll(await SchedulerPersistence.instance.loadRetryQueue());
  }

  Future<void> restore() async {
    await stop();

    await _loadRetryQueue();

    if (_retryQueue.isNotEmpty) {
      await _restoreRetrySchedule();
      return;
    }

    await start();
  }

  Future<void> start() async {
    await stop();

    await _loadRetryQueue();

    // Persisted retries always take priority over starting
    // the normal task list.
    if (_retryQueue.isNotEmpty) {
      await _restoreRetrySchedule();
      return;
    }

    if (plan.tasks.isEmpty) {
      return;
    }

    if (startImmediately) {
      await _startTask(0);
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
      await _startTask(0);
      return;
    }

    _setState(stage: ScheduleStage.waiting, taskIndex: 0, remaining: wait);

    _timer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final remaining = state.remaining - const Duration(seconds: 1);

      if (remaining <= Duration.zero) {
        _timer?.cancel();
        _timer = null;

        await _startTask(0);
        return;
      }

      _setState(
        stage: ScheduleStage.waiting,
        taskIndex: 0,
        remaining: remaining,
      );
    });
  }

  Future<void> completionGraceExpired() async {
    if (state.stage != ScheduleStage.taskCompletionGrace) {
      return;
    }

    final index = state.currentTaskIndex;

    await NotificationService.instance.notifications.cancel(
      _completionNotificationId(index),
    );

    await NotificationService.instance.notifications.cancel(
      _completionGraceExpiryNotificationId(index),
    );

    await _taskFailed();
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;

    _rescheduleTimer?.cancel();
    _rescheduleTimer = null;

    _paused = false;

    await _cancelCurrentTaskNotifications();
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
        break;

      case ScheduleStage.breakTime:
        _resumeBreak();
        break;

      case ScheduleStage.finished:
        break;
    }

    _notify();
  }

  // ACCOUNTABILITY NOTIFICATIONS

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

    final remainingUntilEnd = taskEnd.difference(now);

    if (remainingUntilEnd <= Duration.zero) {
      return;
    }
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
              showsUserInterface: false,
            ),
            AndroidNotificationAction(
              'accountability_no',
              'No',
              showsUserInterface: false,
            ),
          ],
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: 'accountability:$taskIndex:$_noCount',
    );
  }

  Future<void> _scheduleRandomNotification() async {
    _answeredYes = false;
    _noCount = 0;

    await _cancelAccountabilityNotification();
    await _scheduleAccountabilityNotification();
  }

  Duration _getAccountabilityDelay() {
    switch (_noCount) {
      case 0:
        return Duration(seconds: 1 + _random.nextInt(15 * 60));

      case 1:
        return Duration(seconds: 1 + _random.nextInt(10 * 60));

      case 2:
        return Duration(seconds: 1 + _random.nextInt(5 * 60));

      case 3:
        return Duration(seconds: 1 + _random.nextInt(4 * 60));

      case 4:
        return Duration(seconds: 1 + _random.nextInt(3 * 60));

      case 5:
        return Duration(seconds: 1 + _random.nextInt(2 * 60));

      case 6:
        return Duration(seconds: 1 + _random.nextInt(60));

      case 7:
        return const Duration(seconds: 30);

      case 8:
        return const Duration(seconds: 15);

      case 9:
        return const Duration(seconds: 10);

      default:
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

  // ACCOUNTABILITY ACTIONS
  Future<void> answeredYes() async {
    if (_answeredYes) {
      return;
    }

    _answeredYes = true;

    await _cancelAccountabilityNotification();
  }

  Future<void> answeredNo() async {
    if (_answeredYes) {
      return;
    }

    _noCount++;

    // PERSIST ACCOUNTABILITY COUNT
    await SchedulerPersistence.instance.saveNoCount(_noCount);

    await _cancelAccountabilityNotification();

    // CHECK TASK STATE

    if (state.stage != ScheduleStage.task) {
      return;
    }

    if (_currentTaskEndsAt == null) {
      return;
    }
    // SCHEDULE MORE FREQUENT ACCOUNTABILITY
    await _scheduleAccountabilityNotification();
  }

  Future<void> _cancelAccountabilityNotification() async {
    final taskIndex = state.currentTaskIndex;

    await NotificationService.instance.notifications.cancel(
      _accountabilityNotificationId(taskIndex),
    );
  }

  Future<void> _cancelAccountability() async {
    await _cancelAccountabilityNotification();

    _answeredYes = false;
    _noCount = 0;

    await SchedulerPersistence.instance.saveNoCount(0);
  }

  // TASK COMPLETION GRACE PERIOD
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
              showsUserInterface: false,
            ),
            AndroidNotificationAction(
              'task_completed_no',
              'No',
              showsUserInterface: false,
            ),
          ],
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: 'task_completion:$taskIndex',
    );
  }

  Future<void> _scheduleCompletionGraceExpiry() async {
    final taskIndex = state.currentTaskIndex;

    final taskEnd = _currentTaskEndsAt;

    if (taskEnd == null) {
      return;
    }

    final graceExpiry = taskEnd.add(const Duration(minutes: 5));

    await NotificationService.instance.notifications.zonedSchedule(
      _completionGraceExpiryNotificationId(taskIndex),
      'Momentum',
      'completion_grace_expired',
      tz.TZDateTime.from(graceExpiry, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'momentum_internal',
          'Momentum Internal',
          channelDescription: 'Internal Momentum scheduler events',
          importance: Importance.min,
          priority: Priority.min,
          silent: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: 'completion_grace_expired:$taskIndex',
    );
  }

  Future<void> _startCompletionGrace() async {
    await _cancelAccountability();

    final index = state.currentTaskIndex;

    // PERSIST COMPLETION GRACE STATE
    await SchedulerPersistence.instance.markCompletionGrace();

    // UPDATE SCHEDULER STATE
    _setState(
      stage: ScheduleStage.taskCompletionGrace,
      taskIndex: index,
      remaining: const Duration(minutes: 5),
    );

    // START 5-MINUTE GRACE COUNTDOWN
    _timer?.cancel();

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final remaining = state.remaining - const Duration(seconds: 1);

      if (remaining <= Duration.zero) {
        _timer?.cancel();
        _timer = null;

        completionGraceExpired();
        return;
      }

      _setState(
        stage: ScheduleStage.taskCompletionGrace,
        taskIndex: index,
        remaining: remaining,
      );
    });
  }

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

    await NotificationService.instance.notifications.cancel(
      _completionGraceExpiryNotificationId(index),
    );

    await _taskCompleted();
  }

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

    await NotificationService.instance.notifications.cancel(
      _completionGraceExpiryNotificationId(index),
    );

    await _taskFailed();
  }

  // COMPLETED TASK
  Future<void> _taskCompleted() async {
    final index = state.currentTaskIndex;

    await NotificationService.instance.notifications.cancel(
      _completionNotificationId(index),
    );

    if (index + 1 >= plan.tasks.length) {
      await _handleRetriesAfterFinalTask();
      return;
    }

    _startBreak(index);
  }

  Future<void> _persistRetryQueue() async {
    await SchedulerPersistence.instance.saveRetryQueue(
      List<RescheduledTask>.from(_retryQueue),
    );
  }

  Future<void> _restoreRetrySchedule() async {
    await _loadRetryQueue();

    if (_retryQueue.isEmpty) {
      return;
    }

    final now = DateTime.now();

    final workingStart = DateTime(
      now.year,
      now.month,
      now.day,
      plan.startTime.hour,
      plan.startTime.minute,
    );

    final workingEnd = DateTime(
      now.year,
      now.month,
      now.day,
      plan.endTime.hour,
      plan.endTime.minute,
    );

    if (now.isBefore(workingStart)) {
      _waitUntil(workingStart);
      return;
    }

    if (!now.isBefore(workingEnd)) {
      await _scheduleRetryForNextWorkingDay();
      return;
    }

    await _startNextRetry();
  }

  Future<void> _scheduleTaskRescheduledNotification(
    Task task,
    DateTime scheduledTime,
  ) async {
    final taskIndex = plan.tasks.indexOf(task);

    if (taskIndex < 0) {
      return;
    }

    final time = _formatTime(scheduledTime);

    await NotificationService.instance.notifications.zonedSchedule(
      _rescheduledNotificationId(taskIndex),
      'Task Rescheduled',
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
      payload: 'task_rescheduled:$taskIndex',
    );
  }

  Future<void> _scheduleRetryForNextWorkingDay() async {
    if (_retryQueue.isEmpty) {
      await _finishSchedule();
      return;
    }

    final now = DateTime.now();

    final tomorrow = DateTime(now.year, now.month, now.day + 1);

    final tomorrowStart = DateTime(
      tomorrow.year,
      tomorrow.month,
      tomorrow.day,
      plan.startTime.hour,
      plan.startTime.minute,
    );

    // Reset temporary allocations.
    //
    // Any duration reduction was only valid for today's
    // remaining working time.
    final resetQueue = _retryQueue.map((retry) {
      return RescheduledTask(
        originalTaskIndex: retry.originalTaskIndex,
        originalDuration: retry.originalDuration,
        duration: retry.originalDuration,
        scheduledAt: tomorrowStart,
      );
    }).toList();

    _retryQueue
      ..clear()
      ..addAll(resetQueue);

    await _persistRetryQueue();

    final retry = _retryQueue.first;

    await _scheduleTaskRescheduledNotification(
      plan.tasks[retry.originalTaskIndex],
      tomorrowStart,
    );

    _setState(
      stage: ScheduleStage.waiting,
      taskIndex: retry.originalTaskIndex,
      remaining: tomorrowStart.difference(now),
    );

    _rescheduleTimer?.cancel();

    final wait = tomorrowStart.difference(now);

    if (wait <= Duration.zero) {
      await _restoreRetrySchedule();
      return;
    }

    _rescheduleTimer = Timer(wait, () async {
      _rescheduleTimer = null;

      // Re-evaluate using the current DayPlan.
      await _restoreRetrySchedule();
    });
  }

  Future<void> _taskFailed() async {
    final index = state.currentTaskIndex;

    await NotificationService.instance.notifications.cancel(
      _completionNotificationId(index),
    );

    await NotificationService.instance.notifications.cancel(
      _completionGraceExpiryNotificationId(index),
    );

    final taskEnd = _currentTaskEndsAt;

    if (taskEnd == null) {
      await _moveToNextTaskOrFinish(index);
      return;
    }

    final originalDuration = plan.tasks[index].duration;

    final retry = RescheduledTask(
      originalTaskIndex: index,
      originalDuration: originalDuration,
      duration: originalDuration,
      scheduledAt: taskEnd.add(retryBreak),
    );

    _retryQueue.add(retry);

    await _persistRetryQueue();

    if (index + 1 < plan.tasks.length) {
      await _startTask(index + 1);
      return;
    }

    await _handleRetriesAfterFinalTask();
  }

  bool _tasksAreNearlyEqual(List<RescheduledTask> retries) {
    if (retries.isEmpty) {
      return true;
    }

    final durations = retries.map((retry) => retry.originalDuration).toList();

    final longest = durations.reduce(max);
    final shortest = durations.reduce(min);

    return longest - shortest <= 10;
  }

  List<int> _reduceRetriesEqually(List<int> durations, int availableMinutes) {
    if (durations.isEmpty || availableMinutes <= 0) {
      return List<int>.filled(durations.length, 0);
    }

    final total = durations.fold<int>(0, (sum, duration) => sum + duration);

    if (total <= availableMinutes) {
      return List<int>.from(durations);
    }

    // Reduce every retry proportionally.
    //
    // Example:
    //
    // 30, 30, 30 = 90
    // Available = 60
    //
    // Result:
    // 20, 20, 20
    final ratio = availableMinutes / total;

    final result = durations
        .map((duration) => max(1, (duration * ratio).floor()))
        .toList();

    var resultTotal = result.fold<int>(0, (sum, duration) => sum + duration);

    // We may have rounded down too much.
    var index = 0;

    while (resultTotal < availableMinutes) {
      result[index % result.length]++;
      resultTotal++;
      index++;
    }

    // We may have exceeded the available time because of
    // the minimum 1-minute rule.
    index = 0;

    while (resultTotal > availableMinutes) {
      final target = index % result.length;

      if (result[target] > 1) {
        result[target]--;
        resultTotal--;
      }

      index++;
    }

    return result;
  }

  List<int> _reduceLongestFirst(List<int> durations, int availableMinutes) {
    final result = List<int>.from(durations);

    var total = result.fold<int>(0, (sum, duration) => sum + duration);

    if (total <= availableMinutes) {
      return result;
    }

    var excess = total - availableMinutes;

    while (excess > 0) {
      // Find the currently longest retry.
      var longestIndex = 0;

      for (var i = 1; i < result.length; i++) {
        if (result[i] > result[longestIndex]) {
          longestIndex = i;
        }
      }

      // We cannot reduce this any further.
      if (result[longestIndex] <= 1) {
        break;
      }

      result[longestIndex]--;
      excess--;
    }

    return result;
  }

  List<int> _allocateRetryDurations(
    List<RescheduledTask> retries,
    int availableMinutes,
  ) {
    if (retries.isEmpty || availableMinutes <= 0) {
      return List<int>.filled(retries.length, 0);
    }

    final requested = retries.map((retry) => retry.originalDuration).toList();

    final totalRequested = requested.fold<int>(
      0,
      (sum, duration) => sum + duration,
    );

    // Everything fits at the original durations.
    if (totalRequested <= availableMinutes) {
      return requested;
    }

    // Nearly equal tasks → distribute the available time
    // proportionally/equally.
    if (_tasksAreNearlyEqual(retries)) {
      return _reduceRetriesEqually(requested, availableMinutes);
    }

    // Unequal tasks → reduce the longest tasks first.
    return _reduceLongestFirst(requested, availableMinutes);
  }

  Future<void> _startRetryTask(int originalTaskIndex, int duration) async {
    await stop();

    final now = DateTime.now();

    _currentTaskEndsAt = now.add(Duration(minutes: duration));

    await SchedulerPersistence.instance.saveTask(
      taskIndex: originalTaskIndex,
      taskEndsAt: _currentTaskEndsAt!,
    );

    _setState(
      stage: ScheduleStage.task,
      taskIndex: originalTaskIndex,
      remaining: Duration(minutes: duration),
    );
    await _scheduleRandomNotification();

    await _scheduleTaskCompletionNotification();

    await _scheduleCompletionGraceExpiry();

    _resumeTask();
  }

  void _waitUntil(DateTime start) {
    if (_retryQueue.isEmpty) {
      return;
    }

    final wait = start.difference(DateTime.now());

    _setState(
      stage: ScheduleStage.waiting,
      taskIndex: _retryQueue.first.originalTaskIndex,
      remaining: wait > Duration.zero ? wait : Duration.zero,
    );

    _timer?.cancel();

    if (wait <= Duration.zero) {
      _restoreRetrySchedule();
      return;
    }

    _timer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final remaining = state.remaining - const Duration(seconds: 1);

      if (remaining <= Duration.zero) {
        _timer?.cancel();
        _timer = null;

        // Re-evaluate the schedule using the CURRENT DayPlan.
        await _restoreRetrySchedule();
        return;
      }

      _setState(
        stage: ScheduleStage.waiting,
        taskIndex: _retryQueue.first.originalTaskIndex,
        remaining: remaining,
      );
    });
  }

  Future<void> _startNextRetry() async {
    if (_retryQueue.isEmpty) {
      await _finishSchedule();
      return;
    }

    final now = DateTime.now();

    final workingStart = DateTime(
      now.year,
      now.month,
      now.day,
      plan.startTime.hour,
      plan.startTime.minute,
    );

    final workingEnd = DateTime(
      now.year,
      now.month,
      now.day,
      plan.endTime.hour,
      plan.endTime.minute,
    );

    // ------------------------------------------------------------
    // BEFORE WORKING HOURS
    // ------------------------------------------------------------

    if (now.isBefore(workingStart)) {
      _waitUntil(workingStart);
      return;
    }

    // ------------------------------------------------------------
    // AFTER WORKING HOURS
    // ------------------------------------------------------------

    if (!now.isBefore(workingEnd)) {
      await _scheduleRetryForNextWorkingDay();
      return;
    }

    final availableMinutes = workingEnd.difference(now).inMinutes;

    if (availableMinutes <= 0) {
      await _scheduleRetryForNextWorkingDay();
      return;
    }

    // ------------------------------------------------------------
    // ALLOCATE TODAY'S REMAINING WORKING TIME
    // ACROSS ALL PENDING RETRIES.
    // ------------------------------------------------------------

    final allocatedDurations = _allocateRetryDurations(
      _retryQueue,
      availableMinutes,
    );

    if (allocatedDurations.isEmpty) {
      await _scheduleRetryForNextWorkingDay();
      return;
    }

    final duration = allocatedDurations.first;

    // ------------------------------------------------------------
    // If the first retry cannot receive even one minute,
    // it cannot fit today.
    // ------------------------------------------------------------

    if (duration <= 0) {
      await _scheduleRetryForNextWorkingDay();
      return;
    }

    // ------------------------------------------------------------
    // IMPORTANT:
    //
    // Persist the newly allocated durations for the remaining
    // queue BEFORE removing the first retry.
    //
    // This means multiple retries survive restarts with their
    // current allocation.
    // ------------------------------------------------------------

    final allocatedQueue = <RescheduledTask>[];

    for (var i = 0; i < _retryQueue.length; i++) {
      allocatedQueue.add(
        RescheduledTask(
          originalTaskIndex: _retryQueue[i].originalTaskIndex,
          originalDuration: _retryQueue[i].originalDuration,
          duration: allocatedDurations[i],
          scheduledAt: _retryQueue[i].scheduledAt,
        ),
      );
    }

    _retryQueue
      ..clear()
      ..addAll(allocatedQueue);

    await _persistRetryQueue();

    // ------------------------------------------------------------
    // NOW REMOVE THE RETRY WE ARE ABOUT TO EXECUTE.
    // ------------------------------------------------------------

    final retry = _retryQueue.removeAt(0);

    await _persistRetryQueue();

    // ------------------------------------------------------------
    // START IT.
    // ------------------------------------------------------------

    await _startRetryTask(retry.originalTaskIndex, retry.duration);
  }

  Future<void> _handleRetriesAfterFinalTask() async {
    if (_retryQueue.isEmpty) {
      await _finishSchedule();
      return;
    }

    _setState(
      stage: ScheduleStage.breakTime,
      taskIndex: plan.tasks.length - 1,
      remaining: retryBreak,
    );

    _timer?.cancel();

    _timer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final remaining = state.remaining - const Duration(seconds: 1);

      if (remaining <= Duration.zero) {
        _timer?.cancel();
        _timer = null;

        await _startNextRetry();
        return;
      }

      _setState(
        stage: ScheduleStage.breakTime,
        taskIndex: state.currentTaskIndex,
        remaining: remaining,
      );
    });
  }

  Future<void> _moveToNextTaskOrFinish(int index) async {
    if (index + 1 >= plan.tasks.length) {
      await _handleRetriesAfterFinalTask();
      return;
    }

    await _startTask(index + 1);
  }

  // TASK START
  Future<void> _startTask(int index) async {
    await stop();

    final now = DateTime.now();

    final duration = Duration(minutes: plan.tasks[index].duration);

    _currentTaskEndsAt = now.add(duration);

    // PERSIST TASK STATE

    await SchedulerPersistence.instance.saveTask(
      taskIndex: index,
      taskEndsAt: _currentTaskEndsAt!,
    );

    _setState(stage: ScheduleStage.task, taskIndex: index, remaining: duration);

    // ACCOUNTABILITY NOTIFICATION
    await _scheduleRandomNotification();

    // TASK COMPLETION NOTIFICATION
    await _scheduleTaskCompletionNotification();

    // COMPLETION GRACE EXPIRY
    await _scheduleCompletionGraceExpiry();

    // IN-APP COUNTDOWN
    _resumeTask();
  }

  // TASK TIMER
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

  // WAITING
  void _resumeWaiting() {
    _timer?.cancel();

    _timer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final remaining = state.remaining - const Duration(seconds: 1);

      if (remaining <= Duration.zero) {
        _timer?.cancel();
        _timer = null;

        if (_retryQueue.isNotEmpty) {
          await _restoreRetrySchedule();
        } else {
          await _startTask(state.currentTaskIndex);
        }

        return;
      }

      _setState(
        stage: ScheduleStage.waiting,
        taskIndex: state.currentTaskIndex,
        remaining: remaining,
      );
    });
  }

  // BREAK
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
          _handleRetriesAfterFinalTask();
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

  // CANCEL SCHEDULED NOTIFICATIONS
  Future<void> _cancelCurrentTaskNotifications() async {
    final index = state.currentTaskIndex;

    await NotificationService.instance.notifications.cancel(
      _accountabilityNotificationId(index),
    );

    await NotificationService.instance.notifications.cancel(
      _completionNotificationId(index),
    );

    await NotificationService.instance.notifications.cancel(
      _completionGraceExpiryNotificationId(index),
    );

    await NotificationService.instance.notifications.cancel(
      _rescheduledNotificationId(index),
    );

    await NotificationService.instance.notifications.cancel(
      _breakNotificationId(index),
    );
  }

  // FINISH
  Future<void> _finishSchedule() async {
    await stop();
    _retryQueue.clear();

    await SchedulerPersistence.instance.clearRetryQueue();
    _setState(
      stage: ScheduleStage.finished,
      taskIndex: plan.tasks.length - 1,
      remaining: Duration.zero,
    );
  }

  // HELPERS
  String _formatTime(DateTime time) {
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;

    final minute = time.minute.toString().padLeft(2, '0');

    final period = time.hour >= 12 ? 'PM' : 'AM';

    return '$hour:$minute $period';
  }

  // STATE
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
