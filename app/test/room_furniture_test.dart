import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/room/room_layout_data.dart';
import 'package:lifesim/room/room_scene.dart';
import 'package:lifesim/room/room_sim.dart';
import 'package:lifesim/ui/twin_appearance.dart';

const layout = roomLayout;

/// Where walks start and end: the start, every wander target, waypoint and
/// action spot (the bed spot is reached only by the Sleep hop).
final places = <Offset>[
  const Offset(0.35, 0.3),
  ...layout.wander,
  ...layout.waypoints,
  for (final e in layout.spots.entries)
    if (e.key != 'bed') e.value,
];

/// Steps [sim] [steps] times by [dt], checking every frame: off the bed's
/// hop, the feet never enter a padded footprint and no move crosses one
/// (the hop starts at the bedside, so the walk there is checked too).
/// Calls [each] after every step.
void runChecked(RoomSim sim, int steps, {double dt = 0.05, void Function(int i)? each}) {
  var prev = sim.pos;
  var prevInBed = sim.inBed;
  for (var i = 0; i < steps; i++) {
    sim.step(dt);
    if (!sim.inBed || !prevInBed) {
      expect(layout.blocked(sim.pos), isFalse, reason: 'step $i: the feet at ${sim.pos} are inside furniture');
      if (!prevInBed) {
        expect(layout.clear(prev, sim.pos), isTrue, reason: 'step $i: $prev -> ${sim.pos} crosses furniture');
      }
    }
    prev = sim.pos;
    prevInBed = sim.inBed;
    each?.call(i);
  }
}

