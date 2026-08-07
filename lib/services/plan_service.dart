import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/day_plan.dart';

class PlanService {
  static const String _planKey = "today_plan";

  Future<void> savePlan(DayPlan plan) async {
    final prefs = await SharedPreferences.getInstance();

    final json = jsonEncode(plan.toJson());

    await prefs.setString(_planKey, json);
  }

  Future<DayPlan?> loadPlan() async {
    final prefs = await SharedPreferences.getInstance();

    final json = prefs.getString(_planKey);

    if (json == null) {
      return null;
    }

    return DayPlan.fromJson(jsonDecode(json));
  }

  Future<void> deletePlan() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(_planKey);
  }
}
