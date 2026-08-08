import 'package:flutter/material.dart';

import '../models/day_plan.dart';
import '../services/scheduler_service.dart';

class SchedulerProvider extends ChangeNotifier {
  SchedulerService? _scheduler;

  SchedulerService? get scheduler => _scheduler;

  bool get hasScheduler => _scheduler != null;

  // ---------------------------------------------------------------------------
  // PLAN
  // ---------------------------------------------------------------------------

  void loadPlan(DayPlan plan) {
    _scheduler?.stop();

    _scheduler = SchedulerService(plan);

    _scheduler!.onStateChanged = notifyListeners;

    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // SCHEDULER CONTROLS
  // ---------------------------------------------------------------------------

  void start() {
    _scheduler?.start();
    notifyListeners();
  }

  void stop() {
    _scheduler?.stop();
    notifyListeners();
  }

  void pause() {
    _scheduler?.pause();
    notifyListeners();
  }

  void resume() {
    _scheduler?.resume();
    notifyListeners();
  }

  void completionGraceExpired() {
    _scheduler?.completionGraceExpired();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // ACCOUNTABILITY NOTIFICATIONS
  // ---------------------------------------------------------------------------

  Future<void> answeredYes() async {
    await _scheduler?.answeredYes();

    notifyListeners();
  }

  Future<void> answeredNo() async {
    await _scheduler?.answeredNo();

    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // TASK COMPLETION NOTIFICATIONS
  // ---------------------------------------------------------------------------

  Future<void> taskCompletedYes() async {
    await _scheduler?.taskCompletedYes();

    notifyListeners();
  }

  Future<void> taskCompletedNo() async {
    await _scheduler?.taskCompletedNo();

    notifyListeners();
  }
}
