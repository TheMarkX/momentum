import 'package:flutter/material.dart';

class WorkingHoursCard extends StatelessWidget {
  final TimeOfDay startTime;
  final TimeOfDay endTime;

  final ValueChanged<TimeOfDay> onStartChanged;
  final ValueChanged<TimeOfDay> onEndChanged;
  final bool locked;

  const WorkingHoursCard({
    super.key,
    required this.startTime,
    required this.endTime,
    required this.locked,
    required this.onStartChanged,
    required this.onEndChanged,
  });

  Future<void> _pickTime(
    BuildContext context,
    TimeOfDay initial,
    ValueChanged<TimeOfDay> callback,
  ) async {
    final picked = await showTimePicker(context: context, initialTime: initial);

    if (picked != null) {
      callback(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),

      child: Padding(
        padding: const EdgeInsets.all(20),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            const Text(
              "Working Hours",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,

              children: [
                OutlinedButton.icon(
                  onPressed: locked
                      ? null
                      : () {
                          _pickTime(context, startTime, onStartChanged);
                        },

                  icon: const Icon(Icons.schedule),

                  label: Text(startTime.format(context)),
                ),

                const Icon(Icons.arrow_forward),

                OutlinedButton.icon(
                  onPressed: locked
                      ? null
                      : () {
                          _pickTime(context, endTime, onEndChanged);
                        },

                  icon: const Icon(Icons.schedule),

                  label: Text(endTime.format(context)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
