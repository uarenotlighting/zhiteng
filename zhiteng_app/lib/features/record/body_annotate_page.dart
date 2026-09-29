import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../core/haptics.dart';
import '../../core/models/pain_models.dart';
import '../../core/system_confirm_dialog.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/zt_motion.dart';
import 'pain_spot_draft.dart';
import 'record_selection.dart';
import 'widgets/body_3d_webview.dart';
import 'widgets/control_throttle.dart';
import 'widgets/marker_controls.dart';
import 'widgets/schematic_body_locator.dart';

/// Full-screen body workbench. Returns one [PainSpotDraft] when the user
/// finishes this spot, or null if they leave it behind.
class BodyAnnotatePage extends StatefulWidget {
  const BodyAnnotatePage({super.key, this.initial});

  final PainSpotDraft? initial;

  @override
  State<BodyAnnotatePage> createState() => _BodyAnnotatePageState();
}

class _BodyAnnotatePageState extends State<BodyAnnotatePage> {
  final _body3dKey = GlobalKey<Body3dWebViewState>();
  final _body2dKey = GlobalKey<SchematicBodyLocatorState>();
  final _stageKey = GlobalKey();
  final _bandTopKey = GlobalKey();
  final _dockKey = GlobalKey();
  final _spanBarKey = GlobalKey();
  final _leftScaleKey = GlobalKey();
  final _rightScaleKey = GlobalKey();
  final _layerKey = GlobalKey();
  final _zoomKey = GlobalKey();
  String _placementShieldSignature = '';
  late final _controlRebuild = ControlThrottle<void>(
    onValue: (_) {
      if (mounted) setState(() {});
    },
  );
  bool _finishing = false;
  bool _clearingMark = false;
  int _modeRequest = 0;

  static const double _zoomStep = 1.12;

  late RecordRegionSelection _regions;
  late RecordShapeSelection _shapes;
  late bool _use3d;
  late double _markerScale;
  late double _lineLength;
  late double _lineAngle;
  late String _body2dAnchorView;
  late Offset _body2dAnchorPoint;
  late String _body2dLineAnchorView;
  late double _body2dLineAnchorAngle;
  final Map<String, Offset> _body2dViewPoints = {};
  final Map<String, double> _body2dViewLineAngles = {};
  late double _zoom2d;
  late BodyLayer _layer;
  late String _depthState;
  late double _x;
  late double _y;
  late String _view;
  late String _partName;
  late String _bodyPartId;
  late String _side;
  late String _activeSpotId;
  late bool _hasPickedLocation;
  late RecordMarkSelection _marks;
  late RecordMarkSelection _openedMarks;

  double? _localX;
  double? _localY;
  double? _localZ;
  double? _depthMeters;
  String? _meshId;
  String? _surfaceRegionId;
  String? _surfaceRegionSourceName;
  String? _anatomicalStructureId;
  String? _anatomicalSourceName;
  Set<BodyLayer> _visibleLayers = {...defaultVisibleBodyLayers};
  String _organGroup = 'all';
  bool _isolateOrganGroup = false;
  bool _skinReady = false;
  bool _default3dLayersReady = false;
  bool _modelRestored = false;
  bool _allowPop = false;
  bool _locateOpen = false;
  bool _toolsOpen = false;
  bool _cameraAdjusted = false;
  double _frameZoom = 1;
  double? _frameFocusX;
  double? _frameFocusY;
  String? _validation;
  double _topChrome = bodyStageTopChrome;
  double _bottomChrome = bodyStageBottomChrome;

  BodyRegion get _region => _regions.active(use3d: _use3d);
  PainShape get _shape => _shapes.active(use3d: _use3d);
  bool get _editing => widget.initial != null;
  bool get _isSurface3d => (_depthMeters ?? 0) <= 0.004;

  String get _depthLabel {
    if (_use3d && _localX != null) {
      if (_isSurface3d) return '表面';
      final cm = (_depthMeters! * 100).toStringAsFixed(1);
      final where = _layer == BodyLayer.muscle ? '' : ' · ${_layer.label}';
      return '皮下约 $cm cm$where';
    }
    return switch (_depthState) {
      'surface' => '表面',
      'internal_unknown' => _layer.label,
      _ => '说不清楚',
    };
  }

  @override
  void initState() {
    super.initState();
    final spot = widget.initial;
    _regions = const RecordRegionSelection();
    _shapes = const RecordShapeSelection();
    _use3d = spot?.use3d ?? defaultRecordUses3d;
    _markerScale = spot?.markerScale ?? painMarkerMinScale;
    _lineLength = spot?.lineLength ?? 1;
    _lineAngle = spot?.lineAngle ?? 0;
    _layer = spot?.layer ?? BodyLayer.skin;
    _depthState = spot?.depthState ?? 'surface';
    _x = spot?.x ?? 0.5;
    _y = spot?.y ?? regionDefaultY(BodyRegion.full);
    _view = spot?.view ?? 'front';
    _partName = spot?.partName ?? '身体';
    _bodyPartId = spot?.bodyPartId ?? 'body';
    _side = spot?.side ?? 'unknown';
    _activeSpotId = spot?.id ?? const Uuid().v4();
    _hasPickedLocation = spot != null;
    _resetBody2dProjection();
    _localX = spot?.localX;
    _localY = spot?.localY;
    _localZ = spot?.localZ;
    _depthMeters = spot?.depthMeters;
    _meshId = spot?.meshId;
    _surfaceRegionId = spot?.surfaceRegionId;
    _surfaceRegionSourceName = spot?.surfaceRegionSourceName;
    _anatomicalStructureId = spot?.anatomicalStructureId;
    _anatomicalSourceName = spot?.anatomicalSourceName;
    if (spot != null) {
      _regions = _regions.select(spot.region, use3d: _use3d);
      _shapes = _shapes.select(spot.shape, use3d: _use3d);
      _organGroup = spot.organGroup;
      _isolateOrganGroup = spot.isolateOrganGroup;
      _frameZoom = spot.frameZoom;
      _frameFocusX = spot.frameFocusX;
      _frameFocusY = spot.frameFocusY;
      final shown = _anatomyToShow(spot);
      if (shown != null) _visibleLayers = visibleLayersFor(shown);
    }
    _zoom2d = body2dRegionZoom(_region) * _frameZoom;
    _marks = const RecordMarkSelection();
    _storeActive();
    _openedMarks = _marks;
  }

