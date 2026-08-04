import 'package:flutter/material.dart';

class BreakTile extends StatelessWidget {
  final int minutes;
  final ValueChanged<int> onChanged;

  const BreakTile({super.key, required this.minutes, required this.onChanged});

  Future<void> _editBreak(BuildContext context) async {
    final controller = TextEditingController(text: minutes.toString());

    final result = await showDialog<int>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text("Break Duration"),

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
                final value = int.tryParse(controller.text);

                if (value == null) return;

                Navigator.pop(context, value);
              },
              child: const Text("Save"),
            ),
          ],
        );
      },
    );

    if (result != null && result >= 5 && result <= 25) {
      onChanged(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30),

      child: ListTile(
        leading: const Icon(Icons.coffee),

        title: const Text("Break"),

        subtitle: GestureDetector(
          onTap: () => _editBreak(context),

          child: Text(
            "$minutes min",
            style: const TextStyle(decoration: TextDecoration.underline),
          ),
        ),
      ),
    );
  }
}
