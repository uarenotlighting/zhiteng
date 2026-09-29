import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/pain_models.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/pain_body_snapshot.dart';
import '../../widgets/zt_motion.dart';
import '../record/widgets/body_3d_webview.dart';
import '../record/widgets/marker_controls.dart';
import '../record/widgets/schematic_body_locator.dart';

/// Read-only body model for one saved record.
///
/// The stage matches the recorder: the same 2D map or 3D model, the region
/// and anatomy that were selected, and the saved zoom. Taps do not move the
/// mark, and the joystick stays closed. Zoom and, on 3D, 侧看深度 still work.
class HistoryBodyPage extends StatefulWidget {
  const HistoryBodyPage({super.key, required this.locations});

  final List<PainLocation> locations;

  @override
  State<HistoryBodyPage> createState() => _HistoryBodyPageState();
}

class _HistoryBodyPageState extends State<HistoryBodyPage> {
  static const double _zoomStep = 1.12;

  final _body3dKey = GlobalKey<Body3dWebViewState>();
  late final bool _use3d;
  late final List<PainLocation> _marks;
  late final PainLocation _primary;
  late double _zoom2d;
  bool _skinReady = false;

  @override
  void initState() {
    super.initState();
    _marks = widget.locations
        .where((location) => !isQuickPainLocation(location))
        .toList();
    _use3d = _marks.any(
      (location) => location.coordinateMode == '3d' && location.localX != null,
    );
    final modeMarks = _marks.where((location) {
      final is3d = location.coordinateMode == '3d' && location.localX != null;
      return _use3d ? is3d : !is3d;
    }).toList();
    _primary = modeMarks.isEmpty ? _marks.last : modeMarks.last;
    _zoom2d = body2dRegionZoom(_primary.region) * _primary.frameZoom;
  }

  BodyLayer get _anatomy => _use3d
      ? _primary.displayAnatomyLayer
      : (_primary.layer == BodyLayer.unknown ? BodyLayer.skin : _primary.layer);

  String get _viewLabel =>
      bodyViewOptions
          .where((option) => option.$1 == _primary.view)
          .map((option) => option.$2)
          .firstOrNull ??
      '正面';

  void _zoomBy(double factor) {
    if (_use3d) {
      _body3dKey.currentState?.zoom(factor);
      return;
    }
    setState(() {
      _zoom2d = (_zoom2d * factor).clamp(body2dMinZoom, body2dMaxZoom);
    });
  }

  void _resetZoom() {
    if (_use3d) {
      _body3dKey.currentState?.resetView();
      _body3dKey.currentState?.setView(_primary.view);
      if ((_primary.frameZoom - 1).abs() > 0.02) {
        _body3dKey.currentState?.zoom(_primary.frameZoom);
      }
      return;
    }
    setState(() {
      _zoom2d = body2dRegionZoom(_primary.region) * _primary.frameZoom;
    });
  }

