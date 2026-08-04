import 'package:flutter/material.dart';

import '../models/task.dart';

class TaskTile extends StatelessWidget {
  final Task task;

  final VoidCallback onDelete;

  final ValueChanged<int> onDurationChanged;

  const TaskTile({
    super.key,
    required this.task,
    required this.onDelete,
    required this.onDurationChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),

      child: ListTile(
        title: Text(
          task.title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),

        subtitle: InkWell(
          onTap: () async {
            final controller = TextEditingController(
              text: task.duration.toString(),
            );

            final result = await showDialog<int>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text("Task Duration"),
                content: TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(suffixText: "min"),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Cancel"),
                  ),
                  FilledButton(
                    onPressed: () {
                      final minutes = int.tryParse(controller.text);

                      if (minutes != null && minutes >= 5) {
                        Navigator.pop(context, minutes);
                      }
                    },
                    child: const Text("Save"),
                  ),
                ],
              ),
            );

            if (result != null) {
              onDurationChanged(result);
            }
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.schedule, size: 18),
              const SizedBox(width: 6),
              Text("${task.duration} min"),
              const SizedBox(width: 6),
              Icon(
                Icons.edit,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
            ],
          ),
        ),

        leading: const Icon(Icons.drag_handle),

        trailing: Row(
          mainAxisSize: MainAxisSize.min,

          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),

              onPressed: () {
                if (task.duration > 5) {
                  onDurationChanged(task.duration - 5);
                }
              },
            ),

            IconButton(
              icon: const Icon(Icons.add_circle_outline),

              onPressed: () {
                onDurationChanged(task.duration + 5);
              },
            ),

            IconButton(icon: const Icon(Icons.delete), onPressed: onDelete),
          ],
        ),
      ),
    );
  }
}