  @override
  void dispose() {
    _controlRebuild.dispose();
    super.dispose();
  }

  // Keep the intended value synchronously; only expensive widget/scene work
  // is throttled. A final tap is never discarded by a leading-only debounce.
  void _adjustControl(VoidCallback change) {
    change();
    _controlRebuild.add(null);
  }

  Future<void> _flushAdjustments() async {
    _controlRebuild.flush();
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    if (_use3d) {
      await _body3dKey.currentState?.flushControls();
    } else {
      await _body2dKey.currentState?.flushControls();
    }
  }

  /// The anatomy chip to reopen. Prefer the one the user had open; the ray
  /// classification is only a fallback for spots saved before that was stored.
  BodyLayer? _anatomyToShow(PainSpotDraft spot) {
    final shown = spot.shownAnatomy;
    if (shown != null && selectableAnatomyLayers.contains(shown)) return shown;
    if (!spot.use3d && spot.layer == BodyLayer.skin) return null;
    final classified = spot.layer == BodyLayer.unknown
        ? BodyLayer.muscle
        : spot.layer;
    if (selectableAnatomyLayers.contains(classified)) return classified;
    return spot.use3d ? BodyLayer.muscle : null;
  }

  BodyLayer get _shownAnatomy {
    for (final layer in selectableAnatomyLayers) {
      if (_visibleLayers.contains(layer)) return layer;
    }
    return BodyLayer.muscle;
  }

  void _applyShownAnatomy(BodyLayer? anatomy) {
    if (anatomy == null || !selectableAnatomyLayers.contains(anatomy)) return;
    _visibleLayers = visibleLayersFor(anatomy);
  }

  RecordBodyMark _snapshot() {
    return RecordBodyMark(
      picked: _hasPickedLocation,
      x: _x,
      y: _y,
      view: _view,
      partName: _partName,
      bodyPartId: _bodyPartId,
      side: _side,
      layer: _layer,
      depthState: _depthState,
      localX: _localX,
      localY: _localY,
      localZ: _localZ,
      depthMeters: _depthMeters,
      meshId: _meshId,
      surfaceRegionId: _surfaceRegionId,
      surfaceRegionSourceName: _surfaceRegionSourceName,
      anatomicalStructureId: _anatomicalStructureId,
      anatomicalSourceName: _anatomicalSourceName,
      organGroup: _organGroup,
      isolateOrganGroup: _isolateOrganGroup,
      shownAnatomy: _use3d ? _shownAnatomy : null,
    );
  }

  void _storeActive() {
    _marks = _marks.write(_snapshot(), use3d: _use3d);
  }

  void _loadActive() {
    final mark = _marks.active(use3d: _use3d);
    _hasPickedLocation = mark.picked;
    _x = mark.x;
    _y = mark.y;
    _view = mark.view;
    _partName = mark.partName;
    _bodyPartId = mark.bodyPartId;
    _side = mark.side;
    _layer = mark.layer;
    _depthState = mark.depthState;
    _localX = mark.localX;
    _localY = mark.localY;
    _localZ = mark.localZ;
    _depthMeters = mark.depthMeters;
    _meshId = mark.meshId;
    _surfaceRegionId = mark.surfaceRegionId;
    _surfaceRegionSourceName = mark.surfaceRegionSourceName;
    _anatomicalStructureId = mark.anatomicalStructureId;
    _anatomicalSourceName = mark.anatomicalSourceName;
    _organGroup = mark.organGroup;
    _isolateOrganGroup = mark.isolateOrganGroup;
    if (_use3d) _applyShownAnatomy(mark.shownAnatomy ?? _layer);
  }

  void _resetBody2dProjection() {
    _body2dAnchorView = _view;
    _body2dAnchorPoint = Offset(_x, _y);
    _body2dLineAnchorView = _view;
    _body2dLineAnchorAngle = _lineAngle;
    _body2dViewPoints
      ..clear()
      ..[_view] = _body2dAnchorPoint;
    _body2dViewLineAngles
      ..clear()
      ..[_view] = _body2dLineAnchorAngle;
  }

  ({Offset point, double lineAngle}) _body2dProjectionFor(String view) {
    final point =
        _body2dViewPoints[view] ??
        remapBodyImagePoint(
          from: _body2dAnchorView,
          to: view,
          x: _body2dAnchorPoint.dx,
          y: _body2dAnchorPoint.dy,
        );
    final angle =
        _body2dViewLineAngles[view] ??
        remapBodyLineAngle(
          from: _body2dLineAnchorView,
          to: view,
          angle: _body2dLineAnchorAngle,
        );
    return (point: point, lineAngle: angle);
  }

