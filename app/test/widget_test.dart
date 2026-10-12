import 'package:acme_control/core/formatters.dart';
import 'package:acme_control/features/auth/login_screen.dart';
import 'package:acme_control/models/equipment.dart';
import 'package:acme_control/models/process_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('models', () {
    test('equipment parses and reports requested vs actual state', () {
      final e = Equipment.fromJson({
        'id': 'x',
        'plant_id': 'p',
        'tag': 'P1',
        'name': 'Intake Pump',
        'type': 'pump',
        'mode': 'manual',
        'requested_state': 'run',
        'actual_state': 'starting',
        'position': '25',
        'under_maintenance': false,
        'runtime_hours': 12.5,
        'starts_count': 3,
        'params': {'rated_flow_m3h': 150},
        'sort_order': 1,
      });
      expect(e.isPump, isTrue);
      expect(e.inSync, isFalse);
      expect(e.isTransitioning, isTrue);
      expect(e.position, 25);
      expect(e.ratedFlow, 150);
      expect(e.requestedLabel, 'Run');
    });

    test('process state parses tanks and values', () {
      final s = ProcessState.fromJson({
        'plant_id': 'p',
        'scenario': 'normal',
        'sim_time': '2026-10-11T12:00:00Z',
        'speed': 1,
        'running': true,
        'values': {'LT1': 62.5, 'FT1': '10.2'},
        'tanks': {
          'T1': {'level': 62.5, 'volume': 375, 'capacity': 600, 'inflow': 10, 'outflow': 4},
        },
        'conditions': {'source_available': true, 'demand_factor': 1, 'demand_nominal': 110, 'demand_m3h': 100, 'sensor_faults': ['LT2']},
      });
      expect(s.value('LT1'), 62.5);
      expect(s.value('FT1'), 10.2);
      expect(s.tank('T1')!.netFlow, 6);
      expect(s.isFaulted('LT2'), isTrue);
    });
  });

  group('formatters', () {
    test('numbers and durations', () {
      expect(fmtNum(12.345), '12.3');
      expect(fmtNum(null), '--');
      expect(fmtHours(0.5), '30 min');
      expect(fmtDuration(const Duration(minutes: 90)), '1 h 30 min');
      expect(titleCase('in_progress'), 'In Progress');
    });
  });

  testWidgets('login screen renders demo accounts', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: LoginScreen())));
    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Operator'), findsOneWidget);
    expect(find.text('Supervisor'), findsOneWidget);
    await tester.tap(find.text('Engineer'));
    await tester.pump();
    expect(find.text('engineer@acme.demo'), findsOneWidget);
  });
}
