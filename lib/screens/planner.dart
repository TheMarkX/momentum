import 'package:flutter/material.dart';
import 'package:momentum/widgets/add_task_dialog.dart';
import 'package:momentum/widgets/break_tile.dart';

import '../models/task.dart';
import '../widgets/task_tile.dart';
import '../widgets/working_hours_card.dart';

class Planner extends StatefulWidget {
  const Planner({super.key});

  @override
  State<Planner> createState() => _PlannerState();
}

class _PlannerState extends State<Planner> {
  TimeOfDay startTime = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay endTime = const TimeOfDay(hour: 17, minute: 0);

  final List<Task> tasks = [];
  List<int> breaks = [];

  Future<void> _addTask() async {
    final task = await showAddTaskDialog(context);

    if (task == null) return;

    setState(() {
      tasks.add(task);

      if (tasks.length > 1) {
        breaks.add(10);
      }
    });
  }

  void _deleteTask(int index) {
    setState(() {
      tasks.removeAt(index);

      if (breaks.isNotEmpty) {
        if (index < breaks.length) {
          breaks.removeAt(index);
        } else {
          breaks.removeLast();
        }
      }
    });
  }

  void _changeDuration(int index, int duration) {
    setState(() {
      tasks[index].duration = duration;
    });
  }

  void _changeBreak(int index, int minutes) {
    setState(() {
      breaks[index] = minutes;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Plan Your Day")),

      body: Column(
        children: [
          WorkingHoursCard(
            startTime: startTime,
            endTime: endTime,
            onStartChanged: (time) {
              setState(() {
                startTime = time;
              });
            },
            onEndChanged: (time) {
              setState(() {
                endTime = time;
              });
            },
          ),

          Expanded(
            child: tasks.isEmpty
                ? const Center(
                    child: Text(
                      "No tasks yet.\nTap + to add one.",
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    itemCount: tasks.length,
                    itemBuilder: (context, index) {
                      return Column(
                        children: [
                          TaskTile(
                            key: ValueKey(tasks[index].id),
                            task: tasks[index],
                            onDelete: () {
                              _deleteTask(index);
                            },
                            onDurationChanged: (value) {
                              _changeDuration(index, value);
                            },
                          ),

                          if (index < breaks.length)
                            BreakTile(
                              minutes: breaks[index],
                              onChanged: (value) {
                                _changeBreak(index, value);
                              },
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

                  Text(
                    "Tasks: ${tasks.fold(0, (sum, task) => sum + task.duration)} min",
                  ),

                  Text("Breaks: ${breaks.fold(0, (sum, b) => sum + b)} min"),

                  const Divider(),

                  Text(
                    "Total Planned: ${tasks.fold(0, (sum, task) => sum + task.duration) + breaks.fold(0, (sum, b) => sum + b)} min",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),

      floatingActionButton: FloatingActionButton(
        onPressed: _addTask,
        child: const Icon(Icons.add),
      ),
    );
  }
}
