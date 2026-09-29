import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/models/pain_models.dart';
import '../../../core/theme/app_colors.dart';
import 'schematic_body_locator.dart';

class BodyPickResult {
  const BodyPickResult({
    required this.normalizedX,
    required this.normalizedY,
    required this.view,
    this.localX,
    this.localY,
    this.localZ,
    this.meshId,
    this.bodyPartId,
    this.layer,
    this.depthMeters,
    this.source,
    this.bodyHeightFraction,
    this.bodyLateralFraction,
    this.surfaceRegionId,
    this.surfaceRegionSourceName,
    this.anatomicalStructureId,
    this.anatomicalSourceName,
  });

  final double normalizedX;
  final double normalizedY;
  final String view;
  final double? localX;
  final double? localY;
  final double? localZ;
  final String? meshId;
  final String? bodyPartId;

  /// Layer the marker sits in: the deepest visible layer whose surface it has
  /// passed along the placement ray (skin when it is on the surface).
  final BodyLayer? layer;

  /// Depth along the original placement ray. Orbiting does not change it.
  final double? depthMeters;

  /// 'tap' | 'nudge' | 'depth' | 'layers'. Depth keeps the surface spot fixed.
  final String? source;

  /// Surface entry relative to the body, independent of crop/zoom/orbit.
  final double? bodyHeightFraction;
  final double? bodyLateralFraction;

  /// Exact Z-Anatomy surface region hit by the invisible region proxy.
  final String? surfaceRegionId;
  final String? surfaceRegionSourceName;

  /// Original Z-Anatomy / BodyParts3D object beneath the selected skin point,
  /// or the exact internal object when the marker has been moved into one.
  final String? anatomicalStructureId;
  final String? anatomicalSourceName;

  String? get approximatePartName {
    if (bodyHeightFraction == null || bodyLateralFraction == null) return null;
    return guessPartNameOnBody(
      heightFromFeet: bodyHeightFraction!,
      lateralFromCenter: bodyLateralFraction!,
      view: view,
      anatomicalSourceName: surfaceRegionSourceName ?? anatomicalSourceName,
    );
  }

  bool get isSurface => (depthMeters ?? 0) <= 0.004;

  bool get keepsSurfaceSpot => source == 'depth';
}

/// Canonical camera views, anatomical sides ("left" shows the body's left).
const List<(String, String)> bodyViewOptions = [
  ('front', '正面'),
  ('left', '左侧'),
  ('right', '右侧'),
  ('back', '背面'),
];

/// The skin is always visible. Exactly one anatomical layer is shown beneath
/// it so the three combinations remain easy to understand.
const List<BodyLayer> selectableAnatomyLayers = [
  BodyLayer.muscle,
  BodyLayer.bone,
  BodyLayer.organ,
];

const Set<BodyLayer> defaultVisibleBodyLayers = {
  BodyLayer.skin,
  BodyLayer.muscle,
};

Set<BodyLayer> visibleLayersFor(BodyLayer anatomyLayer) {
  if (!selectableAnatomyLayers.contains(anatomyLayer)) {
    throw ArgumentError.value(
      anatomyLayer,
      'anatomyLayer',
      'must be muscle, bone, or organ',
    );
  }
  return {BodyLayer.skin, anatomyLayer};
}

/// Three.js + GLB viewer inspired by 疼痛坐标 / miniProgram locate package.
///
/// Layers are stacked: the translucent skin is always drawn and the selected
/// anatomical layers are visible underneath it.
class Body3dWebView extends StatefulWidget {
  const Body3dWebView({
    super.key,
    required this.region,
    required this.layers,
    required this.onPick,
    required this.onSkinReadyChange,
    required this.onDefaultLayersReadyChange,
    this.onLayersApplied,
    this.active = true,
    this.onViewChange,
    this.showCrosshair = true,
    this.shape = PainShape.point,
    this.markerScale = painMarkerMinScale,
    this.lineLength = 1,
    this.lineAngle = 0,
    this.organGroup = 'all',
    this.isolateOrganGroup = false,
    this.focusOrganOnLoad = true,
    this.topChrome = bodyStageTopChrome,
    this.bottomChrome = bodyStageBottomChrome,
  });

