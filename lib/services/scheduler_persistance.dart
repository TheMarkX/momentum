import 'package:shared_preferences/shared_preferences.dart';

class SchedulerPersistence {
  SchedulerPersistence._();

  static final SchedulerPersistence instance = SchedulerPersistence._();

  static const String _taskIndexKey = 'scheduler_task_index';
  static const String _taskEndsAtKey = 'scheduler_task_ends_at';
  static const String _noCountKey = 'scheduler_no_count';
  static const String _completionGraceKey = 'scheduler_task_completion_grace';

  int? currentTaskIndex;
  DateTime? taskEndsAt;
  int noCount = 0;
  bool taskInCompletionGrace = false;

  // ---------------------------------------------------------------------------
  // LOAD
  // ---------------------------------------------------------------------------

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    currentTaskIndex = prefs.getInt(_taskIndexKey);

    final taskEndsAtMilliseconds = prefs.getInt(_taskEndsAtKey);

    taskEndsAt = taskEndsAtMilliseconds == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(taskEndsAtMilliseconds);

    noCount = prefs.getInt(_noCountKey) ?? 0;

    taskInCompletionGrace = prefs.getBool(_completionGraceKey) ?? false;
  }

  // ---------------------------------------------------------------------------
  // TASK
  // ---------------------------------------------------------------------------

  Future<void> saveTask({
    required int taskIndex,
    required DateTime taskEndsAt,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    currentTaskIndex = taskIndex;
    this.taskEndsAt = taskEndsAt;
    taskInCompletionGrace = false;
    noCount = 0;

    await prefs.setInt(_taskIndexKey, taskIndex);

    await prefs.setInt(_taskEndsAtKey, taskEndsAt.millisecondsSinceEpoch);

    await prefs.setInt(_noCountKey, 0);

    await prefs.setBool(_completionGraceKey, false);
  }

  // ---------------------------------------------------------------------------
  // ACCOUNTABILITY
  // ---------------------------------------------------------------------------

  Future<void> saveNoCount(int value) async {
    final prefs = await SharedPreferences.getInstance();

    noCount = value;

    await prefs.setInt(_noCountKey, value);
  }

  // ---------------------------------------------------------------------------
  // COMPLETION GRACE
  // ---------------------------------------------------------------------------

  Future<void> markCompletionGrace() async {
    final prefs = await SharedPreferences.getInstance();

    taskInCompletionGrace = true;

    await prefs.setBool(_completionGraceKey, true);
  }

  // ---------------------------------------------------------------------------
  // CLEAR
  // ---------------------------------------------------------------------------

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();

    currentTaskIndex = null;
    taskEndsAt = null;
    noCount = 0;
    taskInCompletionGrace = false;

    await prefs.remove(_taskIndexKey);
    await prefs.remove(_taskEndsAtKey);
    await prefs.remove(_noCountKey);
    await prefs.remove(_completionGraceKey);
  }
}
