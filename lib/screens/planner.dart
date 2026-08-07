import 'package:flutter/material.dart';
import 'package:momentum/providers/scheduler_provider.dart';
import 'package:provider/provider.dart';

import '../models/day_plan.dart';
import '../services/plan_service.dart';
import '../widgets/add_task_dialog.dart';
import '../widgets/break_tile.dart';
import '../widgets/task_tile.dart';
import '../widgets/working_hours_card.dart';

class Planner extends StatefulWidget {
  const Planner({super.key});

  @override
  State<Planner> createState() => _PlannerState();
}

class _PlannerState extends State<Planner> {
  DayPlan? plan;

  final PlanService _planService = PlanService();

  @override
  void initState() {
    super.initState();
    _loadPlan();
  }

  Future<void> _loadPlan() async {
    final saved = await _planService.loadPlan();

    setState(() {
      plan =
          saved ??
          DayPlan(
            date: DateTime.now(),
            tasks: [],
            breaks: [],
            startTime: const TimeOfDay(hour: 8, minute: 0),
            endTime: const TimeOfDay(hour: 17, minute: 0),
          );
    });
  }

  Future<void> _updatePlan(VoidCallback update) async {
    setState(update);
    await _planService.savePlan(plan!);
  }

  Future<void> _addTask() async {
    final task = await showAddTaskDialog(context);

    if (task == null) return;

    await _updatePlan(() {
      plan!.tasks.add(task);

      if (plan!.tasks.length > 1) {
        plan!.breaks.add(10);
      }
    });
  }

  Future<void> _deleteTask(int index) async {
    await _updatePlan(() {
      plan!.tasks.removeAt(index);

      if (plan!.breaks.isNotEmpty) {
        if (index < plan!.breaks.length) {
          plan!.breaks.removeAt(index);
        } else {
          plan!.breaks.removeLast();
        }
      }
    });
  }

  Future<void> _changeDuration(int index, int duration) async {
    await _updatePlan(() {
      plan!.tasks[index].duration = duration;
    });
  }

  Future<void> _changeBreak(int index, int minutes) async {
    await _updatePlan(() {
      plan!.breaks[index] = minutes;
    });
  }

  Future<void> _changeStartTime(TimeOfDay time) async {
    await _updatePlan(() {
      plan!.startTime = time;
    });
  }

  Future<void> _changeEndTime(TimeOfDay time) async {
    await _updatePlan(() {
      plan!.endTime = time;
    });
  }

  Future<void> _lockPlan() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text("Lock Today's Plan"),
          content: const Text(
            "Once locked, today's tasks, durations, breaks and working hours cannot be changed.\n\nAre you sure?",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel"),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Lock In"),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    await _updatePlan(() {
      plan!.lock();
    });

    if (!mounted) return;

    // Start the global scheduler
    final scheduler = context.read<SchedulerProvider>();

    scheduler.loadPlan(plan!);
    scheduler.start();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Today's schedule has been locked.")),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (plan == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(plan!.locked ? "Today's Schedule 🔒" : "Plan Your Day"),
      ),

      floatingActionButton: FloatingActionButton(
        onPressed: plan!.locked ? null : _addTask,
        child: const Icon(Icons.add),
      ),

      body: Column(
        children: [
          if (plan!.locked)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              color: Colors.green,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock, color: Colors.white),
                  SizedBox(width: 8),
                  Text(
                    "Today's schedule is locked",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

          WorkingHoursCard(
            startTime: plan!.startTime,
            endTime: plan!.endTime,
            locked: plan!.locked,
            onStartChanged: _changeStartTime,
            onEndChanged: _changeEndTime,
          ),

          Expanded(
            child: plan!.tasks.isEmpty
                ? const Center(
                    child: Text(
                      "No tasks yet.\nTap + to add one.",
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 12),
                    itemCount: plan!.tasks.length,
                    itemBuilder: (context, index) {
                      return Column(
                        children: [
                          TaskTile(
                            key: ValueKey(plan!.tasks[index].id),
                            task: plan!.tasks[index],
                            locked: plan!.locked,
                            onDelete: () => _deleteTask(index),
                            onDurationChanged: (value) =>
                                _changeDuration(index, value),
                          ),

                          if (index < plan!.breaks.length)
                            BreakTile(
                              minutes: plan!.breaks[index],
                              locked: plan!.locked,
                              onChanged: (value) => _changeBreak(index, value),
                            ),
                        ],
                      );
                    },
                  ),
          ),

          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Today's Total",
                    style: Theme.of(context).textTheme.titleMedium,
                  ),

                  const SizedBox(height: 10),

                  Text("Tasks: ${plan!.totalTaskMinutes} min"),

                  Text("Breaks: ${plan!.totalBreakMinutes} min"),

                  const Divider(),

                  Text(
                    "Total Planned: ${plan!.totalPlannedMinutes} min",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),

                  if (!plan!.fitsWorkingHours)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        "⚠ Planned time exceeds working hours.",
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: Icon(plan!.locked ? Icons.lock : Icons.lock_open),
                label: Text(plan!.locked ? "Locked" : "Lock In"),
                onPressed: plan!.locked ? null : _lockPlan,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
