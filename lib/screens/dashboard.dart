import 'package:flutter/material.dart';

import '../widgets/dashboard_card.dart';
import 'planner.dart';

class Dashboard extends StatelessWidget {
  const Dashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Momentum"), centerTitle: true),

      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          DashboardCard(
            child: Row(
              children: [
                const Icon(
                  Icons.local_fire_department,
                  size: 36,
                  color: Colors.orange,
                ),

                const SizedBox(width: 16),

                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Current Streak", style: TextStyle(fontSize: 16)),

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

          DashboardCard(
            child: Row(
              children: [
                const Icon(Icons.verified, size: 36, color: Colors.green),

                const SizedBox(width: 16),

                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Integrity Score", style: TextStyle(fontSize: 16)),

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

          DashboardCard(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),

              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const Planner()),
                );
              },

              child: const Padding(
                padding: EdgeInsets.all(8),

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Today's Schedule",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    SizedBox(height: 20),

                    Center(
                      child: Column(
                        children: [
                          Icon(Icons.event_busy, size: 60, color: Colors.grey),

                          SizedBox(height: 16),

                          Text(
                            "No schedule today.",
                            style: TextStyle(fontSize: 16),
                          ),

                          SizedBox(height: 8),

                          Text(
                            "Tap here or press + to plan your day.",
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilledButton.icon(
              onPressed: () {
                // Statistics screen (Phase 11)
              },

              icon: const Icon(Icons.bar_chart),

              label: const Text("Statistics"),
            ),
          ),

          const SizedBox(height: 90),
        ],
      ),

      floatingActionButton: FloatingActionButton(
        tooltip: "Plan your day",

        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const Planner()),
          );
        },

        child: const Icon(Icons.edit_calendar),
      ),
    );
  }
}
