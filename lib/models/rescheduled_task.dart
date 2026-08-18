class RescheduledTask {
  final int originalTaskIndex;

  /// The task's actual configured duration.
  ///
  /// This must NEVER be reduced by retry allocation.
  final int originalDuration;

  /// The duration currently allocated to this retry.
  ///
  /// This may be temporarily reduced when today's remaining
  /// working time is insufficient.
  final int duration;

  /// Metadata describing when this retry was scheduled.
  final DateTime? scheduledAt;

  const RescheduledTask({
    required this.originalTaskIndex,
    required this.originalDuration,
    required this.duration,
    required this.scheduledAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'originalTaskIndex': originalTaskIndex,
      'originalDuration': originalDuration,
      'duration': duration,
      'scheduledAt': scheduledAt?.toIso8601String(),
    };
  }

  factory RescheduledTask.fromJson(Map<String, dynamic> json) {
    final duration = json['duration'] as int;

    return RescheduledTask(
      originalTaskIndex: json['originalTaskIndex'] as int,

      // Backward compatibility:
      //
      // Older saved retry objects don't have originalDuration.
      // In that case, the old duration is the best available
      // representation of the original duration.
      originalDuration: json['originalDuration'] as int? ?? duration,

      duration: duration,

      scheduledAt: json['scheduledAt'] == null
          ? null
          : DateTime.parse(json['scheduledAt'] as String),
    );
  }
}
