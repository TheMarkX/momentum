import 'dart:async';

import 'package:flutter/material.dart';

import '../models/day_plan.dart';
import '../models/scheduler_state.dart';
import '../models/task.dart';

class SchedulerService {
  final DayPlan plan;
  final bool startImmediately;

  SchedulerService(this.plan, {this.startImmediately = true});

  Timer? _timer;

  SchedulerState state = const SchedulerState(
    stage: ScheduleStage.waiting,
    currentTaskIndex: 0,
    remaining: Duration.zero,
  );

  VoidCallback? onStateChanged;

  bool _paused = false;

  //Getters

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

  bool get isFinished => state.stage == ScheduleStage.finished;

  bool get isPaused => _paused;

  //Public API

  void start() {
    stop();

    if (plan.tasks.isEmpty) return;

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
    _paused = false;
  }

  void pause() {
    if (_paused) return;

    _paused = true;
    _timer?.cancel();
    _timer = null;

    _notify();
  }

  void resume() {
    if (!_paused) return;

    _paused = false;

    switch (state.stage) {
      case ScheduleStage.waiting:
        _resumeWaiting();
        break;

      case ScheduleStage.task:
        _resumeTask();
        break;

      case ScheduleStage.breakTime:
        _resumeBreak();
        break;

      case ScheduleStage.finished:
        break;
    }

    _notify();
  }

  //Resume Helpers

  void _resumeWaiting() {
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

  void _resumeTask() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final remaining = state.remaining - const Duration(seconds: 1);

      if (remaining <= Duration.zero) {
        _timer?.cancel();
        _timer = null;
        _finishTask(state.currentTaskIndex);
        return;
      }

      _setState(
        stage: ScheduleStage.task,
        taskIndex: state.currentTaskIndex,
        remaining: remaining,
      );
    });
  }

  void _resumeBreak() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final remaining = state.remaining - const Duration(seconds: 1);

      if (remaining <= Duration.zero) {
        _timer?.cancel();
        _timer = null;
        _startTask(state.currentTaskIndex + 1);
        return;
      }

      _setState(
        stage: ScheduleStage.breakTime,
        taskIndex: state.currentTaskIndex,
        remaining: remaining,
      );
    });
  }

  //Internal

  void _startTask(int index) {
    stop();

    _setState(
      stage: ScheduleStage.task,
      taskIndex: index,
      remaining: Duration(minutes: plan.tasks[index].duration),
    );

    _resumeTask();
  }

  void _finishTask(int index) {
    if (index >= plan.breaks.length) {
      if (index + 1 >= plan.tasks.length) {
        _finishSchedule();
      } else {
        _startTask(index + 1);
      }

      return;
    }

    _startBreak(index);
  }

  void _startBreak(int index) {
    stop();

    _setState(
      stage: ScheduleStage.breakTime,
      taskIndex: index,
      remaining: Duration(minutes: plan.breaks[index]),
    );

    _resumeBreak();
  }

  void _finishSchedule() {
    stop();

    _setState(
      stage: ScheduleStage.finished,
      taskIndex: plan.tasks.length - 1,
      remaining: Duration.zero,
    );
  }

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