  void _showSavedModel() {
    final view = _body3dKey.currentState;
    if (view == null) return;
    view.setPlacementEnabled(false);
    view.setView(_primary.view);
    final others = <Map<String, Object?>>[];
    for (final location in _marks) {
      if (location.localX == null ||
          location.localY == null ||
          location.localZ == null) {
        continue;
      }
      if (identical(location, _primary)) continue;
      others.add({
        'localX': location.localX,
        'localY': location.localY,
        'localZ': location.localZ,
        'markerScale': location.markerScale,
        'shape': location.shape.wire,
      });
    }
    view.setPinnedMarkers(others);
    view.restoreMarker(
      x: _primary.localX!,
      y: _primary.localY!,
      z: _primary.localZ!,
      depth: _primary.depthMeters,
    );
    view.setShape(_primary.shape);
    view.setMarkerScale(_primary.markerScale);
    view.setLineLength(_primary.lineLength);
    view.setLineAngle(_primary.lineAngle);
    if ((_primary.frameZoom - 1).abs() > 0.02) {
      view.zoom(_primary.frameZoom);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final topInset = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
          ),
      child: Scaffold(
        backgroundColor: AppColors.bodyStageFor(dark: dark),
        body: Stack(
          children: [
            Positioned.fill(child: _stage()),
            if (_use3d && !_skinReady)
              Align(
                alignment: Alignment.center,
                child: Text(
                  '加载人体模型…',
                  style: TextStyle(
                    color: dark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
            Positioned(
              top: topInset + 8,
              left: 12,
              right: 12,
              child: _titleBar(),
            ),
            Positioned(
              top: topInset + 58,
              left: 12,
              right: 12,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SavedParameters(
                    labels: [_viewLabel, _use3d ? '3D' : '2D', _anatomy.label],
                  ),
                  const Spacer(),
                  StageZoomControl(
                    onZoomIn: () => _zoomBy(_zoomStep),
                    onZoomOut: () => _zoomBy(1 / _zoomStep),
                    onReset: _resetZoom,
                  ),
                ],
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: bottomInset + 10,
              child: _RecordInfo(dark: dark, locations: _marks),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stage() {
    if (!_use3d) {
      final focus = _primary.frameFocusX != null && _primary.frameFocusY != null
          ? Offset(_primary.frameFocusX!, _primary.frameFocusY!)
          : null;
      final pinned = <Body2dMark>[
        for (final location in _marks)
          if (!identical(location, _primary))
            Body2dMark(
              x: location.normalizedX,
              y: location.normalizedY,
              view: location.view,
              layer: location.layer,
              shape: location.shape,
              markerScale: location.markerScale,
              lineLength: location.lineLength,
              lineAngle: location.lineAngle,
            ),
      ];
      return SchematicBodyLocator(
        x: _primary.normalizedX,
        y: _primary.normalizedY,
        view: _primary.view,
        region: _primary.region,
        layer: _anatomy,
        shape: _primary.shape,
        markerScale: _primary.markerScale,
        lineLength: _primary.lineLength,
        lineAngle: _primary.lineAngle,
        zoom: _zoom2d,
        showCrosshair: false,
        showMarker: true,
        pinnedMarks: pinned,
        retargetOnViewChange: false,
        interactive: false,
        initialFocus: focus,
        onChanged: (_) {},
      );
    }
    final anatomy = selectableAnatomyLayers.contains(_anatomy)
        ? _anatomy
        : BodyLayer.muscle;
    return Body3dWebView(
      key: _body3dKey,
      region: _primary.region,
      layers: visibleLayersFor(anatomy),
      active: true,
      showCrosshair: false,
      shape: _primary.shape,
      markerScale: _primary.markerScale,
      lineLength: _primary.lineLength,
      lineAngle: _primary.lineAngle,
      organGroup: _primary.organGroup,
      isolateOrganGroup: _primary.isolateOrganGroup,
      focusOrganOnLoad: false,
      topChrome: 108,
      bottomChrome: 168,
      onSkinReadyChange: (ready) {
        if (!mounted) return;
        setState(() => _skinReady = ready);
      },
      onDefaultLayersReadyChange: (_) {},
      onLayersApplied: (layers) {
        if (layers.contains(anatomy.wire)) _showSavedModel();
      },
      onPick: (_) {},
    );
  }

  Widget _titleBar() {
    return Row(
      children: [
        _ChromeButton(label: '返回', onTap: () => Navigator.of(context).pop()),
        Expanded(
          child: Text(
            _primary.region.label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 64),
      ],
    );
  }
}

class _SavedParameters extends StatelessWidget {
  const _SavedParameters({required this.labels});

  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: (dark ? AppColors.darkSurface : Colors.white).withValues(
          alpha: 0.92,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: dark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Text(
          labels.join(' · '),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _RecordInfo extends StatelessWidget {
  const _RecordInfo({required this.dark, required this.locations});

  final bool dark;
  final List<PainLocation> locations;

  @override
  Widget build(BuildContext context) {
    final muted = dark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: (dark ? AppColors.darkSurface : Colors.white).withValues(
          alpha: 0.94,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: dark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final location in locations)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${location.partName} · ${location.shape.label} · ${_depthLabel(location)}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            Text(
              _feeling(locations),
              style: TextStyle(fontSize: 12, height: 1.4, color: muted),
            ),
          ],
        ),
      ),
    );
  }

  String _feeling(List<PainLocation> locations) {
    final primary = locations.isEmpty ? null : locations.last;
    if (primary == null) return '未记录程度';
    final sensations = primary.sensations.isEmpty
        ? '未记录感觉'
        : primary.sensations.join('、');
    return '程度 ${primary.intensity0to10}/10 · $sensations';
  }

  String _depthLabel(PainLocation location) {
    return switch (location.depthState) {
      'surface' => '表面',
      'known' when location.depthMeters != null =>
        '皮下约 ${(location.depthMeters! * 100).toStringAsFixed(1)} cm',
      'internal_unknown' => location.layer.label,
      _ => '说不清楚',
    };
  }
}

class _ChromeButton extends StatelessWidget {
  const _ChromeButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ZtPressableScale(
      onTap: onTap,
      tapScale: 0.92,
      child: Material(
        color: (dark ? AppColors.darkSurface : Colors.white).withValues(
          alpha: 0.92,
        ),
        elevation: 2,
        shadowColor: Colors.black26,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
        ),
      ),
    );
  }
}