  final BodyRegion region;
  final Set<BodyLayer> layers;
  final ValueChanged<BodyPickResult> onPick;

  /// True only after the skin has actually been drawn by WebGL once.
  final ValueChanged<bool> onSkinReadyChange;

  /// Tracks the separate background milestone: skin, muscle and bone parsed.
  final ValueChanged<bool> onDefaultLayersReadyChange;

  /// Fires after a layer set has finished loading. The list is the layers now
  /// showing, so a saved organ spot can wait until `organ` is actually in it.
  final ValueChanged<List<String>>? onLayersApplied;

  /// Whether the 3D stage is currently exposed to the user. The WebView stays
  /// mounted and loads while false, but skips continuous rendering work.
  final bool active;

  /// Pain shape drawn at the marker (point / patch / line / radiating).
  final PainShape shape;

  /// Indicator size as a multiple of the default marker radius.
  /// For a line this is the stroke thickness.
  final double markerScale;

  /// Line arc length as a multiple of [painLineBaseLengthMeters].
  final double lineLength;

  /// Radians around the outward skin normal. 0 runs along the body.
  final double lineAngle;

  /// Stable group ID from [organGroupOptions]. The group is only sent after
  /// the organ layer is selected, preserving on-demand organ loading.
  final String organGroup;
  final bool isolateOrganGroup;

  /// False while reopening a saved spot, so framing the organ group does not
  /// pull the camera off the recorded point.
  final bool focusOrganOnLoad;

  /// Fired when the camera settles nearest to another canonical view
  /// ('front' | 'left' | 'right' | 'back'), including after user rotation.
  final ValueChanged<String>? onViewChange;

  /// CAD-style hairlines + reticle through the marker, drawn by the WebView.
  final bool showCrosshair;

  /// Pixels kept clear above and below the body so it matches the 2D frame.
  final double topChrome;
  final double bottomChrome;

  @override
  State<Body3dWebView> createState() => Body3dWebViewState();
}

class Body3dWebViewState extends State<Body3dWebView> {
  late final WebViewController _controller;
  final _BodyAssetServer _assets = _BodyAssetServer();
  bool _ready = false;
  bool _pageReady = false;
  bool? _stageDark;
  bool _defaultLayersReady = false;
  String? _error;
  final Set<String> _loadedLayers = {};
  // Bound native evaluateJavaScript traffic. A slow WebView gets one batch
  // at a time and each absolute control keeps only its newest requested value.
  final Map<String, String> _pendingControls = {};
  Timer? _controlTimer;
  Completer<void>? _pendingCompletion;
  Future<void>? _sendingControls;
  final Map<int, Completer<void>> _flushAcks = {};
  int _flushSequence = 0;
  double _pendingDx = 0, _pendingDy = 0, _pendingDz = 0;
  double _pendingZoom = 1;
  String? _requestedView;