  void _applyBody2dPick(Body2dPick pick) {
    final point = Offset(pick.normalizedX, pick.normalizedY);
    if (pick.reanchorsView) {
      // A deliberate edit establishes a new body-space anchor. Previously
      // projected views no longer describe this point and must be discarded.
      _body2dAnchorView = _view;
      _body2dAnchorPoint = point;
      _body2dViewPoints
        ..clear()
        ..[_view] = point;
    } else {
      // Mask snapping refines only the view being shown. In particular, a
      // profile edge must never replace the original face-view anchor.
      _body2dViewPoints[_view] = point;
      if (_view == _body2dAnchorView) _body2dAnchorPoint = point;
    }
    _applyNormalized(
      pick.normalizedX,
      pick.normalizedY,
      bodyPartId: pick.bodyPartId,
      partName: pick.partName,
    );
  }

  void _setLineAngle(double value) {
    _lineAngle = value;
    if (_use3d) return;
    _body2dLineAnchorView = _view;
    _body2dLineAnchorAngle = value;
    _body2dViewLineAngles
      ..clear()
      ..[_view] = value;
  }

  bool _markDirty(RecordBodyMark current, RecordBodyMark opened) {
    if (!current.picked && !opened.picked) return false;
    return current != opened;
  }

  PainSpotDraft _capture() {
    final precise3d =
        _use3d && _localX != null && _localY != null && _localZ != null;
    return PainSpotDraft(
      id: _activeSpotId,
      x: _x,
      y: _y,
      view: _view,
      layer: _layer,
      shape: _shape,
      region: _region,
      partName: _partName,
      bodyPartId: _bodyPartId,
      markerScale: _markerScale,
      lineLength: _lineLength,
      lineAngle: _lineAngle,
      depthState: precise3d
          ? (_isSurface3d ? 'surface' : 'known')
          : _depthState,
      use3d: precise3d,
      side: _side,
      localX: precise3d ? _localX : null,
      localY: precise3d ? _localY : null,
      localZ: precise3d ? _localZ : null,
      depthMeters: precise3d ? _depthMeters : null,
      meshId: precise3d ? _meshId : null,
      surfaceRegionId: precise3d ? _surfaceRegionId : null,
      surfaceRegionSourceName: precise3d ? _surfaceRegionSourceName : null,
      anatomicalStructureId: precise3d ? _anatomicalStructureId : null,
      anatomicalSourceName: precise3d ? _anatomicalSourceName : null,
      organGroup: _organGroup,
      isolateOrganGroup: _isolateOrganGroup,
      shownAnatomy: precise3d ? _shownAnatomy : null,
      frameZoom: _frameZoom,
      frameFocusX: _frameFocusX,
      frameFocusY: _frameFocusY,
    );
  }

  /// Remember the camera that was actually on screen, not only the region chip.
  Future<void> _rememberFrame() async {
    if (_use3d) {
      final camera = await _body3dKey.currentState?.readCameraFrame();
      if (camera == null) return;
      final focus = projectBodyPointToImage(
        x: camera.x,
        y: camera.y,
        z: camera.z,
        view: _view,
      );
      _frameZoom = camera.zoom;
      _frameFocusX = focus.x;
      _frameFocusY = focus.y;
      return;
    }
    final regionZoom = body2dRegionZoom(_region);
    final relative = regionZoom == 0 ? 1.0 : _zoom2d / regionZoom;
    final zoomed = (relative - 1).abs() > 0.02;
    _frameZoom = relative;
    _frameFocusX = zoomed ? _x : null;
    _frameFocusY = zoomed ? _y : null;
  }

  bool get _dirty {
    final inactive = _use3d ? _marks.twoDimensional : _marks.threeDimensional;
    final openedInactive = _use3d
        ? _openedMarks.twoDimensional
        : _openedMarks.threeDimensional;
    final openedActive = _openedMarks.active(use3d: _use3d);
    return _cameraAdjusted ||
        _markDirty(_snapshot(), openedActive) ||
        _markDirty(inactive, openedInactive);
  }

