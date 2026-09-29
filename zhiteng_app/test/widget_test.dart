import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zhiteng_app/core/models/pain_models.dart';
import 'package:zhiteng_app/features/history/history_body_page.dart';
import 'package:zhiteng_app/features/history/history_detail_page.dart';
import 'package:zhiteng_app/widgets/pain_body_snapshot.dart';
import 'package:zhiteng_app/features/record/pain_spot_draft.dart';
import 'package:zhiteng_app/features/record/record_page.dart';
import 'package:zhiteng_app/features/record/widgets/body_3d_webview.dart';
import 'package:zhiteng_app/features/record/widgets/medication_fields.dart';
import 'package:zhiteng_app/features/record/widgets/marker_controls.dart';
import 'package:zhiteng_app/features/record/widgets/schematic_body_locator.dart';

void main() {
  test('record page opens in quick 2D mode', () {
    expect(defaultRecordUses3d, isFalse);
  });

  test('3D preload shows skin first, then muscle and bone, never organs', () {
    expect(bodyModelInitialLayers, ['skin']);
    expect(bodyModelBackgroundLayers, ['muscle', 'bone', 'region']);
    expect(bodyModelDefaultLayers, {'skin', 'muscle', 'bone'});
    expect(bodyModelBackgroundLayers, isNot(contains('organ')));
    expect(bodyModelInitialLayers, isNot(contains('organ')));
    expect(bodyModelVersion, 'zhiteng_zanatomy_neutral_20260922_v24');
    expect(organGroupOptions.map((option) => option.id), [
      'all',
      'heart',
      'lung',
      'hepatobiliary',
      'digestive',
      'urinary',
    ]);
  });

  test('2D and 3D keep independent body-region selections', () {
    const initial = RecordRegionSelection();
    final after2d = initial.select(BodyRegion.head, use3d: false);

    expect(after2d.active(use3d: false), BodyRegion.head);
    expect(after2d.active(use3d: true), BodyRegion.full);

    final after3d = after2d.select(BodyRegion.lower, use3d: true);
    expect(after3d.active(use3d: false), BodyRegion.head);
    expect(after3d.active(use3d: true), BodyRegion.lower);

    final upper2d = after3d.select(BodyRegion.upper, use3d: false);
    expect(upper2d.active(use3d: false), BodyRegion.upper);
    expect(upper2d.active(use3d: true), BodyRegion.lower);
    final upper3d = upper2d.select(BodyRegion.upper, use3d: true);
    expect(upper3d.active(use3d: true), BodyRegion.upper);
  });

  test('2D marks follow a direction change instead of staying put', () {
    final back = remapBodyImagePoint(
      from: 'front',
      to: 'back',
      x: 0.25,
      y: 0.4,
    );
    expect(back.dx, closeTo(0.75, 1e-9));
    expect(back.dy, closeTo(0.4, 1e-9));

    final frontAgain = remapBodyImagePoint(
      from: 'back',
      to: 'front',
      x: back.dx,
      y: back.dy,
    );
    expect(frontAgain.dx, closeTo(0.25, 1e-9));

    final otherSide = remapBodyImagePoint(
      from: 'left',
      to: 'right',
      x: 0.2,
      y: 0.55,
    );
    expect(otherSide.dx, closeTo(0.8, 1e-9));
    expect(otherSide.dy, closeTo(0.55, 1e-9));

    // Front surface becomes the front edge of a side view (left image: x = 0).
    final profile = remapBodyImagePoint(
      from: 'front',
      to: 'left',
      x: 0.4,
      y: 0.3,
    );
    expect(profile.dx, 0);
    expect(profile.dy, closeTo(0.3, 1e-9));

    // A left-side view is the body's left, which is the right side of 正面.
    final face = remapBodyImagePoint(from: 'left', to: 'front', x: 0.5, y: 0.3);
    expect(face.dx, 1);
    expect(face.dy, closeTo(0.3, 1e-9));
  });

  testWidgets('switching 2D views keeps the body framing centred', (
    tester,
  ) async {
    Widget locator({required String view, required double x}) {
      return MaterialApp(
        home: Center(
          child: SizedBox(
            width: 328,
            height: 400,
            child: SchematicBodyLocator(
              x: x,
              y: 0.35,
              view: view,
              region: BodyRegion.full,
              layer: BodyLayer.skin,
              shape: PainShape.point,
              zoom: 2,
              showCrosshair: true,
              onChanged: (_) {},
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(locator(view: 'front', x: 0.2));
    final frontTransform = tester.widget<Transform>(find.byType(Transform));
    final frontTranslation = Offset(
      frontTransform.transform.storage[12],
      frontTransform.transform.storage[13],
    );

    // Face-to-profile remapping places the mark on the image edge. The body
    // itself must still retain the same centred viewport transform.
    await tester.pumpWidget(locator(view: 'left', x: 0));
    final sideTransform = tester.widget<Transform>(find.byType(Transform));
    final sideTranslation = Offset(
      sideTransform.transform.storage[12],
      sideTransform.transform.storage[13],
    );

    expect(sideTranslation.dx, closeTo(frontTranslation.dx, 1e-9));
    expect(sideTranslation.dy, closeTo(frontTranslation.dy, 1e-9));
  });

  test('2D and 3D keep independent pain-shape selections', () {
    const initial = RecordShapeSelection();
    expect(initial.active(use3d: false), PainShape.point);
    expect(initial.active(use3d: true), PainShape.point);

    final after2d = initial.select(PainShape.line, use3d: false);
    expect(after2d.active(use3d: false), PainShape.line);
    expect(after2d.active(use3d: true), PainShape.point);

    final after3d = after2d.select(PainShape.radiate, use3d: true);
    expect(after3d.active(use3d: false), PainShape.line);
    expect(after3d.active(use3d: true), PainShape.radiate);

    final backTo2d = after3d.active(use3d: false);
    expect(backTo2d, PainShape.line);
  });

  test('2D and 3D keep independent placed marks', () {
    const initial = RecordMarkSelection();
    expect(initial.active(use3d: false).picked, isFalse);
    expect(initial.active(use3d: true).picked, isFalse);

    final marked2d = initial.write(
      const RecordBodyMark(
        picked: true,
        x: 0.42,
        y: 0.3,
        view: 'front',
        partName: '左肩',
      ),
      use3d: false,
    );
    expect(marked2d.active(use3d: false).picked, isTrue);
    expect(marked2d.active(use3d: false).partName, '左肩');
    expect(marked2d.active(use3d: true).picked, isFalse);

    final marked3d = marked2d.write(
      const RecordBodyMark(
        picked: true,
        x: 0.5,
        y: 0.62,
        view: 'back',
        partName: '腰',
        localX: 0.1,
        localY: 0.2,
        localZ: 0.3,
      ),
      use3d: true,
    );
    expect(marked3d.active(use3d: false).partName, '左肩');
    expect(marked3d.active(use3d: true).partName, '腰');
    expect(marked3d.active(use3d: true).has3d, isTrue);

    final cleared3d = marked3d.write(const RecordBodyMark(), use3d: true);
    expect(cleared3d.active(use3d: true).picked, isFalse);
    expect(cleared3d.active(use3d: false).picked, isTrue);
  });

  test(
    'region options include head-neck-shoulders, upper body and lower body',
    () {
      expect(BodyRegion.values.map((region) => region.label), [
        '头部',
        '上身',
        '下身',
        '全身',
      ]);
      expect(BodyRegion.head.coverageLabel, '头、颈、肩');
      expect(BodyRegion.upper.coverageLabel, '上肢、手、上身');
      expect(BodyRegion.lower.coverageLabel, '下肢、脚');
    },
  );

  test('new and historical body-region wire values round trip', () {
    for (final region in BodyRegion.values) {
      expect(BodyRegionX.fromWire(region.wire), region);
    }
    expect(BodyRegionX.fromWire('lower'), BodyRegion.lower);
    expect(BodyRegionX.fromWire('full'), BodyRegion.full);
    expect(BodyRegionX.fromWire(null), BodyRegion.full);
  });

  test('2D region framing uses the same camera distances as 3D', () {
    expect(
      body2dRegionZoom(BodyRegion.head) / body2dRegionZoom(BodyRegion.full),
      closeTo(1.95 / 0.54, 0.001),
    );
    expect(
      body2dRegionZoom(BodyRegion.upper) / body2dRegionZoom(BodyRegion.full),
      closeTo(1.95 / 0.85, 0.001),
    );
    expect(
      body2dRegionZoom(BodyRegion.lower) / body2dRegionZoom(BodyRegion.full),
      closeTo(1.95 / 1.02, 0.001),
    );
    expect(body2dRegionFocus(BodyRegion.full).dy, closeTo(0.5, 0.001));
    expect(body2dRegionFocus(BodyRegion.head).dy, lessThan(0.2));
    expect(body2dRegionFocus(BodyRegion.upper).dy, closeTo(0.38889, 0.001));
    expect(body2dRegionFocus(BodyRegion.lower).dy, greaterThan(0.6));
  });

  test(
    '2D frames contain shoulders, fingertips and soles in the content band',
    () {
      for (final (region, lower, upper) in [
        (BodyRegion.head, 0.74, 1.0),
        (BodyRegion.upper, 0.40, 0.84),
        (BodyRegion.lower, 0.0, 0.54),
      ]) {
        final focus = body2dRegionFocus(region).dy;
        final scale = body2dRegionZoom(region);
        for (final heightFraction in [lower, upper]) {
          final imageY =
              (0.5 + body2dOrthoPadding / 2 - heightFraction) /
              body2dOrthoPadding;
          final contentY = 0.5 + (imageY - focus) * scale;
          expect(contentY, inInclusiveRange(0.0, 1.0), reason: region.label);
        }
      }
    },
  );

  test('one 3D depth step moves beyond the surface tolerance', () {
    expect(MarkerJoystick.depthStep, greaterThan(0.004));
  });

  test('3D anatomy control always combines skin with one selected layer', () {
    expect(defaultVisibleBodyLayers, {BodyLayer.skin, BodyLayer.muscle});
    expect(selectableAnatomyLayers, [
      BodyLayer.muscle,
      BodyLayer.bone,
      BodyLayer.organ,
    ]);
    expect(visibleLayersFor(BodyLayer.muscle), {
      BodyLayer.skin,
      BodyLayer.muscle,
    });
    expect(visibleLayersFor(BodyLayer.bone), {BodyLayer.skin, BodyLayer.bone});
    expect(visibleLayersFor(BodyLayer.organ), {
      BodyLayer.skin,
      BodyLayer.organ,
    });
  });

  test('guessPartName covers head region', () {
    expect(
      guessPartName(x: 0.5, y: 0.1, region: BodyRegion.head, view: 'front'),
      '头部',
    );
  });

  test('2D names keep whole-image coordinates in every regional crop', () {
    for (final region in BodyRegion.values) {
      for (final (x, y, name) in [
        (0.5, 0.1, '头部'),
        (0.5, 0.21, '颈部'),
        (0.30, 0.29, '肩部'),
        (0.27, 0.45, '前臂'),
        (0.25, 0.58, '手部'),
        (0.5, 0.40, '腹部'),
        (0.4, 0.65, '大腿'),
        (0.4, 0.72, '膝部'),
        (0.4, 0.83, '小腿'),
        (0.4, 0.94, '脚部'),
      ]) {
        expect(guessPartName(x: x, y: y, region: region, view: 'front'), name);
      }
    }
  });

  testWidgets('quick record detail omits the body image', (tester) async {
    final now = DateTime(2026, 9, 28, 12);
    PainEntry entry(List<PainLocation> locations) {
      return PainEntry(
        id: 'entry',
        createdAt: now,
        startedAt: now,
        endedAt: now,
        locations: locations,
        intensity0to10: 3,
      );
    }

    PainLocation location({
      required String id,
      required String part,
      required BodyRegion region,
    }) {
      return PainLocation(
        id: id,
        bodyPartId: id,
        normalizedX: 0.5,
        normalizedY: 0.3,
        view: 'front',
        layer: BodyLayer.skin,
        shape: PainShape.point,
        region: region,
        partName: part,
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: HistoryDetailPage(
          entry: entry([
            location(
              id: 'quick_head_center',
              part: '头部',
              region: BodyRegion.head,
            ),
          ]),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(PainBodySnapshot), findsNothing);
    expect(find.text('详情'), findsNothing);
    expect(find.text('详细信息'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: HistoryDetailPage(
          entry: entry([
            location(id: 'chest', part: '胸部', region: BodyRegion.upper),
          ]),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(PainBodySnapshot), findsOneWidget);
    expect(find.text('详情'), findsNothing);

    await tester.tap(find.byType(PainBodySnapshot));
    await tester.pumpAndSettle();
    expect(find.byType(HistoryBodyPage), findsOneWidget);
  });

  testWidgets('saved 2D history model shows pain marks without the crosshair', (
    tester,
  ) async {
    PainLocation location({
      required String id,
      required double x,
      required PainShape shape,
    }) {
      return PainLocation(
        id: id,
        bodyPartId: id,
        normalizedX: x,
        normalizedY: 0.4,
        view: 'front',
        layer: BodyLayer.skin,
        shape: shape,
        region: BodyRegion.upper,
        partName: '胸部',
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: HistoryBodyPage(
          locations: [
            location(id: 'shoulder', x: 0.32, shape: PainShape.point),
            location(id: 'chest', x: 0.5, shape: PainShape.line),
          ],
        ),
      ),
    );
    await tester.pump();

    final locator = tester.widget<SchematicBodyLocator>(
      find.byType(SchematicBodyLocator),
    );
    expect(locator.showCrosshair, isFalse);
    expect(locator.showMarker, isTrue);

    bool isPainter(Widget widget, String typeName) {
      return widget is CustomPaint &&
          widget.painter?.runtimeType.toString() == typeName;
    }

    expect(
      find.byWidgetPredicate((widget) => isPainter(widget, '_MarkerPainter')),
      paints..circle(color: const Color(0xFFE64340)),
    );
    expect(
      find.byWidgetPredicate(
        (widget) => isPainter(widget, '_PinnedMarksPainter'),
      ),
      paints..circle(color: const Color(0xFFE64340)),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 20));
  });

  test('saved body frame keeps the region the user was looking at', () {
    final upper = PainLocation(
      id: 'chest',
      bodyPartId: 'chest',
      normalizedX: 0.5,
      normalizedY: 0.8,
      view: 'front',
      layer: BodyLayer.skin,
      shape: PainShape.point,
      region: BodyRegion.upper,
      partName: '胸部',
    );
    expect(painSnapshotRegion([upper]), BodyRegion.upper);
    final crop = snapshotCropFor(locations: [upper], region: BodyRegion.upper);
    expect(crop.top, lessThan(0.25));
    expect(crop.bottom, lessThan(0.75));

    final zoomed = PainLocation(
      id: 'zoomed',
      bodyPartId: 'chest',
      normalizedX: 0.5,
      normalizedY: 0.8,
      view: 'front',
      layer: BodyLayer.organ,
      shape: PainShape.point,
      region: BodyRegion.upper,
      partName: '胸部',
      frameZoom: 2,
      frameFocusX: 0.5,
      frameFocusY: 0.34,
    );
    final tight = snapshotCropFor(
      locations: [zoomed],
      region: BodyRegion.upper,
    );
    expect(tight.height, lessThan(crop.height));
    expect(tight.center.dy, closeTo(0.34, 0.08));
  });

  test('history marks use the ortho body image, not the 3D screen point', () {
    // Recorded from the left with the camera framed on the upper body and
    // the marker pushed inward. The saved screen point lands on the pelvis
    // of the ortho picture; the body coordinate is the lower chest.
    final chest = PainLocation(
      id: 'chest',
      bodyPartId: 'hypochondriac_region_left',
      normalizedX: 0.5755,
      normalizedY: 0.4783,
      view: 'left',
      layer: BodyLayer.bone,
      shape: PainShape.line,
      region: BodyRegion.upper,
      partName: '胸部',
      localX: 0.0818,
      localY: 1.351,
      localZ: 0.0808,
      depthMeters: 0.03,
      lineAngle: -1.832595714594046,
    );
    final onFront = bodySnapshotImagePoint(chest, 'front');
    expect(onFront.dx, closeTo(0.5659, 0.002));
    expect(onFront.dy, closeTo(0.3129, 0.002));
    expect(onFront.dx, lessThan(0.7));

    final onLeft = bodySnapshotImagePoint(chest, 'left');
    expect(onLeft.dy, closeTo(onFront.dy, 0.0001));
    expect((onLeft.dy - chest.normalizedY).abs(), greaterThan(0.1));

    // Depth along the left-view axis must not slide the mark on that picture.
    final deeper = projectBodyPointToImage(
      x: chest.localX! - 0.05,
      y: chest.localY!,
      z: chest.localZ!,
      view: 'left',
    );
    expect(deeper.x, closeTo(onLeft.dx, 1e-9));
    expect(deeper.y, closeTo(onLeft.dy, 1e-9));

    final neck = PainLocation(
      id: 'neck',
      bodyPartId: 'muscular_triangle_right',
      normalizedX: 0.49187,
      normalizedY: 0.1572,
      view: 'front',
      layer: BodyLayer.skin,
      shape: PainShape.point,
      region: BodyRegion.full,
      partName: '颈部',
    );
    expect(
      bodySnapshotImagePoint(neck, 'front'),
      const Offset(0.49187, 0.1572),
    );
    expect(bodyViewRightAlignment('left', 'front'), 0);
    expect(bodyViewRightAlignment('front', 'back'), -1);
  });

  test(
    '3D part naming uses body coordinates rather than on-screen position',
    () {
      for (final (height, lateral, name) in [
        (0.92, 0.01, '头部'),
        (0.81, 0.01, '颈部'),
        (0.75, 0.10, '胸部'),
        (0.75, 0.15, '肩部'),
        (0.65, 0.13, '上臂'),
        (0.41, 0.16, '手部'),
        (0.03, 0.07, '脚部'),
      ]) {
        for (final screenY in [0.05, 0.5, 0.95]) {
          final pick = BodyPickResult(
            normalizedX: 0.5,
            normalizedY: screenY,
            view: 'front',
            bodyHeightFraction: height,
            bodyLateralFraction: lateral,
          );
          expect(pick.approximatePartName, name);
        }
      }
    },
  );

  test('open-source anatomy names resolve to the shared coarse vocabulary', () {
    expect(
      partNameFromAnatomicalSource(
        'Clavicular head of pectoralis major muscle.l',
        view: 'front',
      ),
      '胸部',
    );
    expect(
      partNameFromAnatomicalSource(
        'Acromial part of deltoid muscle.r',
        view: 'front',
      ),
      '肩部',
    );
    expect(partNameFromAnatomicalSource('Scapula.l', view: 'back'), '肩胛部');
    expect(partNameFromAnatomicalSource('Patella.r', view: 'front'), '膝部');
    expect(
      partNameFromAnatomicalSource('Anterior region of arm.l', view: 'front'),
      '上臂',
    );
    expect(partNameFromAnatomicalSource('Palm.r', view: 'front'), '手部');
    expect(
      partNameFromAnatomicalSource('Lateral malleolus.l', view: 'front'),
      '脚踝',
    );
    expect(
      partNameFromAnatomicalSource('Popliteal fossa.r', view: 'back'),
      '膝部',
    );
    expect(
      partNameFromAnatomicalSource('Cavity of concha.l', view: 'left'),
      '头部',
    );
  });

  test('every published surface region has a shared user-facing name', () {
    final data =
        jsonDecode(File('assets/models/2d/regions.json').readAsStringSync())
            as Map<String, dynamic>;
    final unmapped = (data['regions'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map((region) => region['sourceName'] as String)
        .where(
          (sourceName) =>
              partNameFromAnatomicalSource(sourceName, view: 'front') == null,
        )
        .toList();
    expect(unmapped, isEmpty);
  });

  test('surface provenance survives location JSON round trip', () {
    final location = PainLocation(
      id: 'surface-region',
      bodyPartId: 'pectoral_region_left',
      normalizedX: 0.4,
      normalizedY: 0.3,
      view: 'front',
      layer: BodyLayer.skin,
      shape: PainShape.point,
      region: BodyRegion.upper,
      partName: '胸部',
      surfaceRegionId: 'pectoral_region_left',
      surfaceRegionSourceName: 'Pectoral region.l',
    );

    final restored = PainLocation.fromJson(location.toJson());
    expect(restored.surfaceRegionId, 'pectoral_region_left');
    expect(restored.surfaceRegionSourceName, 'Pectoral region.l');
    expect(
      location.toJson()['anatomicalMappingVersion'],
      anatomicalMappingVersion,
    );
  });

  test('intensity labels stay everyday and differ across 10 levels', () {
    final labels = [
      for (var level = 1; level <= 10; level++) intensityLabel(level),
    ];
    expect(labels.toSet(), hasLength(10));
    expect(intensityLabel(1), '隐约');
    expect(intensityDetail(1), '几乎不影响，不留意就过去了。');
    expect(intensityLabel(5), '需要停一下');
    expect(intensityLabel(10), '完全无法忍受');
    expect(intensityDetail(10), '能想到的最疼，需要马上处理。');
  });

  test('2d pain location records an intentionally imprecise depth', () {
    final location = PainLocation(
      id: 'location-1',
      bodyPartId: 'abdomen',
      normalizedX: 0.5,
      normalizedY: 0.45,
      view: 'front',
      layer: BodyLayer.muscle,
      shape: PainShape.point,
      region: BodyRegion.full,
      partName: '腹部',
    );

    expect(location.coordinateMode, '2d');
    expect(location.depthState, 'internal_unknown');
    expect(location.toJson()['localXYZ'], isNull);
    expect(location.markerScale, painMarkerMinScale);
    expect(
      PainLocation.fromJson(location.toJson()).markerScale,
      painMarkerMinScale,
    );
  });

  test('thin anatomical layers cannot override a conflicting surface area', () {
    expect(
      guessPartNameOnBody(
        heightFromFeet: 0.73,
        lateralFromCenter: 0.05,
        view: 'front',
        anatomicalSourceName: 'Investing abdominal fascia.l',
      ),
      '胸部',
    );
  });

  test('2d layer choices remain distinct without inventing 3d coordinates', () {
    for (final layer in [BodyLayer.muscle, BodyLayer.bone]) {
      final location = PainLocation(
        id: 'location-${layer.wire}',
        bodyPartId: 'abdomen',
        normalizedX: 0.5,
        normalizedY: 0.45,
        view: 'front',
        layer: layer,
        shape: PainShape.point,
        region: BodyRegion.full,
        partName: '腹部',
      );

      expect(location.layer, layer);
      expect(location.depthState, 'internal_unknown');
      expect(location.toJson()['localXYZ'], isNull);
      expect(PainLocation.fromJson(location.toJson()).layer, layer);
    }
  });

  test('2d unclear layer is saved as unknown', () {
    final location = PainLocation(
      id: 'location-unknown',
      bodyPartId: 'abdomen',
      normalizedX: 0.5,
      normalizedY: 0.45,
      view: 'front',
      layer: BodyLayer.unknown,
      shape: PainShape.point,
      region: BodyRegion.full,
      partName: '腹部',
    );

    expect(location.depthState, 'unknown');
    expect(location.toJson()['layer'], 'unknown');
    expect(PainLocation.fromJson(location.toJson()).layer, BodyLayer.unknown);
  });

  test(
    'pain sensations support multi-select and an exclusive unclear choice',
    () {
      var selected = <String>{};
      selected = togglePainSensation(selected, '刺痛');
      selected = togglePainSensation(selected, '跳痛');
      expect(selected, {'刺痛', '跳痛'});

      selected = togglePainSensation(selected, '说不清楚');
      expect(selected, {'说不清楚'});

      selected = togglePainSensation(selected, '灼热痛');
      expect(selected, {'灼热痛'});
    },
  );

  test('custom pain words stay short, personal, and newest first', () {
    expect(customPainSensationMaxLength, lessThanOrEqualTo(8));
    expect(normalizeCustomPainSensation('  酸胀 '), '酸胀');
    expect(normalizeCustomPainSensation('   '), isNull);
    expect(normalizeCustomPainSensation('这是一段很长的描述不是一个词'), isNull);
    expect(hasThreeIdenticalCharactersInARow('啊啊'), isFalse);
    expect(hasThreeIdenticalCharactersInARow('aaA'), isFalse);
    expect(hasThreeIdenticalCharactersInARow('啊啊啊'), isTrue);
    expect(hasThreeIdenticalCharactersInARow('aaa'), isTrue);
    expect(hasThreeIdenticalCharactersInARow('111'), isTrue);
    expect(hasThreeIdenticalCharactersInARow('！！！'), isTrue);
    expect(hasThreeIdenticalCharactersInARow('😂😂😂'), isTrue);
    expect(hasThreeIdenticalCharactersInARow('疼啊啊啊'), isTrue);

    final saved = rememberCustomPainSensation(const ['针扎'], '火辣');
    expect(saved, ['火辣', '针扎']);
    expect(rememberCustomPainSensation(saved, '针扎'), ['针扎', '火辣']);
    expect(rememberCustomPainSensation(saved, '刺痛'), saved);
  });

  test('pain sensations survive location JSON round trip', () {
    final location = PainLocation(
      id: 'location-sensations',
      bodyPartId: 'head',
      normalizedX: 0.5,
      normalizedY: 0.2,
      view: 'front',
      layer: BodyLayer.skin,
      shape: PainShape.point,
      region: BodyRegion.head,
      partName: '头部',
      sensations: const ['刺痛', '跳痛'],
    );

    final restored = PainLocation.fromJson(location.toJson());
    expect(restored.sensations, ['刺痛', '跳痛']);
  });

  test('legacy records without marker size keep their original scale', () {
    final location = PainLocation.fromJson({
      'id': 'legacy-location',
      'bodyPartId': 'abdomen',
      'shape': 'point',
    });

    expect(location.markerScale, 1);
    expect(location.extentMeters, painMarkerBaseRadiusMeters);
    expect(location.lineAngle, 0);
  });

  test('line direction is along the body until the user turns it', () {
    expect(bodyLineHeading(upward: true, angle: 0), const Offset(0, -1));
    expect(bodyLineHeading(upward: false, angle: 0), const Offset(0, 1));
    final across = bodyLineHeading(upward: true, angle: math.pi / 2);
    expect(across.dx, closeTo(-1, 0.001));
    expect(across.dy, closeTo(0, 0.001));
    expect(lineDirectionLabel(0), '顺着身体');
    expect(lineDirectionLabel(math.pi / 2), '逆时针 90°');
    expect(lineDirectionLabel(-math.pi / 6), '顺时针 30°');

    final saved = PainLocation(
      id: 'line-1',
      bodyPartId: 'chest',
      normalizedX: 0.5,
      normalizedY: 0.3,
      view: 'front',
      layer: BodyLayer.skin,
      shape: PainShape.line,
      region: BodyRegion.full,
      partName: '胸部',
      lineAngle: math.pi / 2,
    );
    expect(
      PainLocation.fromJson(saved.toJson()).lineAngle,
      closeTo(math.pi / 2, 1e-6),
    );
  });

  test('completed pain entry keeps its end time', () {
    final endedAt = DateTime(2026, 9, 22, 12);
    final entry = PainEntry(
      id: 'entry-1',
      createdAt: endedAt,
      startedAt: endedAt.subtract(const Duration(minutes: 30)),
      endedAt: endedAt,
      status: 'completed',
      locations: const [],
      intensity0to10: 5,
    );

    final restored = PainEntry.decode(entry.encode());
    expect(restored.status, 'completed');
    expect(restored.endedAt, endedAt);
  });

  test('a pain entry keeps the medicine taken with it', () {
    final takenAt = DateTime(2026, 9, 24, 18, 20);
    final entry = PainEntry(
      id: 'entry-med',
      createdAt: takenAt,
      startedAt: takenAt.subtract(const Duration(hours: 2)),
      locations: const [],
      intensity0to10: 4,
      medications: [
        MedicationRecord(
          name: '布洛芬',
          doseAmount: 1,
          doseUnit: '片',
          takenAt: takenAt,
        ),
      ],
    );

    final restored = PainEntry.decode(entry.encode());
    expect(restored.medications, hasLength(1));
    expect(restored.medications.single.name, '布洛芬');
    expect(restored.medications.single.doseText, '1 片');
    expect(restored.medications.single.takenAt, takenAt);
    expect(formatMedicationDose(0.5), '0.5');
  });

  test('an ongoing pain keeps each change on a timeline', () {
    final end = DateTime.now().subtract(const Duration(minutes: 5));
    final level2At = end.subtract(const Duration(hours: 1));
    final medicineAt = end.subtract(const Duration(hours: 1, minutes: 30));
    final level3At = end.subtract(const Duration(hours: 2));
    final start = end.subtract(const Duration(hours: 2, minutes: 30));
    var sequence = 0;
    String nextId() => 'moment-${sequence++}';

    PainLocation spot(String part) {
      return PainLocation(
        id: part,
        bodyPartId: part,
        normalizedX: 0.42,
        normalizedY: 0.3,
        view: 'front',
        layer: BodyLayer.skin,
        shape: PainShape.point,
        region: BodyRegion.upper,
        partName: part,
        sensations: const ['隐痛'],
      );
    }

    PainEntry entryFrom(PainTimelineUpdate update) {
      return PainEntry(
        id: 'pain-1',
        createdAt: start,
        startedAt: update.startedAt,
        endedAt: update.endedAt,
        locations: update.locations,
        intensity0to10: update.intensity0to10,
        notes: update.notes,
        medications: update.medications,
        moments: update.moments,
        status: update.endedAt == null ? 'ongoing' : 'completed',
      );
    }

    final began = applyPainUpdate(
      previous: null,
      draft: PainMomentDraft(
        startedAt: start,
        changeAt: start,
        locations: [spot('右肩')],
        intensity0to10: 1,
      ),
      newId: nextId,
    );
    expect(began.saved, isTrue);
    var entry = entryFrom(began.update!);

    final worse = applyPainUpdate(
      previous: entry,
      draft: PainMomentDraft(
        startedAt: start,
        changeAt: level3At,
        locations: [spot('右肩')],
        intensity0to10: 3,
        medications: entry.medications,
      ),
      newId: nextId,
    );
    expect(worse.saved, isTrue);
    entry = entryFrom(worse.update!);

    final dose = MedicationRecord(
      name: '布洛芬',
      doseAmount: 1,
      doseUnit: '片',
      takenAt: medicineAt,
    );
    final tookMedicine = applyPainUpdate(
      previous: entry,
      draft: PainMomentDraft(
        startedAt: start,
        changeAt: medicineAt,
        locations: [spot('右肩')],
        intensity0to10: 3,
        medications: [dose],
      ),
      newId: nextId,
    );
    expect(tookMedicine.saved, isTrue);
    entry = entryFrom(tookMedicine.update!);

    final easing = applyPainUpdate(
      previous: entry,
      draft: PainMomentDraft(
        startedAt: start,
        changeAt: level2At,
        locations: [spot('右肩'), spot('左肩')],
        intensity0to10: 2,
        medications: [dose],
      ),
      newId: nextId,
    );
    expect(easing.saved, isTrue);
    entry = entryFrom(easing.update!);

    final finished = applyPainUpdate(
      previous: entry,
      draft: PainMomentDraft(
        startedAt: start,
        changeAt: end,
        endedAt: end,
        locations: [spot('右肩'), spot('左肩')],
        intensity0to10: 2,
        medications: [dose],
      ),
      newId: nextId,
    );
    expect(finished.saved, isTrue);
    entry = entryFrom(finished.update!);

    expect(captionedPainMoments(entry.timeline).map((line) => line.caption), [
      '开始 · 1 级 · 右肩 · 隐痛',
      '改为 3 级',
      '吃了布洛芬 1 片',
      '改为 2 级 · 增加左肩',
      '结束',
    ]);
    expect(painCourseLines(entry.timeline).map((line) => line.title), [
      '开始',
      '修改',
      '用药',
      '新增 · 修改',
      '结束',
    ]);
    expect(painCourseLines(entry.timeline).map((line) => line.detail), [
      '1 级 · 右肩 · 隐痛',
      '改为 3 级',
      '布洛芬 1 片',
      '改为 2 级 · 增加左肩',
      '',
    ]);
    expect(entry.isOngoing, isFalse);
    expect(intensityCourseLabel(entry), '1 级到 3 级');
    final restored = PainEntry.decode(entry.encode());
    expect(restored.moments, hasLength(entry.moments.length));
  });

  test('saving an open pain with no difference keeps the timeline', () {
    final start = DateTime.now().subtract(const Duration(hours: 2));
    final location = PainLocation(
      id: 'shoulder',
      bodyPartId: 'shoulder',
      normalizedX: 0.42,
      normalizedY: 0.3,
      view: 'front',
      layer: BodyLayer.skin,
      shape: PainShape.point,
      region: BodyRegion.upper,
      partName: '右肩',
      sensations: const ['隐痛'],
    );
    final began = applyPainUpdate(
      previous: null,
      draft: PainMomentDraft(
        startedAt: start,
        changeAt: start,
        locations: [location],
        intensity0to10: 1,
      ),
      newId: () => 'started',
    );
    final entry = PainEntry(
      id: 'pain-2',
      createdAt: start,
      startedAt: start,
      locations: [location],
      intensity0to10: 1,
      moments: began.update!.moments,
    );
    final again = applyPainUpdate(
      previous: entry,
      draft: PainMomentDraft(
        startedAt: start,
        changeAt: DateTime.now(),
        locations: [
          PainSpotDraft.fromLocation(
            location,
          ).toLocation(intensity0to10: 1, sensations: const ['隐痛']),
        ],
        intensity0to10: 1,
      ),
      newId: () => 'unused',
    );
    expect(again.unchanged, isTrue);
  });

  test('moving the start time rewrites the first moment only', () {
    final start = DateTime.now().subtract(const Duration(hours: 3));
    final earlier = start.subtract(const Duration(minutes: 20));
    final began = applyPainUpdate(
      previous: null,
      draft: PainMomentDraft(
        startedAt: start,
        changeAt: start,
        locations: [
          PainLocation(
            id: 'waist',
            bodyPartId: 'waist',
            normalizedX: 0.5,
            normalizedY: 0.55,
            view: 'back',
            layer: BodyLayer.muscle,
            shape: PainShape.point,
            region: BodyRegion.upper,
            partName: '腰部',
          ),
        ],
        intensity0to10: 2,
      ),
      newId: () => 'started',
    );
    final entry = PainEntry(
      id: 'pain-3',
      createdAt: start,
      startedAt: start,
      locations: began.update!.locations,
      intensity0to10: 2,
      moments: began.update!.moments,
    );
    final moved = applyPainUpdate(
      previous: entry,
      draft: PainMomentDraft(
        startedAt: earlier,
        changeAt: DateTime.now(),
        locations: began.update!.locations,
        intensity0to10: 2,
      ),
      newId: () => 'should-not-be-used',
    );
    expect(moved.saved, isTrue);
    expect(moved.update!.moments, hasLength(1));
    expect(moved.update!.moments.single.kind, PainMomentKind.started);
    expect(sameMinute(moved.update!.moments.single.at, earlier), isTrue);
  });

  test('dose input stays a non-negative decimal', () {
    const formatter = NonNegativeDecimalInputFormatter();
    TextEditingValue apply(String oldText, String newText) {
      return formatter.formatEditUpdate(
        TextEditingValue(text: oldText),
        TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: newText.length),
        ),
      );
    }

    expect(apply('', '2.5').text, '2.5');
    expect(apply('', '0.125').text, '0.125');
    expect(apply('2', '-1').text, '2');
    expect(apply('1.', '1.2.3').text, '1.');
    expect(apply('1', '1e2').text, '1');
    expect(apply('1.25', '1.2567').text, '1.25');

    expect(stepDoseAmount('', 1), '1');
    expect(stepDoseAmount('', -1), '');
    expect(stepDoseAmount('2', 1), '3');
    expect(stepDoseAmount('0.5', 1), '1.5');
    expect(stepDoseAmount('0.4', -1), '0');
    expect(stepDoseAmount('0', -1), '0');
  });

  testWidgets('dose stepper changes the amount and still accepts typing', (
    tester,
  ) async {
    final controller = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DoseQuantityField(controller: controller)),
      ),
    );

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(controller.text, '1');

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(controller.text, '2');

    await tester.enterText(find.byType(TextField), '2.5');
    await tester.pump();
    expect(controller.text, '2.5');

    await tester.tap(find.byIcon(Icons.remove));
    await tester.pump();
    expect(controller.text, '1.5');

    await tester.enterText(find.byType(TextField), '-3');
    await tester.pump();
    expect(controller.text, '1.5');
    controller.dispose();
  });

  testWidgets('unit menu is an iOS checkmark list', (tester) async {
    String? picked;
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              key: key,
              onPressed: () async {
                picked = await showIosOptionMenu(
                  context: context,
                  anchorKey: key,
                  options: const ['片', '粒', '毫克'],
                  selected: '片',
                );
              },
              child: const Text('打开单位'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开单位'));
    await tester.pumpAndSettle();
    expect(find.text('毫克'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.check_mark), findsOneWidget);
    final option = tester.widget<RichText>(
      find.descendant(of: find.text('毫克'), matching: find.byType(RichText)),
    );
    final span = option.text;
    expect(span, isA<TextSpan>());
    expect(
      (span as TextSpan).style?.decoration,
      isNot(TextDecoration.underline),
    );

    await tester.tap(find.text('毫克'));
    await tester.pumpAndSettle();
    expect(picked, '毫克');
  });

  testWidgets('medication time asks the system date picker', (tester) async {
    const channel = MethodChannel('zhiteng/system_datetime');
    final messenger = tester.binding.defaultBinaryMessenger;
    Map<dynamic, dynamic>? args;
    messenger.setMockMethodCallHandler(channel, (call) async {
      args = call.arguments as Map;
      return DateTime(2026, 9, 28, 16, 9).millisecondsSinceEpoch;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    DateTime? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              picked = await showIosDateTimePicker(
                context: context,
                initialDateTime: DateTime(2026, 9, 28, 16, 9),
                minimumDate: DateTime(2020),
                maximumDate: DateTime(2026, 9, 28, 16, 9),
              );
            },
            child: const Text('打开时间'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开时间'));
    await tester.pump();
    final initial = DateTime(2026, 9, 28, 16, 9);
    expect(args?['initial'], initial.millisecondsSinceEpoch);
    expect(args?['minimum'], DateTime(2020).millisecondsSinceEpoch);
    expect(args?['maximum'], initial.millisecondsSinceEpoch);
    expect(picked, initial);
  });
}
