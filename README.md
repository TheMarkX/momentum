# Momentum

Momentum is a productivity and task scheduling application built with Flutter. It is designed around structured working hours, task execution, accountability, completion confirmation, breaks, and automatic rescheduling of unfinished work.

The project focuses on maintaining a reliable daily workflow while ensuring that failed or unfinished tasks are not silently lost.

---

## Overview

Momentum provides a structured scheduling system for users who want their workday to operate according to a predefined plan rather than relying entirely on manual time management.

The scheduler manages:

- Daily working hours
- Ordered tasks
- Task durations
- Breaks between tasks
- Task completion confirmation
- Completion grace periods
- Accountability notifications
- Failed task detection
- Automatic retry scheduling
- Multiple rescheduled tasks
- Working-hours constraints
- Cross-day task rescheduling
- Persistent retry queues
- Recovery after application restarts
- Dynamic working-hours changes

The core scheduling principle is simple:

> A task that is not completed should be rescheduled rather than forgotten.

---

## Features

### Task Scheduling

Momentum executes tasks according to a configured `DayPlan`.

Each task can contain:

- Title
- Duration
- Position in the schedule

Tasks are processed sequentially and transition through the scheduler's state machine.
