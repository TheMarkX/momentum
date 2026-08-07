import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/scheduler_state.dart';
import '../providers/scheduler_provider.dart';

class WorkingScreen extends StatelessWidget {
  const WorkingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheduler = context.watch<SchedulerProvider>().scheduler;

    if (scheduler == null) {
      return const Scaffold(body: Center(child: Text("No active schedule.")));
    }

    final state = scheduler.state;

    final remaining = state.remaining;
    final minutes = remaining.inMinutes
        .remainder(60)
        .toString()
        .padLeft(2, '0');
    final seconds = remaining.inSeconds
        .remainder(60)
        .toString()
        .padLeft(2, '0');

    String currentTitle;
    String nextTitle;

    switch (state.stage) {
      case ScheduleStage.waiting:
        currentTitle = "Waiting to Start";
        nextTitle = scheduler.currentTask.title;
        break;

      case ScheduleStage.task:
        currentTitle = scheduler.currentTask.title;

        if (state.currentTaskIndex < scheduler.dayPlan.breaks.length) {
          nextTitle =
              "Break (${scheduler.dayPlan.breaks[state.currentTaskIndex]} min)";
        } else if (scheduler.nextTask != null) {
          nextTitle = scheduler.nextTask!.title;
        } else {
          nextTitle = "Finish";
        }
        break;

      case ScheduleStage.breakTime:
        currentTitle =
            "Break (${scheduler.dayPlan.breaks[state.currentTaskIndex]} min)";

        nextTitle = scheduler.nextTask?.title ?? "Finish";
        break;

      case ScheduleStage.finished:
        currentTitle = "All Tasks Complete 🎉";
        nextTitle = "-";
        break;
    }

    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text("Momentum")),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const Spacer(),

              const Text(
                "Current",
                style: TextStyle(fontSize: 20, color: Colors.grey),
              ),

              const SizedBox(height: 16),

              Text(
                currentTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 40),

              Text(
                "$minutes:$seconds",
                style: const TextStyle(
                  fontSize: 72,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const Spacer(),

              const Divider(),

              const SizedBox(height: 20),

              const Text(
                "Next",
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),

              const SizedBox(height: 12),

              Text(
                nextTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
