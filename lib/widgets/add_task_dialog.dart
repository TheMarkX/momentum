import 'package:flutter/material.dart';

import '../models/task.dart';

Future<Task?> showAddTaskDialog(BuildContext context) async {
  final titleController = TextEditingController();
  final durationController = TextEditingController(text: "60");

  return showDialog<Task>(
    context: context,
    builder: (_) {
      return AlertDialog(
        title: const Text("Add Task"),

        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: "Task Title"),
            ),

            const SizedBox(height: 16),

            TextField(
              controller: durationController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Duration (minutes)",
              ),
            ),
          ],
        ),

        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text("Cancel"),
          ),

          FilledButton(
            onPressed: () {
              final title = titleController.text.trim();

              final duration = int.tryParse(durationController.text) ?? 60;

              if (title.isEmpty) return;

              Navigator.pop(context, Task(title: title, duration: duration));
            },
            child: const Text("Add"),
          ),
        ],
      );
    },
  );
}
