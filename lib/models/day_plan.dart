import 'package:flutter/material.dart';

import 'task.dart';

class DayPlan {
  DateTime date;

  List<Task> tasks;

  List<int> breaks;

  TimeOfDay startTime;
  TimeOfDay endTime;

  bool locked;

  DayPlan({
    required this.date,
    required this.tasks,
    required this.breaks,
    required this.startTime,
    required this.endTime,
    this.locked = false,
  });

  // ---------- Computed Values ----------

  int get totalTaskMinutes {
    return tasks.fold(0, (total, task) => total + task.duration);
  }

  int get totalBreakMinutes {
    return breaks.fold(0, (total, minutes) => total + minutes);
  }

  int get totalPlannedMinutes {
    return totalTaskMinutes + totalBreakMinutes;
  }

  int get workingMinutes {
    final start = startTime.hour * 60 + startTime.minute;
    final end = endTime.hour * 60 + endTime.minute;

    return end - start;
  }

  int get remainingMinutes {
    return workingMinutes - totalPlannedMinutes;
  }

  bool get fitsWorkingHours {
    return remainingMinutes >= 0;
  }

  // ---------- JSON ----------

  Map<String, dynamic> toJson() {
    return {
      "date": date.toIso8601String(),
      "tasks": tasks.map((t) => t.toJson()).toList(),
      "breaks": breaks,
      "startHour": startTime.hour,
      "startMinute": startTime.minute,
      "endHour": endTime.hour,
      "endMinute": endTime.minute,
      "locked": locked,
    };
  }

  factory DayPlan.fromJson(Map<String, dynamic> json) {
    return DayPlan(
      date: DateTime.parse(json["date"]),

      tasks: (json["tasks"] as List).map((e) => Task.fromJson(e)).toList(),

      breaks: List<int>.from(json["breaks"]),

      startTime: TimeOfDay(
        hour: json["startHour"],
        minute: json["startMinute"],
      ),

      endTime: TimeOfDay(hour: json["endHour"], minute: json["endMinute"]),

      locked: json["locked"] ?? false,
    );
  }
  void lock() {
    locked = true;
  }
}