void main() {
  test('the padded footprints come from the prototype and contain the true ones', () {
    expect(layout.footprints.keys, containsAll(['bed', 'table', 'plant']));
    expect(layout.obstacles.length, layout.footprints.length);
    for (final (i, f) in layout.footprints.values.indexed) {
      final o = layout.obstacles[i];
      expect(o.left, closeTo(f.left - layout.bearRadius, 1e-3));
      expect(o.top, closeTo(f.top - layout.bearRadius, 1e-3));
      expect(o.right, closeTo(f.right + layout.bearRadius, 1e-3));
      expect(o.bottom, closeTo(f.bottom + layout.bearRadius, 1e-3));
    }
    // The bed spot is on the quilt; everything else is on open floor.
    expect(layout.blocked(layout.spots['bed']!), isTrue);
    for (final p in places) {
      expect(layout.blocked(p), isFalse, reason: '$p');
      expect(layout.bounds.contains(p), isTrue, reason: '$p');
    }
  });

  test('every planned path between walk places is clear, segment by segment', () {
    for (final a in places) {
      for (final b in places) {
        final path = layout.planPath(a, b);
        expect(path.last, b);
        var from = a;
        for (final p in path) {
          expect(layout.clear(from, p), isTrue, reason: '$a -> $b: segment $from -> $p crosses furniture');
          from = p;
        }
      }
    }
    // A walk past the foot of the bed detours instead of cutting across it.
    const left = Offset(-1.4, -1.0), right = Offset(1.3, -1.0);
    expect(layout.clear(left, right), isFalse);
    expect(layout.planPath(left, right).length, greaterThan(1));
  });

  test('random wander over 2,000 seeded steps never enters or crosses furniture', () {
    for (final seed in [1, 2, 3, 7, 42]) {
      final sim = RoomSim(layout: layout, random: math.Random(seed));
      addTearDown(sim.dispose);
      final visited = <Offset>{};
      runChecked(sim, 2000, each: (_) => visited.add(sim.pos));
      expect(visited.length, greaterThan(200), reason: 'seed $seed: the twin wandered');
      expect(sim.onBed, isFalse);
    }
  });

  test('Exercise, Eat, Fortune and Sleep from every idle position avoid the bed', () {
    for (final start in places) {
      for (final a in RoomAction.values) {
        final sim = RoomSim(layout: layout, random: math.Random(5))..pos = start;
        sim.onFortune = sim.fortuneDone;
        Offset? hopFrom;
        sim.startAction(a);
        runChecked(
          sim,
          600,
          each: (_) {
            if (sim.inBed) hopFrom ??= sim.pos;
          },
        );
        final where = '$a from $start';
        if (a == RoomAction.sleep) {
          expect(sim.onBed, isTrue, reason: '$where: asleep on the bed');
          expect(hopFrom, layout.spots['sleepSide'], reason: '$where: hops on from the bedside');
          expect((sim.pos - layout.spots['bed']!).distance, lessThan(1e-9));
        } else {
          expect(sim.onBed, isFalse, reason: where);
          expect(sim.action, isNull, reason: '$where: the action ran and finished');
        }
        sim.dispose();
      }
    }
  });

  test('an action pressed mid-hop lands, gets up at the bedside, then walks around the bed', () {
    final sim = RoomSim(layout: layout)..pos = const Offset(-1.4, -1.0);
    addTearDown(sim.dispose);
    sim.startAction(RoomAction.sleep);
    var i = 0;
    while (!sim.inBed && i++ < 400) {
      sim.step(0.05);
    }
    sim.step(0.05); // mid-climb
    expect(sim.inBed && !sim.onBed, isTrue);
    sim.startAction(RoomAction.eat);
    final said = <String>{};
    runChecked(sim, 400, each: (_) => said.add(sim.status));
    expect(said, containsAll(['Good morning!', 'Crunch, crunch!', 'Full and happy']));
    expect(sim.onBed, isFalse);
  });

  test('from every idle spot to the shelf: every segment is clear and the walk gets there', () {
    final shelf = layout.spots['fortune']!;
    final idle = <String, Offset>{
      'start': const Offset(0.35, 0.3),
      for (final (i, w) in layout.wander.indexed) 'wander$i': w,
      for (final k in ['rug', 'exercise', 'eat', 'sleepSide']) k: layout.spots[k]!,
    };
    for (final MapEntry(key: name, value: from) in idle.entries) {
      final path = layout.planPath(from, shelf);
      expect(path.last, shelf, reason: name);
      var a = from;
      for (final p in path) {
        expect(layout.clear(a, p), isTrue, reason: '$name: segment $a -> $p crosses furniture');
        expect(layout.blocked(p), isFalse, reason: '$name: node $p is inside furniture');
        a = p;
      }
      // And the twin really walks it, frame by frame, to the shelf.
      final sim = RoomSim(layout: layout, random: math.Random(3))..pos = from;
      addTearDown(sim.dispose);
      sim.startAction(RoomAction.fortune);
      var arrived = false;
      runChecked(sim, 400, each: (_) => arrived |= sim.status == 'Hmm, let me see');
      expect(arrived, isTrue, reason: '$name: reached the shelf');
      expect((sim.pos - shelf).distance, lessThan(1e-9), reason: name);
    }
  });

  test('a frame hitch (large dt) never moves the twin past a corner or through furniture', () {
    // Corners of every planned walk are where a big step could cut across a box: walk the
    // longest detours with huge, erratic frame times and check every move.
    const maxMove = 0.82 * 0.05; // walking speed x the per-step dt cap
    for (final dt in [0.05, 0.1, 0.25, 0.5, 1.0, 5.0]) {
      for (final start in places) {
        for (final a in [RoomAction.fortune, RoomAction.exercise, RoomAction.sleep]) {
          final sim = RoomSim(layout: layout, random: math.Random(11))..pos = start;
          sim.onFortune = sim.fortuneDone;
          sim.startAction(a);
          var prev = sim.pos;
          for (var i = 0; i < 400; i++) {
            final wasInBed = sim.inBed;
            sim.step(i.isEven ? dt : 1 / 60);
            if (!sim.inBed && !wasInBed) {
              expect(
                (sim.pos - prev).distance,
                lessThanOrEqualTo(maxMove + 1e-9),
                reason: '$a from $start at dt $dt: step $i moved too far',
              );
              expect(layout.blocked(sim.pos), isFalse, reason: '$a from $start at dt $dt: step $i inside furniture');
              expect(layout.clear(prev, sim.pos), isTrue, reason: '$a from $start at dt $dt: step $i cut a corner');
            }
            prev = sim.pos;
          }
          sim.dispose();
        }
      }
    }
  });

  test('stress: 20,000 random steps x 10 seeds with presses, taps, mid-hop presses and hitches', () {
    for (var seed = 1; seed <= 10; seed++) {
      final sim = RoomSim(layout: layout, random: math.Random(seed));
      final drive = math.Random(1000 + seed);
      var fortunes = 0;
      sim.onFortune = () => fortunes++;
      var prev = sim.pos;
      var prevInBed = sim.inBed;
      var sleeps = 0, midHop = 0;
      final visited = <String>{};
      for (var i = 0; i < 20000; i++) {
        final x = drive.nextDouble();
        if (x < 0.006) {
          sim.press(RoomAction.values[drive.nextInt(RoomAction.values.length)]);
        } else if (x < 0.008) {
          sim.tapTwin();
        } else if (x < 0.009) {
          sim.longPressTwin();
        }
        if (sim.action == RoomAction.fortune && drive.nextDouble() < 0.02) sim.fortuneDone();
        // Mid-hop presses: an action while the twin is in the air onto the bed.
        if (sim.inBed && !sim.onBed && sim.action == RoomAction.sleep && drive.nextDouble() < 0.3) {
          midHop++;
          sim.startAction(drive.nextBool() ? RoomAction.eat : RoomAction.exercise);
        }
        final wasOnBed = sim.onBed;
        final y = drive.nextDouble();
        sim.step(y < 0.01 ? 0.5 + drive.nextDouble() * 2 : (y < 0.15 ? 0.05 : 1 / 60));
        if (!wasOnBed && sim.onBed) sleeps++;
        final p = sim.pos, ib = sim.inBed;
        if (!ib && layout.blocked(p)) fail('seed $seed step $i: feet at $p inside furniture');
        if (!ib && !prevInBed && !layout.clear(prev, p)) fail('seed $seed step $i: $prev -> $p crosses furniture');
        visited.add('${p.dx.toStringAsFixed(1)},${p.dy.toStringAsFixed(1)}');
        prev = p;
        prevInBed = ib;
      }
      expect(visited.length, greaterThan(40), reason: 'seed $seed: the twin got around the room');
      expect(sleeps, greaterThan(0), reason: 'seed $seed: slept at least once');
      expect(fortunes + midHop, greaterThan(0), reason: 'seed $seed');
      sim.dispose();
    }
  });

  group('draw order', () {
    final bed = layout.footprints['bed']!, table = layout.footprints['table']!;

    test('the bed covers a twin behind it, never one in front', () {
      expect(layout.covers(bed, const Offset(-1.4, -1.0)), isTrue, reason: 'left of the bed, deeper in the room');
      expect(layout.covers(bed, const Offset(-1.6, -0.6)), isTrue);
      expect(layout.covers(bed, const Offset(-1.6, -0.3)), isFalse, reason: 'left, but in front of the foot');
      expect(layout.covers(bed, const Offset(0.3, 0.1)), isFalse, reason: 'in front of the foot');
      expect(layout.covers(bed, layout.spots['sleepSide']!), isFalse, reason: 'beside it, toward the camera');
      expect(layout.covers(bed, layout.spots['fortune']!), isFalse);
    });

    test('the table uses the same rule', () {
      expect(layout.covers(table, layout.spots['rug']!), isTrue, reason: 'the rug is behind the table');
      expect(layout.covers(table, layout.spots['eat']!), isFalse, reason: 'eating in front of it');
      expect(layout.covers(table, const Offset(0.3, 0.1)), isFalse);
    });

    Future<List<Widget>> layers(WidgetTester t, Offset at) async {
      final sim = RoomSim(layout: layout)..pos = at;
      addTearDown(sim.dispose);
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          home: RoomScene(sim: sim, appearance: const TwinAppearance()),
        ),
      );
      final stack = find.descendant(of: find.byType(RoomScene), matching: find.byType(Stack)).first;
      return t.widget<Stack>(stack).children;
    }

    int at(List<Widget> order, String key) => order.indexWhere((w) => w.key == ValueKey(key));

    testWidgets('behind the bed: the whole bed is drawn over the twin', (t) async {
      final order = await layers(t, const Offset(-1.4, -1.0));
      expect(at(order, 'room-bed-over'), greaterThan(at(order, 'room-twin')));
      expect(at(order, 'room-twin'), greaterThanOrEqualTo(0));
      final bed = order[at(order, 'room-bed-over')] as Positioned;
      expect(((bed.child as IgnorePointer).child as ExcludeSemantics).child, isA<Image>());
    });

    testWidgets('in front of the bed: the bed is not drawn over the twin', (t) async {
      for (final p in [const Offset(0.3, 0.1), layout.spots['sleepSide']!, layout.spots['fortune']!]) {
        final order = await layers(t, p);
        expect(at(order, 'room-bed-over'), -1, reason: '$p');
        expect(at(order, 'room-twin'), greaterThanOrEqualTo(0));
      }
    });

    testWidgets('behind the table: the table is drawn over the twin', (t) async {
      final order = await layers(t, layout.spots['rug']!);
      expect(at(order, 'room-table-over'), greaterThan(at(order, 'room-twin')));
      expect(at(order, 'room-bed-over'), -1);
    });
  });
}