  void _leave() {
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _nudgeMarker({double dx = 0, double dy = 0, double dz = 0}) {
    if (!_use3d) {
      _body2dKey.currentState?.nudgeMeters(dx, dy);
      return Future.value();
    }
    return _body3dKey.currentState?.nudgeMarker(dx: dx, dy: dy, dz: dz) ??
        Future.value();
  }

  void _zoomBy(double factor) {
    _cameraAdjusted = true;
    if (_use3d) {
      _body3dKey.currentState?.zoom(factor);
      return;
    }
    setState(
      () => _zoom2d = (_zoom2d * factor).clamp(body2dMinZoom, body2dMaxZoom),
    );
  }

  void _resetZoom() {
    if (_use3d) {
      _body3dKey.currentState?.resetView();
      return;
    }
    setState(() => _zoom2d = body2dRegionZoom(_region));
  }

  Future<void> _clearMark() async {
    _clearingMark = true;
    setState(() {
      _hasPickedLocation = false;
      _localX = null;
      _localY = null;
      _localZ = null;
      _depthMeters = null;
      _meshId = null;
      _surfaceRegionId = null;
      _surfaceRegionSourceName = null;
      _anatomicalStructureId = null;
      _anatomicalSourceName = null;
      _partName = '身体';
      _bodyPartId = 'body';
      _validation = null;
    });
    await _body3dKey.currentState?.clearMarker();
    _clearingMark = false;
  }

  /// Put a saved 3D spot back only after the anatomy chip that was open
  /// (muscle, bone, or organ) has loaded. Waiting on the ray classification
  /// instead skips bone: the chip can be bone while the point is still
  /// reported as muscle, and that layer is never applied.
  void _restoreSavedModel(List<String> layers) {
    if (_modelRestored || !_use3d || !mounted) return;
    if (!layers.contains(_shownAnatomy.wire)) return;
    _modelRestored = true;
    _showActiveOnModel();
  }

  void _showActiveOnModel() {
    _body3dKey.currentState?.setView(_view);
    if (!_hasPickedLocation ||
        _localX == null ||
        _localY == null ||
        _localZ == null) {
      _body3dKey.currentState?.clearMarker();
      return;
    }
    _body3dKey.currentState?.restoreMarker(
      x: _localX!,
      y: _localY!,
      z: _localZ!,
      depth: _depthMeters,
    );
    _body3dKey.currentState?.setShape(_shape);
    _body3dKey.currentState?.setMarkerScale(_markerScale);
    _body3dKey.currentState?.setLineLength(_lineLength);
    _body3dKey.currentState?.setLineAngle(_lineAngle);
    if ((_frameZoom - 1).abs() > 0.02) {
      _body3dKey.currentState?.zoom(_frameZoom);
    }
  }

  void _applyNormalized(
    double x,
    double y, {
    String? view,
    String? bodyPartId,
    String? partName,
  }) {
    setState(() {
      _x = x;
      _y = y;
      if (view != null) _view = view;
      final guessed = guessPartName(x: _x, y: _y, region: _region, view: _view);
      final isNeutralSurface = bodyPartId?.startsWith('neutral_') ?? false;
      _partName = partName ?? guessed;
      _bodyPartId = isNeutralSurface
          ? 'approx_${_view}_${(_x * 1000).round()}_${(_y * 1000).round()}'
          : (bodyPartId ?? _partName);
      _side = _inferSide();
      _hasPickedLocation = true;
      _validation = null;
    });
  }

  String _inferSide() {
    if (_view == 'left') return 'left';
    if (_view == 'right') return 'right';
    if ((_x - 0.5).abs() < 0.04) return 'center';
    final imageRightIsBodyLeft = _view != 'back';
    final onImageRight = _x > 0.5;
    return imageRightIsBodyLeft == onImageRight ? 'left' : 'right';
  }

  Future<void> _setUse3d(bool value) async {
    final request = ++_modeRequest;
    if (value == _use3d) return;
    try {
      await _flushAdjustments();
    } catch (_) {
      if (mounted) setState(() => _validation = '调整尚未完成，请稍后再切换');
      return;
    }
    if (!mounted || request != _modeRequest) return;
    setState(() {
      _storeActive();
      _use3d = value;
      _loadActive();
      if (!value) {
        _resetBody2dProjection();
        _zoom2d = body2dRegionZoom(_region);
      }
    });
    if (value) {
      _showActiveOnModel();
    } else {
      _body3dKey.currentState?.clearMarker();
    }
  }

  Future<void> _cancel() async {
    if (!_dirty) {
      _leave();
      return;
    }
    final editing = _editing;
    final leave = await _confirmDiscard(editing);
    if (leave == true && mounted) _leave();
  }

  Future<bool?> _confirmDiscard(bool editing) {
    final title = editing ? '放弃这次修改？' : '放弃这个痛点？';
    final message = editing ? '痛点还在，只是这次改动不会保存。' : '已经标好的位置会丢掉。';
    final stay = editing ? '继续编辑' : '继续标注';
    final discard = editing ? '返回' : '放弃';
    return showSystemConfirm(
      title: title,
      message: message,
      stay: stay,
      discard: discard,
    );
  }

  void _measureClearBand() {
    final stageBox = _stageKey.currentContext?.findRenderObject() as RenderBox?;
    final topBox = _bandTopKey.currentContext?.findRenderObject() as RenderBox?;
    final dockBox = _dockKey.currentContext?.findRenderObject() as RenderBox?;
    if (stageBox == null ||
        topBox == null ||
        dockBox == null ||
        !stageBox.hasSize ||
        !topBox.hasSize ||
        !dockBox.hasSize) {
      return;
    }
    final stageTop = stageBox.localToGlobal(Offset.zero).dy;
    final stageBottom = stageTop + stageBox.size.height;
    final bandTop = topBox.localToGlobal(Offset.zero).dy + topBox.size.height;
    // Side sliders sit in the corners. Only full-width bars (the dock card,
    // and the line-direction slider) take space away from the body.
    var bandBottom = dockBox.localToGlobal(Offset.zero).dy;
    final spanBox =
        _spanBarKey.currentContext?.findRenderObject() as RenderBox?;
    if (spanBox != null && spanBox.hasSize) {
      final spanTop = spanBox.localToGlobal(Offset.zero).dy;
      if (spanTop < bandBottom) bandBottom = spanTop;
    }
    final top = (bandTop - stageTop + 8).clamp(0.0, stageBox.size.height);
    final bottom = (stageBottom - bandBottom + 8).clamp(
      0.0,
      stageBox.size.height,
    );
    _syncPlacementShields(stageBox);
    if ((top - _topChrome).abs() < 1 && (bottom - _bottomChrome).abs() < 1) {
      return;
    }
    setState(() {
      _topChrome = top;
      _bottomChrome = bottom;
    });
  }

  /// The 3D page is a platform WebView under these controls. A tap on the
  /// depth pad or another tool can also land on the canvas and move the pain
  /// point to whatever is behind that control. Report each control's bounds
  /// so the page ignores those taps.
  void _syncPlacementShields(RenderBox stage) {
    if (!_use3d) return;
    final rects = <Rect>[];
    for (final key in [
      _dockKey,
      _leftScaleKey,
      _rightScaleKey,
      _spanBarKey,
      _layerKey,
      _zoomKey,
    ]) {
      final box = key.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached || !box.hasSize) continue;
      if (box.size.width < 8 || box.size.height < 8) continue;
      final topLeft = stage.globalToLocal(box.localToGlobal(Offset.zero));
      rects.add((topLeft & box.size).inflate(6));
    }
    final signature = rects
        .map(
          (rect) =>
              '${rect.left.round()},${rect.top.round()},${rect.width.round()},${rect.height.round()}',
        )
        .join(';');
    if (signature == _placementShieldSignature) return;
    _placementShieldSignature = signature;
    _body3dKey.currentState?.setPlacementShields(rects);
  }

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    try {
      await _flushAdjustments();
      await _rememberFrame();
    } catch (_) {
      if (mounted) setState(() => _validation = '调整尚未完成，请稍后再保存');
      _finishing = false;
      return;
    }
    if (!mounted) return;
    if (!_hasPickedLocation) {
      setState(() => _validation = '请先在人体上标记这个痛点');
      _finishing = false;
      return;
    }
    final spot = _capture();
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(spot);
    });
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final stageReady = !_use3d || _skinReady;
    final topInset = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureClearBand());
    return PopScope(
      canPop: _allowPop || !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
            .copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: Colors.transparent,
            ),
        child: Scaffold(
          backgroundColor: AppColors.bodyStageFor(dark: dark),
          extendBody: true,
          extendBodyBehindAppBar: true,
          body: Stack(
            key: _stageKey,
            children: [
              Positioned.fill(child: _stage()),
              if (stageReady) ...[
                Positioned(
                  key: _bandTopKey,
                  top: topInset + 52,
                  left: 10,
                  right: 10,
                  child: _viewControls(),
                ),
                _EdgeLabel(
                  text: bodyEdgeLabels(_view).$1,
                  alignment: Alignment.centerLeft,
                ),
                _EdgeLabel(
                  text: bodyEdgeLabels(_view).$2,
                  alignment: Alignment.centerRight,
                ),
                Positioned(
                  left: 10,
                  right: 10,
                  top: topInset + 108,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      KeyedSubtree(key: _layerKey, child: _layerChooser()),
                      const Spacer(),
                      KeyedSubtree(
                        key: _zoomKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            StageZoomControl(
                              onZoomIn: () => _zoomBy(_zoomStep),
                              onZoomOut: () => _zoomBy(1 / _zoomStep),
                              onReset: _resetZoom,
                            ),
                            if (_hasPickedLocation) ...[
                              const SizedBox(height: 8),
                              _ResetMarkButton(onTap: _clearMark),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              Positioned(
                left: 10,
                right: 10,
                bottom: bottomInset + 10,
                child: _bottomTools(dark),
              ),
              Positioned(
                top: topInset + 6,
                left: 12,
                right: 12,
                child: _titleBar(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stage() {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
        Positioned.fill(
          child: Body3dWebView(
            key: _body3dKey,
            region: _regions.threeDimensional,
            layers: _visibleLayers,
            active: _use3d,
            onSkinReadyChange: (ready) {
              if (!mounted) return;
              setState(() => _skinReady = ready);
              if (ready) {
                _body3dKey.currentState?.setStageChrome(
                  _topChrome,
                  _bottomChrome,
                );
              }
            },
            onLayersApplied: _restoreSavedModel,
            onDefaultLayersReadyChange: (ready) {
              if (mounted) setState(() => _default3dLayersReady = ready);
            },
            onViewChange: (view) {
              if (!_use3d) return;
              if (view != _view) setState(() => _view = view);
            },
            shape: _shapes.threeDimensional,
            markerScale: _markerScale,
            lineLength: _lineLength,
            lineAngle: _lineAngle,
            organGroup: _organGroup,
            isolateOrganGroup: _isolateOrganGroup,
            focusOrganOnLoad: widget.initial?.has3d != true,
            topChrome: _topChrome,
            bottomChrome: _bottomChrome,
            onPick: (pick) {
              if (!_use3d || _clearingMark) return;
              // The restore report repeats a skin-ray guess. Applying it
              // replaces the recorded organ, position, and depth.
              if (pick.source == 'restore') return;
              final fromLayers = pick.source == 'layers';
              setState(() {
                if (!fromLayers) {
                  _localX = pick.localX;
                  _localY = pick.localY;
                  _localZ = pick.localZ;
                  _depthMeters = pick.depthMeters;
                  _meshId = pick.meshId;
                  _surfaceRegionId = pick.surfaceRegionId;
                  _surfaceRegionSourceName = pick.surfaceRegionSourceName;
                  _anatomicalStructureId = pick.anatomicalStructureId;
                  _anatomicalSourceName = pick.anatomicalSourceName;
                }
                final reported = pick.layer;
                if (reported != null &&
                    (!fromLayers || _visibleLayers.contains(reported))) {
                  _layer = reported;
                }
              });
              if (pick.source == 'tap') {
                ztHaptic(context, ZtHaptic.selection);
              }
              if (!fromLayers &&
                  pick.source != 'flush' &&
                  !pick.keepsSurfaceSpot) {
                _applyNormalized(
                  pick.normalizedX,
                  pick.normalizedY,
                  view: pick.view,
                  bodyPartId: pick.bodyPartId ?? pick.meshId,
                  partName: pick.approximatePartName,
                );
              }
            },
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            ignoring: _use3d,
            child: Opacity(
              opacity: _use3d ? 0 : 1,
              child: SchematicBodyLocator(
                key: _body2dKey,
                x: _x,
                y: _y,
                view: _view,
                region: _regions.twoDimensional,
                layer: _layer,
                shape: _shapes.twoDimensional,
                markerScale: _markerScale,
                lineLength: _lineLength,
                lineAngle: _lineAngle,
                zoom: _zoom2d,
                showCrosshair: _hasPickedLocation,
                topChrome: _topChrome,
                bottomChrome: _bottomChrome,
                retargetOnViewChange: !_use3d,
                onChanged: (pick) {
                  if (_use3d) return;
                  _applyBody2dPick(pick);
                },
              ),
            ),
          ),
        ),
        if (_use3d && !_skinReady)
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(bottom: 150),
              child: Text(
                '加载 3D 人体表面…',
                style: TextStyle(
                  color: dark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        if (_use3d && _skinReady && !_default3dLayersReady)
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(bottom: 150),
              child: Text(
                '正在后台准备肌肉与骨骼…',
                style: TextStyle(
                  color: dark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                  fontSize: 12,
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _selectRegion(BodyRegion region) {
    _adjustControl(() {
      _regions = _regions.select(region, use3d: _use3d);
      _locateOpen = false;
      if (!_use3d) _zoom2d = body2dRegionZoom(region);
    });
  }

  Widget _titleBar() {
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        Row(
          children: [
            _OverlayButton(label: '取消', onTap: _cancel),
            const Spacer(),
            _OverlayButton(
              label: _editing ? '保存修改' : '完成本痛点',
              onTap: _finish,
              haptic: ZtHaptic.medium,
            ),
          ],
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _LocateButton(
              label: _region.label,
              open: _locateOpen,
              onTap: () => setState(() => _locateOpen = !_locateOpen),
            ),
            if (_locateOpen) ...[
              const SizedBox(height: 6),
              _LocateMenu(selected: _region, onSelected: _selectRegion),
            ],
          ],
        ),
      ],
    );
  }

  Widget _viewControls() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        BodyViewSegment(
          value: _view,
          onChanged: (view) {
            if (_use3d) {
              _adjustControl(() => _view = view);
              _body3dKey.currentState?.setView(view);
            } else {
              _adjustControl(() {
                if (_hasPickedLocation) {
                  _body2dViewPoints[_view] = Offset(_x, _y);
                  _body2dViewLineAngles[_view] = _lineAngle;
                  final projected = _body2dProjectionFor(view);
                  _x = projected.point.dx;
                  _y = projected.point.dy;
                  _lineAngle = projected.lineAngle;
                  _body2dViewPoints[view] = projected.point;
                  _body2dViewLineAngles[view] = projected.lineAngle;
                }
                _view = view;
                _side = _inferSide();
              });
            }
          },
        ),
        const Spacer(),
        _ModeSwitch(use3d: _use3d, onChanged: _setUse3d),
      ],
    );
  }

  Widget _bottomTools(bool dark) {
    final line = _shape == PainShape.line;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            KeyedSubtree(
              key: _leftScaleKey,
              child: line
                  ? _SideScale(
                      label: '长短',
                      value: _lineLength,
                      min: painLineMinLength,
                      max: painLineMaxLength,
                      onChanged: (value) =>
                          _adjustControl(() => _lineLength = value),
                    )
                  : const SizedBox(width: 44),
            ),
            Expanded(
              child: line
                  ? Padding(
                      key: _spanBarKey,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: _LineDirection(
                        angle: _lineAngle,
                        onChanged: (value) =>
                            _adjustControl(() => _setLineAngle(value)),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            KeyedSubtree(
              key: _rightScaleKey,
              child: _SideScale(
                label: line ? '粗细' : '大小',
                value: _markerScale,
                min: painMarkerMinScale,
                max: painMarkerMaxScale,
                onChanged: (value) =>
                    _adjustControl(() => _markerScale = value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        _dock(dark),
      ],
    );
  }

  Widget _dock(bool dark) {
    final place = _hasPickedLocation ? '$_partName · $_depthLabel' : '未标记';
    return _FloatCard(
      key: _dockKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ZtPressableScale(
            onTap: () => _adjustControl(() => _toolsOpen = !_toolsOpen),
            tapScale: 0.99,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '位置  $place',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: dark
                          ? AppColors.darkTextPrimary
                          : AppColors.lightTextPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '疼痛模式  ${_shape.label}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: dark
                        ? AppColors.darkTextPrimary
                        : AppColors.lightTextPrimary,
                  ),
                ),
                Icon(
                  _toolsOpen ? Icons.expand_more : Icons.expand_less,
                  size: 20,
                ),
              ],
            ),
          ),
          if (_validation != null) ...[
            const SizedBox(height: 4),
            Text(
              _validation!,
              style: const TextStyle(color: AppColors.painMarker, fontSize: 12),
            ),
          ],
          if (_toolsOpen) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                for (final shape in PainShape.values)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: _ShapeCard(
                        shape: shape,
                        selected: _shape == shape,
                        onTap: () => _adjustControl(
                          () => _shapes = _shapes.select(shape, use3d: _use3d),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            MarkerJoystick(
              enabled: stageReady && _hasPickedLocation,
              depthCaption: place,
              onPlane: (dx, dy) => _nudgeMarker(dx: dx, dy: dy),
              onDepth: _use3d ? (dz) => _nudgeMarker(dz: dz) : null,
              hint: _use3d ? null : '按住可连续移动。',
            ),
          ],
        ],
      ),
    );
  }

  bool get stageReady => !_use3d || _skinReady;

  Widget _layerChooser() {
    if (_use3d) {
      final organOpen = _visibleLayers.contains(BodyLayer.organ);
      return LayoutBuilder(
        builder: (context, constraints) {
          final room = constraints.maxHeight.isFinite
              ? constraints.maxHeight - _bottomChrome - 8
              : 320.0;
          return _PillSegment(
            maxHeight: organOpen ? room.clamp(160, 420) : null,
            options: [
              for (final layer in selectableAnatomyLayers)
                (
                  layer.label,
                  _visibleLayers.contains(layer),
                  () => _adjustControl(
                    () => _visibleLayers = visibleLayersFor(layer),
                  ),
                ),
              if (organOpen) ...[
                for (final option in organGroupOptions)
                  (
                    option.label,
                    _organGroup == option.id,
                    () => _adjustControl(() {
                      _organGroup = option.id;
                      if (option.id == 'all') _isolateOrganGroup = false;
                    }),
                  ),
                if (_organGroup != 'all')
                  (
                    '仅看所选',
                    _isolateOrganGroup,
                    () => _adjustControl(
                      () => _isolateOrganGroup = !_isolateOrganGroup,
                    ),
                  ),
              ],
            ],
          );
        },
      );
    }
    return _PillSegment(
      options: [
        for (final option in const [
          (BodyLayer.skin, 'surface', '皮肤'),
          (BodyLayer.muscle, 'internal_unknown', '肌肉'),
          (BodyLayer.bone, 'internal_unknown', '骨骼'),
          (BodyLayer.unknown, 'unknown', '说不清楚'),
        ])
          (
            option.$3,
            _layer == option.$1 && _depthState == option.$2,
            () => _adjustControl(() {
              _layer = option.$1;
              _depthState = option.$2;
            }),
          ),
      ],
    );
  }
}

class _OverlayButton extends StatelessWidget {
  const _OverlayButton({
    required this.label,
    required this.onTap,
    this.haptic = ZtHaptic.light,
  });

  final String label;
  final VoidCallback onTap;
  final ZtHaptic haptic;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ZtPressableScale(
      onTap: onTap,
      haptic: haptic,
      tapScale: 0.92,
      child: Material(
        color: dark
            ? AppColors.darkSurface.withValues(alpha: 0.92)
            : Colors.white.withValues(alpha: 0.92),
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

class _LocateButton extends StatelessWidget {
  const _LocateButton({
    required this.label,
    required this.open,
    required this.onTap,
  });

  final String label;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ZtPressableScale(
      onTap: onTap,
      tapScale: 0.92,
      child: Material(
        color: dark
            ? AppColors.darkSurface.withValues(alpha: 0.92)
            : Colors.white.withValues(alpha: 0.92),
        elevation: 2,
        shadowColor: Colors.black26,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              Icon(open ? Icons.expand_less : Icons.expand_more, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocateMenu extends StatelessWidget {
  const _LocateMenu({required this.selected, required this.onSelected});

  final BodyRegion selected;
  final ValueChanged<BodyRegion> onSelected;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: dark
          ? AppColors.darkSurface.withValues(alpha: 0.96)
          : Colors.white.withValues(alpha: 0.96),
      elevation: 4,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 112,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final region in const [
              BodyRegion.full,
              BodyRegion.head,
              BodyRegion.upper,
              BodyRegion.lower,
            ])
              ZtPressableScale(
                onTap: () => onSelected(region),
                haptic: ZtHaptic.selection,
                tapScale: 0.94,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  alignment: Alignment.center,
                  child: Text(
                    region.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: region == selected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: region == selected
                          ? (dark
                                ? AppColors.darkTextPrimary
                                : AppColors.lightTextPrimary)
                          : (dark
                                ? AppColors.darkTextSecondary
                                : AppColors.lightTextSecondary),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.use3d, required this.onChanged});

  final bool use3d;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return _FloatCard(
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModeOption(
            label: '2D',
            selected: !use3d,
            onTap: () => onChanged(false),
          ),
          _ModeOption(
            label: '3D',
            selected: use3d,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ZtPressableScale(
      onTap: onTap,
      haptic: ZtHaptic.selection,
      tapScale: 0.92,
      child: Material(
        color: selected
            ? (dark ? AppColors.darkElevated : AppColors.lightSubtle)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _FloatCard extends StatelessWidget {
  const _FloatCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: dark
          ? AppColors.darkSurface.withValues(alpha: 0.94)
          : Colors.white.withValues(alpha: 0.94),
      elevation: 2,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: padding ?? const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: child,
      ),
    );
  }
}

class _EdgeLabel extends StatelessWidget {
  const _EdgeLabel({required this.text, required this.alignment});

  final String text;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: alignment,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            text,
            style: TextStyle(
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppColors.darkTextSecondary
                  : AppColors.lightTextSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _ShapeCard extends StatelessWidget {
  const _ShapeCard({
    required this.shape,
    required this.selected,
    required this.onTap,
  });

  final PainShape shape;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ZtPressableScale(
      onTap: onTap,
      haptic: ZtHaptic.selection,
      tapScale: 0.92,
      child: Material(
        color: selected
            ? (dark ? AppColors.darkPrimarySoft : AppColors.lightPrimarySoft)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? (dark ? AppColors.darkPrimary : AppColors.lightPrimary)
                  : (dark ? AppColors.darkBorder : AppColors.lightBorder),
            ),
          ),
          child: Column(
            children: [
              Icon(
                switch (shape) {
                  PainShape.point => Icons.circle,
                  PainShape.area => Icons.circle_outlined,
                  PainShape.line => Icons.horizontal_rule,
                  PainShape.radiate => Icons.blur_on,
                },
                size: 16,
                color: AppColors.painMarker,
              ),
              const SizedBox(height: 2),
              Text(
                shape.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PillSegment extends StatelessWidget {
  const _PillSegment({required this.options, this.maxHeight});

  final List<(String, bool, VoidCallback)> options;
  final double? maxHeight;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final items = IntrinsicWidth(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final option in options)
            ZtPressableScale(
              onTap: option.$3,
              haptic: ZtHaptic.selection,
              tapScale: 0.94,
              child: Material(
                color: option.$2
                    ? (dark ? AppColors.darkElevated : AppColors.lightSubtle)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(11),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  child: Text(
                    option.$1,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: option.$2 ? FontWeight.w700 : FontWeight.w500,
                      color: option.$2
                          ? (dark
                                ? AppColors.darkTextPrimary
                                : AppColors.lightTextPrimary)
                          : (dark
                                ? AppColors.darkTextSecondary
                                : AppColors.lightTextSecondary),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(3),
      constraints: maxHeight == null
          ? null
          : BoxConstraints(maxHeight: maxHeight!),
      decoration: BoxDecoration(
        color: dark
            ? AppColors.darkSurface.withValues(alpha: 0.92)
            : Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: dark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.3 : 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: maxHeight == null ? items : SingleChildScrollView(child: items),
    );
  }
}

class _ResetMarkButton extends StatelessWidget {
  const _ResetMarkButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      button: true,
      label: '重置标记',
      child: ZtPressableScale(
        onTap: onTap,
        tapScale: 0.9,
        child: Material(
          color: dark
              ? AppColors.darkSurface.withValues(alpha: 0.92)
              : Colors.white.withValues(alpha: 0.92),
          elevation: 2,
          shadowColor: Colors.black26,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(
              Icons.restart_alt,
              size: 18,
              color: dark
                  ? AppColors.darkTextSecondary
                  : AppColors.lightTextSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _LineDirection extends StatelessWidget {
  const _LineDirection({required this.angle, required this.onChanged});

  final double angle;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Text(
          '方向 · ${lineDirectionLabel(angle)}',
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 28,
          height: 28,
          child: Center(
            child: Transform.rotate(
              angle: -angle,
              child: Container(
                width: 3,
                height: 22,
                decoration: BoxDecoration(
                  color: AppColors.painMarker.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: AppColors.painMarker,
              thumbColor: AppColors.painMarker,
              overlayColor: Colors.transparent,
              inactiveTrackColor: dark
                  ? AppColors.darkBorder
                  : AppColors.lightBorder,
            ),
            child: Slider(
              value: angle.clamp(-math.pi, math.pi),
              min: -math.pi,
              max: math.pi,
              divisions: 24,
              semanticFormatterCallback: (value) => lineDirectionLabel(value),
              onChangeStart: (_) => ztHaptic(context, ZtHaptic.selection),
              onChanged: onChanged,
              onChangeEnd: (_) => ztHaptic(context, ZtHaptic.selection),
            ),
          ),
        ),
      ],
    );
  }
}

/// Full-length outline under the scale track. The slider is painted on top,
/// so the unfilled line stays visible on both the dark stage and the pale body.
class _StageScaleTrackShape extends RoundedRectSliderTrackShape {
  const _StageScaleTrackShape({required this.halo});

  final Color halo;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    final height = sliderTheme.trackHeight;
    if (height != null && height > 0) {
      final trackRect = getPreferredRect(
        parentBox: parentBox,
        offset: offset,
        sliderTheme: sliderTheme,
        isEnabled: isEnabled,
        isDiscrete: isDiscrete,
      );
      final haloRect = trackRect.inflate(1.5 + additionalActiveTrackHeight / 2);
      context.canvas.drawRRect(
        RRect.fromRectAndRadius(
          haloRect,
          Radius.circular(haloRect.shortestSide / 2),
        ),
        Paint()..color = halo,
      );
    }
    super.paint(
      context,
      offset,
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      enableAnimation: enableAnimation,
      textDirection: textDirection,
      thumbCenter: thumbCenter,
      secondaryOffset: secondaryOffset,
      isDiscrete: isDiscrete,
      isEnabled: isEnabled,
      additionalActiveTrackHeight: additionalActiveTrackHeight,
    );
  }
}

class _SideScale extends StatelessWidget {
  const _SideScale({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: 40,
      height: 148,
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
          Expanded(
            child: RotatedBox(
              quarterTurns: 3,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  activeTrackColor: AppColors.painMarker,
                  thumbColor: AppColors.painMarker,
                  overlayColor: Colors.transparent,
                  inactiveTrackColor: AppColors.stageScaleTrack(dark: dark),
                  trackShape: _StageScaleTrackShape(
                    halo: AppColors.stageScaleTrackHalo(dark: dark),
                  ),
                ),
                child: Slider(
                  value: value.clamp(min, max),
                  min: min,
                  max: max,
                  onChangeStart: (_) => ztHaptic(context, ZtHaptic.selection),
                  onChanged: onChanged,
                  onChangeEnd: (_) => ztHaptic(context, ZtHaptic.selection),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
