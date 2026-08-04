import 'package:uuid/uuid.dart';

const Uuid uuid = Uuid();

class Task {
  final String id;

  String title;
  int duration;

  bool completed;
  bool failed;
  bool rescheduled;

  Task({
    String? id,
    required this.title,
    required this.duration,
    this.completed = false,
    this.failed = false,
    this.rescheduled = false,
  }) : id = id ?? uuid.v4();

  Map<String, dynamic> toJson() {
    return {
      "id": id,
      "title": title,
      "duration": duration,
      "completed": completed,
      "failed": failed,
      "rescheduled": rescheduled,
    };
  }

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json["id"],
      title: json["title"],
      duration: json["duration"],
      completed: json["completed"] ?? false,
      failed: json["failed"] ?? false,
      rescheduled: json["rescheduled"] ?? false,
    );
  }
}