  bool _viewerStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (!_viewerStarted) {
      _viewerStarted = true;
      _stageDark = dark;
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(AppColors.bodyStageFor(dark: dark))
        ..addJavaScriptChannel('ZhitengChannel', onMessageReceived: _onMessage)
        ..setNavigationDelegate(
          NavigationDelegate(onPageFinished: (_) => _preparePage()),
        );
      unawaited(_openViewer());
      return;
    }
    if (_stageDark == dark) return;
    _stageDark = dark;
    unawaited(_applyStageBackground(dark));
  }

  @override
  void dispose() {
    _controlTimer?.cancel();
    _pendingControls.clear();
    _pendingCompletion?.complete();
    for (final ack in _flushAcks.values) {
      if (!ack.isCompleted) ack.complete();
    }
    _flushAcks.clear();
    unawaited(_assets.close());
    super.dispose();
  }

  /// Serves the viewer and GLBs over loopback so the page can fetch local
  /// file URLs. WKWebView's asset loader only grants read access to the HTML
  /// directory, and injecting Base64 would copy every layer into one script.
  Future<void> _openViewer() async {
    try {
      final page = await _assets.start();
      if (!mounted) return;
      final stage = AppColors.bodyStageFor(dark: _stageDark ?? false);
      final hex = (stage.toARGB32() & 0xFFFFFF)
          .toRadixString(16)
          .padLeft(6, '0');
      await _controller.loadRequest(
        page.replace(queryParameters: {'stage': hex}),
      );
    } catch (error) {
      debugPrint('3D local asset server failed: $error');
      if (!mounted) return;
      setState(() => _error = '本地人体模型资源加载失败');
      widget.onSkinReadyChange(false);
      widget.onDefaultLayersReadyChange(false);
    }
  }

  Future<void> _preparePage() async {
    try {
      if (mounted) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        _stageDark = dark;
        _pageReady = true;
        await _applyStageBackground(dark);
      }
      final manifest =
          jsonDecode(await rootBundle.loadString(bodyModelManifestPath))
              as Map<String, dynamic>;
      final version = manifest['bodyModelVersion']?.toString();
      if (version != null) {
        await _controller.runJavaScript(
          'window.ZHITENG_MODEL_VERSION = ${jsonEncode(version)};'
          'if (window.ZhitengBridge) window.ZhitengBridge.setModelVersion(window.ZHITENG_MODEL_VERSION);',
        );
      }
      // body3d.html starts reading only skin from its local relative URL. Do
      // not ask for any other payload until its first rendered-frame event.
      await setRegion(widget.region);
      await setStageChrome(widget.topChrome, widget.bottomChrome);
      await setCrosshair(widget.showCrosshair);
      await setShape(widget.shape);
      await setMarkerScale(widget.markerScale);
      await setLineLength(widget.lineLength);
      await setLineAngle(widget.lineAngle);
      await setActive(widget.active);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '本地人体模型资源加载失败');
      widget.onSkinReadyChange(false);
      widget.onDefaultLayersReadyChange(false);
    }
  }

  Future<void> _warmBackgroundModels() async {
    await Future.wait(
      bodyModelBackgroundLayers.map((layer) async {
        try {
          await _callBridge(
            'window.ZhitengBridge && '
            'window.ZhitengBridge.preloadLayer(${jsonEncode(layer)})',
          );
        } catch (error) {
          debugPrint('Optional 3D body layer preload failed: $layer $error');
        }
      }),
    );
  }

  @override
  void didUpdateWidget(covariant Body3dWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.region != widget.region && _ready) {
      setRegion(widget.region);
    }
    if (oldWidget.topChrome != widget.topChrome ||
        oldWidget.bottomChrome != widget.bottomChrome) {
      setStageChrome(widget.topChrome, widget.bottomChrome);
    }
    if (!setEquals(oldWidget.layers, widget.layers) && _ready) {
      setLayers(widget.layers);
    }
    if (oldWidget.showCrosshair != widget.showCrosshair) {
      setCrosshair(widget.showCrosshair);
    }
    if (oldWidget.shape != widget.shape) setShape(widget.shape);
    if (oldWidget.markerScale != widget.markerScale) {
      setMarkerScale(widget.markerScale);
    }
    if (oldWidget.lineLength != widget.lineLength) {
      setLineLength(widget.lineLength);
    }
    if (oldWidget.lineAngle != widget.lineAngle) {
      setLineAngle(widget.lineAngle);
    }
    if (oldWidget.active != widget.active) setActive(widget.active);
    if ((oldWidget.organGroup != widget.organGroup ||
            oldWidget.isolateOrganGroup != widget.isolateOrganGroup) &&
        widget.layers.contains(BodyLayer.organ)) {
      setOrganGroup(widget.organGroup, isolate: widget.isolateOrganGroup);
    }
  }

  void _onMessage(JavaScriptMessage message) {
    if (!mounted) return;
    try {
      final data = jsonDecode(message.message) as Map<String, dynamic>;
      final type = data['type'] as String?;
      final payload = data['payload'] as Map<String, dynamic>? ?? {};
      if (type == 'controlsApplied') {
        _flushAcks.remove(payload['id'])?.complete();
      } else if (type == 'layerLoaded') {
        final layer = payload['layer'] as String?;
        if (layer == null) return;
        _loadedLayers.add(layer);
        debugPrint('3D local layer loaded: $layer');
        final complete = _loadedLayers.containsAll(bodyModelDefaultLayers);
        if (complete != _defaultLayersReady) {
          _defaultLayersReady = complete;
          widget.onDefaultLayersReadyChange(complete);
        }
      } else if (type == 'skinFirstFrame') {
        if (_ready) return;
        setState(() {
          _ready = true;
          _error = null;
        });
        widget.onSkinReadyChange(true);
        setRegion(widget.region);
        unawaited(
          setLayers(widget.layers, focusOrgan: widget.focusOrganOnLoad),
        );
        unawaited(_warmBackgroundModels());
      } else if (type == 'layersApplied') {
        final layers = (payload['layers'] as List<dynamic>? ?? const [])
            .map((layer) => layer.toString())
            .toList(growable: false);
        widget.onLayersApplied?.call(layers);
      } else if (type == 'error') {
        if (payload['source'] == 'bridge') {
          debugPrint('3D control failed: ${payload['message']}');
          return;
        }
        final layer = payload['layer'] as String?;
        if (layer != null && layer != 'skin') {
          debugPrint(
            'Optional 3D body layer failed: $layer ${payload['message']}',
          );
          return;
        }
        setState(() {
          _error = payload['message']?.toString() ?? '加载失败';
        });
        widget.onSkinReadyChange(false);
      } else if (type == 'pick') {
        widget.onPick(
          BodyPickResult(
            normalizedX: (payload['normalizedX'] as num?)?.toDouble() ?? 0.5,
            normalizedY: (payload['normalizedY'] as num?)?.toDouble() ?? 0.35,
            view: payload['view'] as String? ?? 'front',
            localX: (payload['localX'] as num?)?.toDouble(),
            localY: (payload['localY'] as num?)?.toDouble(),
            localZ: (payload['localZ'] as num?)?.toDouble(),
            meshId: payload['meshId'] as String?,
            bodyPartId: payload['bodyPartId'] as String?,
            layer: _layerFromWire(payload['layer'] as String?),
            depthMeters: (payload['depth'] as num?)?.toDouble(),
            source: payload['source'] as String?,
            bodyHeightFraction: (payload['bodyHeightFraction'] as num?)
                ?.toDouble(),
            bodyLateralFraction: (payload['bodyLateralFraction'] as num?)
                ?.toDouble(),
            surfaceRegionId: payload['surfaceRegionId'] as String?,
            surfaceRegionSourceName:
                payload['surfaceRegionSourceName'] as String?,
            anatomicalStructureId: payload['anatomicalStructureId'] as String?,
            anatomicalSourceName: payload['anatomicalSourceName'] as String?,
          ),
        );
      } else if (type == 'view') {
        final view = payload['view'] as String?;
        if (_requestedView != null && view != _requestedView) return;
        _requestedView = null;
        if (view != null) widget.onViewChange?.call(view);
      }
    } catch (_) {
      // Ignore malformed bridge payloads.
    }
  }

  Future<void> _queueControl(String key, String expression) {
    if (!mounted) return Future.value();
    _pendingControls.remove(key);
    _pendingControls[key] = expression;
    final completion = _pendingCompletion ??= Completer<void>();
    _scheduleControls();
    return completion.future;
  }

  void _scheduleControls() {
    if (_controlTimer != null || _sendingControls != null || !mounted) return;
    _controlTimer = Timer(const Duration(milliseconds: 64), () {
      _controlTimer = null;
      unawaited(_sendControls());
    });
  }

  Future<void> _sendControls() async {
    if (_sendingControls != null) return _sendingControls;
    _controlTimer?.cancel();
    _controlTimer = null;
    if (_pendingControls.isEmpty || !mounted) return;
    final commands = Map<String, String>.of(_pendingControls);
    _pendingControls.clear();
    final completion = _pendingCompletion!;
    _pendingCompletion = null;
    if (commands.containsKey('nudge')) {
      commands['nudge'] =
          'window.ZhitengBridge.nudge('
          '$_pendingDx, $_pendingDy, $_pendingDz)';
      _pendingDx = _pendingDy = _pendingDz = 0;
    }
    if (commands.containsKey('zoom')) {
      commands['zoom'] = 'window.ZhitengBridge.zoom($_pendingZoom)';
      _pendingZoom = 1;
    }
    final sending = _callBridge(
      '(() => { if (!window.ZhitengBridge) return; '
      '${commands.values.map((command) => 'try { const result = ($command); '
          'if (result && result.catch) result.catch(console.error); '
          '} catch (error) { console.error(error); }').join('\n')} })()',
    );
    _sendingControls = sending;
    try {
      await sending;
    } finally {
      _sendingControls = null;
      completion.complete();
      if (_pendingControls.isNotEmpty) _scheduleControls();
    }
  }

  /// A save/mode-switch barrier: apply the last queued input and receive its
  /// final pick before capturing Dart state. No fixed delay or dropped tail.
  Future<void> flushControls() async {
    while (mounted &&
        (_sendingControls != null || _pendingControls.isNotEmpty)) {
      await (_sendingControls ?? _sendControls());
    }
    if (!mounted || !_ready) return;
    final id = ++_flushSequence;
    final ack = Completer<void>();
    _flushAcks[id] = ack;
    try {
      await _callBridge(
        '(() => { '
        'window.ZhitengBridge.flushControls(); '
        'window.ZhitengChannel.postMessage(JSON.stringify('
        '{type:"controlsApplied",payload:{id:$id}})); })()',
      );
      await ack.future.timeout(const Duration(seconds: 5));
    } finally {
      _flushAcks.remove(id);
    }
  }

  Future<void> _applyStageBackground(bool dark) async {
    final color = AppColors.bodyStageFor(dark: dark);
    await _controller.setBackgroundColor(color);
    if (!_pageReady) return;
    final rgb = color.toARGB32() & 0xFFFFFF;
    final hex = '#${rgb.toRadixString(16).padLeft(6, '0')}';
    await _callBridge(
      'window.ZhitengBridge && window.ZhitengBridge.setStageBackground(${jsonEncode(hex)})',
    );
  }

  /// Runs a bridge call without ever surfacing a platform exception.
  ///
  /// WKWebView rejects `evaluateJavaScript` when the script's completion value
  /// cannot be serialised (bridge methods return Promises), when the script
  /// throws, or when the web content process is gone (hot restart, memory
  /// pressure). None of those should crash the app: the call is wrapped so it
  /// completes with `undefined`, JS-side failures are reported through the
  /// channel, and anything the platform still throws is only logged.
  Future<void> _callBridge(String expression) async {
    final script =
        '''
(function () {
  function report(error) {
    if (!window.ZhitengChannel) return;
    window.ZhitengChannel.postMessage(JSON.stringify({
      type: 'error',
      payload: { message: String((error && error.message) || error), source: 'bridge' }
    }));
  }
  try {
    var result = ($expression);
    if (result && typeof result.then === 'function') result.then(null, report);
  } catch (error) {
    report(error);
  }
})();
''';
    try {
      await _controller.runJavaScript(script);
    } on PlatformException catch (error) {
      debugPrint(
        'Body3dWebView bridge call failed: ${error.code} ${error.message} '
        '${_describeDetails(error.details)}',
      );
    }
  }

  static String _describeDetails(Object? details) {
    if (details == null) return '';
    try {
      final dynamic native = details;
      return 'NSError(domain: ${native.domain}, code: ${native.code}, '
          'userInfo: ${native.userInfo})';
    } catch (_) {
      return details.toString();
    }
  }

  Future<void> setRegion(BodyRegion region) {
    _requestedView = null;
    return _queueControl(
      'region',
      "window.ZhitengBridge && window.ZhitengBridge.setRegion('${region.wire}')",
    );
  }

  Future<void> setStageChrome(double top, double bottom) {
    return _queueControl(
      'chrome',
      'window.ZhitengBridge && window.ZhitengBridge.setStageChrome('
          '${top.toStringAsFixed(1)}, ${bottom.toStringAsFixed(1)})',
    );
  }

  /// Control rectangles in this WebView's logical pixels. A tap there must
  /// not place a marker: the platform view can receive the same pointer that
  /// the Flutter control above it already handled.
  Future<void> setPlacementShields(List<Rect> rects) {
    final payload = jsonEncode([
      for (final rect in rects)
        {'x': rect.left, 'y': rect.top, 'w': rect.width, 'h': rect.height},
    ]);
    return _queueControl(
      'shields',
      'window.ZhitengBridge && window.ZhitengBridge.setPlacementShields($payload)',
    );
  }

  Future<void> _sendLayers(Set<BodyLayer> layers) {
    final wire = jsonEncode(
      {BodyLayer.skin, ...layers}.map((layer) => layer.wire).toList(),
    );
    return _queueControl(
      'layers',
      '(window.ZHITENG_ACTIVE_LAYERS = $wire, '
          'window.ZhitengBridge && window.ZhitengBridge.setLayers(window.ZHITENG_ACTIVE_LAYERS))',
    );
  }

  Future<void> setLayers(Set<BodyLayer> layers, {bool focusOrgan = true}) {
    if (!_ready) return Future.value();
    _pendingControls.remove('organ');
    _pendingControls.remove('focus');
    final applied = _sendLayers(layers);
    // Enqueue focus with the layer intent, not from a later async continuation
    // that could run after a newer camera/view click.
    if (layers.contains(BodyLayer.organ)) {
      setOrganGroup(
        widget.organGroup,
        isolate: widget.isolateOrganGroup,
        focus: focusOrgan,
      );
    } else if (layers.contains(BodyLayer.bone) && focusOrgan) {
      focusBone();
    }
    return applied;
  }

  Future<void> focusBone() {
    _requestedView = null;
    return _queueControl(
      'focus',
      'window.ZhitengBridge && window.ZhitengBridge.focusBone()',
    );
  }

  Future<void> setOrganGroup(
    String group, {
    bool isolate = false,
    bool focus = true,
  }) {
    if (focus) _requestedView = null;
    return _queueControl(
      'organ',
      'window.ZhitengBridge && window.ZhitengBridge.setOrganGroup('
          '${jsonEncode(group)}, ${isolate ? 'true' : 'false'}, ${focus ? 'true' : 'false'})',
    );
  }

  static BodyLayer? _layerFromWire(String? value) {
    if (value == null) return null;
    for (final layer in BodyLayer.values) {
      if (layer.wire == value) return layer;
    }
    return null;
  }

  Future<void> resetView() {
    _requestedView = null;
    _pendingControls.remove('zoom');
    _pendingZoom = 1;
    return _queueControl(
      'camera',
      'window.ZhitengBridge && window.ZhitengBridge.resetView()',
    );
  }

  /// Swing the camera to a canonical view; see [bodyViewOptions].
  Future<void> setView(String view) {
    _requestedView = view;
    return _queueControl(
      'camera',
      'window.ZhitengBridge && window.ZhitengBridge.setView(${jsonEncode(view)})',
    );
  }

  Future<void> setCrosshair(bool on) {
    return _queueControl(
      'crosshair',
      'window.ZhitengBridge && window.ZhitengBridge.setCrosshair(${on ? 'true' : 'false'})',
    );
  }

  Future<void> setActive(bool active) {
    return _queueControl(
      'active',
      'window.ZhitengBridge && window.ZhitengBridge.setActive(${active ? 'true' : 'false'})',
    );
  }

  /// Joystick step for the marker, in metres: [dx]/[dy] slide it in the
  /// screen plane, [dz] pushes it deeper (positive) or back toward the skin.
  /// The WebView answers with a new `pick` message.
  Future<void> nudgeMarker({double dx = 0, double dy = 0, double dz = 0}) {
    _pendingDx += dx;
    _pendingDy += dy;
    _pendingDz += dz;
    return _queueControl('nudge', '');
  }

  Future<void> clearMarker() {
    _pendingControls.remove('nudge');
    _pendingDx = _pendingDy = _pendingDz = 0;
    return _queueControl('marker', 'window.ZhitengBridge.clearMarker()');
  }

  /// Spots already placed on this record. Each map needs localX/Y/Z, and may
  /// include markerScale and shape.
  Future<void> setPinnedMarkers(List<Map<String, Object?>> markers) {
    return _queueControl(
      'pinned',
      'window.ZhitengBridge && window.ZhitengBridge.setPinnedMarkers(${jsonEncode(markers)})',
    );
  }

  /// Put the editable marker back on a saved 3D coordinate.
  Future<void> restoreMarker({
    required double x,
    required double y,
    required double z,
    double? depth,
  }) {
    final depthArg = depth == null ? 'null' : depth.toString();
    return _queueControl(
      'marker',
      'window.ZhitengBridge && window.ZhitengBridge.restoreMarker($x, $y, $z, $depthArg)',
    );
  }

  Future<void> setShape(PainShape shape) {
    return _queueControl(
      'shape',
      'window.ZhitengBridge && window.ZhitengBridge.setShape(${jsonEncode(shape.wire)})',
    );
  }

  /// Indicator size, multiple of the default radius (clamped in the page).
  /// For a line this is thickness only.
  Future<void> setMarkerScale(double scale) {
    return _queueControl(
      'scale',
      'window.ZhitengBridge && window.ZhitengBridge.setMarkerScale($scale)',
    );
  }

  /// Line length, multiple of the 16 cm base.
  Future<void> setLineLength(double length) {
    return _queueControl(
      'length',
      'window.ZhitengBridge && window.ZhitengBridge.setLineLength($length)',
    );
  }

  /// Line direction in radians around the outward normal. The page re-drapes
  /// the stroke on the skin.
  Future<void> setLineAngle(double angle) {
    return _queueControl(
      'angle',
      'window.ZhitengBridge && window.ZhitengBridge.setLineAngle($angle)',
    );
  }

  /// False keeps orbit and the depth-view button, and ignores taps that
  /// would place a new point.
  Future<void> setPlacementEnabled(bool enabled) {
    return _queueControl(
      'placement',
      'window.ZhitengBridge && window.ZhitengBridge.setPlacementEnabled(${enabled ? 'true' : 'false'})',
    );
  }

  /// Region-relative zoom and the world point the camera is aimed at.
  /// Zoom is 1 at the 头部 / 上身 / 下身 / 全身 frame.
  Future<
    ({
      double zoom,
      double distance,
      double fitDistance,
      double x,
      double y,
      double z,
    })?
  >
  readCameraFrame() async {
    if (!_ready) return null;
    try {
      final raw = await _controller.runJavaScriptReturningResult(
        'JSON.stringify(window.ZhitengBridge && window.ZhitengBridge.cameraFrame())',
      );
      var text = raw.toString();
      if (text == 'null' || text.isEmpty) return null;
      if (text.startsWith('"')) {
        final decoded = jsonDecode(text);
        if (decoded is! String) return null;
        text = decoded;
      }
      final data = jsonDecode(text);
      if (data is! Map) return null;
      final zoom = (data['zoom'] as num?)?.toDouble();
      final distance = (data['distance'] as num?)?.toDouble();
      final fitDistance = (data['fitDistance'] as num?)?.toDouble();
      final x = (data['targetX'] as num?)?.toDouble();
      final y = (data['targetY'] as num?)?.toDouble();
      final z = (data['targetZ'] as num?)?.toDouble();
      if (zoom == null ||
          distance == null ||
          fitDistance == null ||
          x == null ||
          y == null ||
          z == null) {
        return null;
      }
      return (
        zoom: zoom,
        distance: distance,
        fitDistance: fitDistance,
        x: x,
        y: y,
        z: z,
      );
    } catch (error) {
      debugPrint('3D camera frame unavailable: $error');
      return null;
    }
  }

  /// Zoom the whole body about the orbit target; [factor] > 1 zooms in.
  Future<void> zoom(double factor) {
    _pendingZoom *= factor;
    return _queueControl('zoom', '');
  }

  @override
  Widget build(BuildContext context) {
    // A platform WebView can be composited above later Flutter siblings after
    // it has been shown once. Merely painting the opaque 2D locator on top is
    // therefore not enough: switching back to 2D can leave both bodies
    // visible. Keep the WebView alive for fast mode switching, but explicitly
    // remove its native surface from the visible/interactive composition.
    return Visibility(
      visible: widget.active,
      maintainState: true,
      maintainAnimation: true,
      maintainSize: true,
      child: Stack(
        fit: StackFit.expand,
        children: [
          WebViewWidget(controller: _controller),
          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '3D 模型暂时不可用\n可改用示意人体继续记录',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.secondary,
                    height: 1.4,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Loopback file server for the 3D viewer. The page fetches each GLB by URL;
/// nothing is Base64-encoded into JavaScript.
class _BodyAssetServer {
  HttpServer? _server;
  final Map<String, Uint8List> _cache = {};

  Future<Uri> start() async {
    final existing = _server;
    if (existing != null) {
      return Uri.parse(
        'http://127.0.0.1:${existing.port}/assets/web/body3d.html',
      );
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen(
      _handle,
      onError: (Object error) {
        debugPrint('3D asset server error: $error');
      },
    );
    return Uri.parse('http://127.0.0.1:${server.port}/assets/web/body3d.html');
  }

  Future<void> close() async {
    final server = _server;
    _server = null;
    _cache.clear();
    await server?.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    final key = _assetKey(request.uri.path);
    final response = request.response;
    if (key == null) {
      response.statusCode = HttpStatus.forbidden;
      await response.close();
      return;
    }
    try {
      final bytes = await _read(key);
      response.headers.contentType = _contentType(key);
      // The viewer code changes independently of the GLB payloads during
      // development. WKWebView can otherwise keep an older HTML/JavaScript
      // response alive across a Flutter hot restart and make a camera fix
      // appear ineffective until the whole app is reinstalled.
      if (key.endsWith('.html') || key.endsWith('.js')) {
        response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
        response.headers.set(HttpHeaders.pragmaHeader, 'no-cache');
        response.headers.set(HttpHeaders.expiresHeader, '0');
      }
      response.contentLength = bytes.length;
      response.add(bytes);
    } catch (error) {
      debugPrint('3D asset missing: $key $error');
      response.statusCode = HttpStatus.notFound;
    }
    await response.close();
  }

  String? _assetKey(String path) {
    final key = path.startsWith('/') ? path.substring(1) : path;
    if (key.contains('..')) return null;
    const allowed = ['assets/web/', 'assets/models/'];
    if (!allowed.any(key.startsWith)) return null;
    return key;
  }

  Future<Uint8List> _read(String key) async {
    final cached = _cache[key];
    if (cached != null) return cached;
    final data = await rootBundle.load(key);
    final bytes = Uint8List.fromList(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    _cache[key] = bytes;
    return bytes;
  }

  ContentType _contentType(String key) {
    if (key.endsWith('.html')) return ContentType.html;
    if (key.endsWith('.js')) return ContentType('text', 'javascript');
    if (key.endsWith('.wasm')) return ContentType('application', 'wasm');
    if (key.endsWith('.json')) return ContentType.json;
    if (key.endsWith('.glb')) return ContentType('model', 'gltf-binary');
    return ContentType.binary;
  }
}
