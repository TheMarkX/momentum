import 'package:flutter/material.dart';

import '../models/day_plan.dart';
import '../services/scheduler_service.dart';

class SchedulerProvider extends ChangeNotifier {
  SchedulerService? _scheduler;

  SchedulerService? get scheduler => _scheduler;

  bool get hasScheduler => _scheduler != null;

  void loadPlan(DayPlan plan) {
    _scheduler?.stop();

    _scheduler = SchedulerService(plan);

    _scheduler!.onStateChanged = notifyListeners;
  }

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

  void answeredYes() {
    _scheduler?.answeredYes();
    notifyListeners();
  }

  void answeredNo() {
    _scheduler?.answeredNo();
    notifyListeners();
  }

  void taskCompletedYes() {
    _scheduler?.taskCompletedYes();
    notifyListeners();
  }

  void taskCompletedNo() {
    _scheduler?.taskCompletedNo();
    notifyListeners();
  }
}
