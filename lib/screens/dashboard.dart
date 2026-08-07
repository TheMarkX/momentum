import 'package:flutter/material.dart';
import 'package:momentum/providers/scheduler_provider.dart';
import 'package:momentum/screens/working_screen.dart';
import 'package:provider/provider.dart';

import '../models/day_plan.dart';
import '../models/scheduler_state.dart';
import '../services/plan_service.dart';
import '../services/scheduler_service.dart';
import '../widgets/dashboard_card.dart';
import 'planner.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  final PlanService _planService = PlanService();

  DayPlan? _plan;

  @override
  void initState() {
    super.initState();
    _loadPlan();
  }

  Future<void> _loadPlan() async {
    final plan = await _planService.loadPlan();

    if (!mounted) return;

    setState(() {
      _plan = plan;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasLockedPlan = _plan != null && _plan!.locked;
    final scheduler = context.watch<SchedulerProvider>().scheduler;

    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text("Momentum")),

      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          //STREAK
          DashboardCard(
            child: Row(
              children: const [
                Icon(
                  Icons.local_fire_department,
                  size: 36,
                  color: Colors.orange,
                ),
                SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Current Streak"),
                    SizedBox(height: 4),
                    Text(
                      "0 Sessions",
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          //INTEGRITY
          DashboardCard(
            child: Row(
              children: const [
                Icon(Icons.verified, size: 36, color: Colors.green),
                SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Integrity Score"),
                    SizedBox(height: 4),
                    Text(
                      "100%",
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          //LIVE STATUS
          DashboardCard(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        hasLockedPlan ? const WorkingScreen() : const Planner(),
                  ),
                );

                _loadPlan();
              },
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: hasLockedPlan && scheduler != null
                    ? _buildLiveCard(scheduler)
                    : _buildEmptyCard(),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilledButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.bar_chart),
              label: const Text("Statistics"),
            ),
          ),

          const SizedBox(height: 90),
        ],
      ),

      floatingActionButton: FloatingActionButton(
        tooltip: "Plan your day",
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  hasLockedPlan ? const WorkingScreen() : const Planner(),
            ),
          );

          _loadPlan();
        },
        child: const Icon(Icons.edit_calendar),
      ),
    );
  }
  
  // EMPTY CARD
  Widget _buildEmptyCard() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Today's Schedule",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 20),
        Center(
          child: Column(
            children: [
              Icon(Icons.event_busy, size: 60, color: Colors.grey),
              SizedBox(height: 16),
              Text("No schedule today.", style: TextStyle(fontSize: 16)),
              SizedBox(height: 8),
              Text(
                "Tap here or press + to plan your day.",
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // LIVE CARD
  Widget _buildLiveCard(SchedulerService scheduler) {
    final state = scheduler.state;

    final remaining = state.remaining;

    final mm = remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = remaining.inSeconds.remainder(60).toString().padLeft(2, '0');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Current Task",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),

        const SizedBox(height: 18),

        Text(
          scheduler.currentTask.title,
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
        ),

        const SizedBox(height: 8),

        Text("$mm:$ss remaining", style: const TextStyle(fontSize: 18)),

        const Divider(height: 32),

        const Text("Next", style: TextStyle(fontWeight: FontWeight.bold)),

        const SizedBox(height: 8),

        if (scheduler.nextTask != null) ...[
          Text(scheduler.nextTask!.title, style: const TextStyle(fontSize: 18)),

          if (state.stage == ScheduleStage.task &&
              state.currentTaskIndex < _plan!.breaks.length)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                "${_plan!.breaks[state.currentTaskIndex]} min break first",
              ),
            ),
        ] else
          const Text("You're done for today 🎉"),
      ],
    );
  }
}
