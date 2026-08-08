enum ScheduleStage { waiting, task, taskCompletionGrace, breakTime, finished }
class SchedulerState {
  final ScheduleStage stage;

  final int currentTaskIndex;

  final Duration remaining;

  const SchedulerState({
    required this.stage,
    required this.currentTaskIndex,
    required this.remaining,
  });
}
