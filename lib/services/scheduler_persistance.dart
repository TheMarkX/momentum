import 'dart:convert';

import 'package:momentum/models/rescheduled_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SchedulerPersistence {
  SchedulerPersistence._();

  static final SchedulerPersistence instance = SchedulerPersistence._();

  // ===========================================================================
  // STORAGE KEYS
  // ===========================================================================

  static const String _taskIndexKey = 'scheduler_task_index';
  static const String _taskEndsAtKey = 'scheduler_task_ends_at';
  static const String _noCountKey = 'scheduler_no_count';
  static const String _completionGraceKey = 'scheduler_task_completion_grace';

  /// The retry queue is authoritative.
  ///
  /// Android notifications are NOT authoritative.
  ///
  /// If working hours change while the app is dead, the queue is loaded again
  /// and the scheduler recalculates the retry time from the current DayPlan.
  static const String _retryQueueKey = 'scheduler_retry_queue';

  // ===========================================================================
  // IN-MEMORY STATE
  // ===========================================================================

  int? currentTaskIndex;

  DateTime? taskEndsAt;

  int noCount = 0;

  bool taskInCompletionGrace = false;

  /// Always represents the persisted retry queue currently loaded.
  List<RescheduledTask> retryQueue = [];

  // ===========================================================================
  // LOAD
  // ===========================================================================

  /// Loads ALL scheduler state.
  ///
  /// This should be called when the scheduler is restored after:
  ///
  /// - app restart
  /// - app launch
  /// - notification callback
  /// - returning from the background
  ///
  /// The retry queue is loaded here because it is part of the scheduler's
  /// authoritative state.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    // -------------------------------------------------------------------------
    // CURRENT TASK
    // -------------------------------------------------------------------------

    currentTaskIndex = prefs.getInt(_taskIndexKey);

    final taskEndsAtMilliseconds = prefs.getInt(_taskEndsAtKey);

    taskEndsAt = taskEndsAtMilliseconds == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(taskEndsAtMilliseconds);

    // -------------------------------------------------------------------------
    // ACCOUNTABILITY
    // -------------------------------------------------------------------------

    noCount = prefs.getInt(_noCountKey) ?? 0;

    // -------------------------------------------------------------------------
    // COMPLETION GRACE
    // -------------------------------------------------------------------------

    taskInCompletionGrace = prefs.getBool(_completionGraceKey) ?? false;

    // -------------------------------------------------------------------------
    // RETRY QUEUE
    // -------------------------------------------------------------------------

    retryQueue = await loadRetryQueue();
  }

  // ===========================================================================
  // TASK
  // ===========================================================================

  /// Persists the currently running task.
  ///
  /// Starting a new task resets:
  ///
  /// - accountability count
  /// - completion grace
  Future<void> saveTask({
    required int taskIndex,
    required DateTime taskEndsAt,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    currentTaskIndex = taskIndex;
    this.taskEndsAt = taskEndsAt;

    noCount = 0;
    taskInCompletionGrace = false;

    await prefs.setInt(_taskIndexKey, taskIndex);

    await prefs.setInt(_taskEndsAtKey, taskEndsAt.millisecondsSinceEpoch);

    await prefs.setInt(_noCountKey, 0);

    await prefs.setBool(_completionGraceKey, false);
  }

  // ===========================================================================
  // ACCOUNTABILITY
  // ===========================================================================

  /// Persists the current accountability "No" count.
  Future<void> saveNoCount(int value) async {
    final prefs = await SharedPreferences.getInstance();

    noCount = value;

    await prefs.setInt(_noCountKey, value);
  }

  // ===========================================================================
  // COMPLETION GRACE
  // ===========================================================================

  /// Marks the current task as being inside its completion grace period.
  Future<void> markCompletionGrace() async {
    final prefs = await SharedPreferences.getInstance();

    taskInCompletionGrace = true;

    await prefs.setBool(_completionGraceKey, true);
  }

  /// Clears completion grace state.
  ///
  /// Useful when the task is completed or failed.
  Future<void> clearCompletionGrace() async {
    final prefs = await SharedPreferences.getInstance();

    taskInCompletionGrace = false;

    await prefs.setBool(_completionGraceKey, false);
  }

  // ===========================================================================
  // RETRY QUEUE
  // ===========================================================================

  /// Saves the COMPLETE retry queue.
  ///
  /// This is the primary persistence operation for retries.
  ///
  /// Example:
  ///
  /// [
  ///   Task #2,
  ///   Task #4,
  ///   Task #6,
  /// ]
  ///
  /// survives an application restart.
  ///
  /// IMPORTANT:
  ///
  /// `scheduledAt` is NOT authoritative.
  ///
  /// It may describe the scheduler's current best-known time, but when a
  /// retry crosses into another working day, SchedulerService MUST calculate
  /// the actual start using the CURRENT DayPlan.
  Future<void> saveRetryQueue(List<RescheduledTask> retries) async {
    final prefs = await SharedPreferences.getInstance();

    retryQueue = List<RescheduledTask>.from(retries);

    final data = retryQueue.map((retry) => retry.toJson()).toList();

    await prefs.setString(_retryQueueKey, jsonEncode(data));
  }

  /// Adds ONE failed task to the retry queue.
  ///
  /// The queue is immediately persisted.
  Future<void> addRetry(RescheduledTask retry) async {
    final queue = List<RescheduledTask>.from(retryQueue);

    queue.add(retry);

    await saveRetryQueue(queue);
  }

  /// Inserts a retry at the beginning of the queue.
  ///
  /// Useful when a retry must take priority over later retries.
  Future<void> addRetryFirst(RescheduledTask retry) async {
    final queue = List<RescheduledTask>.from(retryQueue);

    queue.insert(0, retry);

    await saveRetryQueue(queue);
  }

  /// Removes the first retry in the queue.
  ///
  /// Returns the removed retry, or null if the queue is empty.
  Future<RescheduledTask?> removeFirstRetry() async {
    if (retryQueue.isEmpty) {
      return null;
    }

    final retry = retryQueue.first;

    final queue = List<RescheduledTask>.from(retryQueue)..removeAt(0);

    await saveRetryQueue(queue);

    return retry;
  }

  /// Removes a specific retry by its task index.
  ///
  /// This is useful if a retry is completed.
  Future<void> removeRetryByTaskIndex(int taskIndex) async {
    final queue = List<RescheduledTask>.from(retryQueue)
      ..removeWhere((retry) => retry.originalTaskIndex == taskIndex);

    await saveRetryQueue(queue);
  }

  /// Replaces a retry with an updated version.
  ///
  /// Useful when its duration or scheduled time changes.
  Future<void> updateRetry(RescheduledTask updatedRetry) async {
    final queue = List<RescheduledTask>.from(retryQueue);

    final index = queue.indexWhere(
      (retry) => retry.originalTaskIndex == updatedRetry.originalTaskIndex,
    );

    if (index == -1) {
      queue.add(updatedRetry);
    } else {
      queue[index] = updatedRetry;
    }

    await saveRetryQueue(queue);
  }

  /// Clears the entire retry queue.
  Future<void> clearRetryQueue() async {
    final prefs = await SharedPreferences.getInstance();

    retryQueue.clear();

    await prefs.remove(_retryQueueKey);
  }

  /// Returns a fresh copy of the persisted retry queue.
  ///
  /// This deliberately reads SharedPreferences again instead of trusting only
  /// the in-memory list.
  ///
  /// This is useful during restoration after a notification wakes the app.
  Future<List<RescheduledTask>> reloadRetryQueue() async {
    retryQueue = await loadRetryQueue();

    return List<RescheduledTask>.from(retryQueue);
  }

  // ===========================================================================
  // INTERNAL RETRY QUEUE LOADER
  // ===========================================================================

  Future<List<RescheduledTask>> loadRetryQueue() async {
    final prefs = await SharedPreferences.getInstance();

    final raw = prefs.getString(_retryQueueKey);

    if (raw == null || raw.isEmpty) {
      return [];
    }

    try {
      final decoded = jsonDecode(raw);

      if (decoded is! List) {
        return [];
      }

      final result = <RescheduledTask>[];

      for (final item in decoded) {
        if (item is! Map) {
          continue;
        }

        try {
          final json = Map<String, dynamic>.from(item);

          final originalTaskIndex = json['originalTaskIndex'];
          final duration = json['duration'];

          // ---------------------------------------------------------------
          // REQUIRED FIELD VALIDATION
          // ---------------------------------------------------------------

          if (originalTaskIndex is! int) {
            continue;
          }

          if (duration is! int) {
            continue;
          }

          if (originalTaskIndex < 0) {
            continue;
          }

          if (duration <= 0) {
            continue;
          }

          // ---------------------------------------------------------------
          // BACKWARD COMPATIBILITY
          //
          // Old persisted retry objects don't contain originalDuration.
          //
          // In that case, RescheduledTask.fromJson() falls back to
          // the old duration value.
          // ---------------------------------------------------------------

          final retry = RescheduledTask.fromJson(json);

          result.add(retry);
        } catch (_) {
          // Ignore malformed individual retry entries.
          //
          // One corrupted retry should not destroy the entire queue.
          continue;
        }
      }

      return result;
    } catch (_) {
      // Corrupted persistence should never crash the scheduler.
      return [];
    }
  }

  // ===========================================================================
  // CLEAR ALL
  // ===========================================================================

  /// Clears ALL persisted scheduler state.
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();

    currentTaskIndex = null;
    taskEndsAt = null;
    noCount = 0;
    taskInCompletionGrace = false;
    retryQueue.clear();

    await prefs.remove(_taskIndexKey);
    await prefs.remove(_taskEndsAtKey);
    await prefs.remove(_noCountKey);
    await prefs.remove(_completionGraceKey);
    await prefs.remove(_retryQueueKey);
  }
}
