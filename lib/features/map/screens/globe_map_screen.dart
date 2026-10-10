import '../data/map_proximity_audio.dart';
import 'package:ccs_app/core/localization/ccs_text.dart'
    show CcsText, trText, LanguageReactiveState;
import '../data/live_location_config.dart'
    show
        regularUserCarIconAsset,
        verifiedUserCarIconAsset,
        friendUserCarIconAsset;
import '../widgets/globe_marker_images.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/map_style.dart';
import 'dart:async';
import '../widgets/navigation_arrow.dart';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:ccs_app/features/spots/models/spot_categories.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Read-only renderer. GPS, visibility rules and Firebase remain owned by CCS.
class GlobeMapScreen extends StatefulWidget {
  const GlobeMapScreen({
    super.key,
    required this.readFeatures,
    this.readMotion,
    this.onBack,
    this.onInteraction,
    this.onCameraChanged,
    this.onPick,
    this.onDismissRoute,
    this.routeDistanceLabel,
    this.showControls = true,
    required this.isSharing,
    required this.sharingBusy,
    required this.onShareChanged,
    this.isVisible = true,
    this.sharingExpiresAt,
    this.onExtendSharing,
    required this.cardBuilder,
    required this.onFilter,
    required this.onAddReport,
    required this.onLocate,
  });
  final Map<String, Object?> Function() readFeatures;
  final Map<String, Object?> Function()? readMotion;

  final VoidCallback? onBack, onInteraction;
  final VoidCallback? onDismissRoute;
  final String? routeDistanceLabel;
  final void Function(double, double, double)? onCameraChanged;
  final void Function(double latitude, double longitude)? onPick;
  final bool showControls;
  final bool isSharing, sharingBusy, isVisible;
  final DateTime? sharingExpiresAt;
  final Future<void> Function()? onExtendSharing;
  final Future<void> Function(bool) onShareChanged;
  final Widget? Function(BuildContext, String, String) cardBuilder;
  final Future<void> Function() onFilter, onAddReport, onLocate;
  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  State<GlobeMapScreen> createState() => _GlobeMapScreenState();
}

class _GlobeMapScreenState extends State<GlobeMapScreen>
    with WidgetsBindingObserver, LanguageReactiveState {
  late final WebViewController controller;
  Timer? timer, motionTimer;
  bool sendingMotion = false;
  String? previousMotion;
  bool ready = false, sending = false, active = true;
  bool followActive = false;
  String? previous;
  String? error;
  bool iconsSent = false;
  String style = 'dark';
  Future<void> showClusterPeople(List<String> ids) async {
    final frame = widget.readFeatures();
    final features = frame['features'] as List? ?? const [];
    final people = features.whereType<Map>().where((feature) {
      final p = feature['properties'];
      return p is Map && p['kind'] == 'live' && ids.contains(p['id']);
    }).toList();
    if (people.isEmpty || !mounted) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .6,
          ),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: people.length,
            itemBuilder: (context, index) {
              final p = people[index]['properties'] as Map;
              return ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text('${p['label'] ?? p['id']}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(context, p['id'] as String),
              );
            },
          ),
        ),
      ),
    );
    if (!mounted || selected == null) return;
    setState(() {
      selectedKind = 'live';
      selectedId = selected;
    });
  }

  String? selectedKind, selectedId;
  Object? selectionToken;
  final _proximityAudio = MapProximityAudio();
  List<Map<String, Object?>> cameras = [];

  final _avatarImages = <String, Map<String, String>>{};
  final _avatarLoading = <String>{};
  final _avatarFailed = <String>{};
  int _avatarSequence = 0;

  // Resolve profile images natively so no new WebView network permissions are needed.
  Future<void> loadBeaconAvatar(String url) async {
    _avatarLoading.add(url);
    ImageStream? stream;
    ImageStreamListener? listener;
    ImageInfo? info;
    ui.Image? output;
    ui.Picture? picture;
    try {
      final completer = Completer<ImageInfo>();
      stream = ResizeImage(
        NetworkImage(url),
        width: 128,
        height: 128,
      ).resolve(ImageConfiguration.empty);
      listener = ImageStreamListener(
        (image, _) {
          if (!completer.isCompleted) {
            completer.complete(image);
          } else {
            image.dispose();
          }
        },
        onError: (Object error, StackTrace? stack) {
          if (!completer.isCompleted) completer.completeError(error, stack);
        },
      );
      stream.addListener(listener);
      info = await completer.future.timeout(const Duration(seconds: 8));
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final image = info.image;
      final side = image.width < image.height
          ? image.width.toDouble()
          : image.height.toDouble();
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(
          (image.width - side) / 2,
          (image.height - side) / 2,
          side,
          side,
        ),
        const Rect.fromLTWH(0, 0, 128, 128),
        Paint(),
      );
      picture = recorder.endRecording();
      output = await picture.toImage(128, 128);
      final bytes = await output.toByteData(format: ui.ImageByteFormat.png);
      if (!mounted || bytes == null) return;
      final id = 'ccs-avatar-${_avatarSequence++}';
      final png =
          'data:image/png;base64,${base64Encode(bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes))}';
      _avatarImages[url] = {'id': id, 'png': png};
      if (ready) {
        await controller.runJavaScript(
          'window.ccsSetIcons(JSON.parse(${jsonEncode(jsonEncode({id: png}))}));',
        );
      }
      unawaited(refresh());
    } catch (_) {
      _avatarFailed.add(
        url,
      ); // Keep the person silhouette if an image is unavailable.
    } finally {
      if (stream != null && listener != null) stream.removeListener(listener);
      info?.dispose();
      output?.dispose();
      picture?.dispose();
      _avatarLoading.remove(url);
    }
  }

  List<Object?> withBeaconAvatars(List features) => features.map<Object?>((
    feature,
  ) {
    if (feature is! Map ||
        feature['properties'] is! Map ||
        feature['properties']['kind'] != 'live')
      return feature;
    final properties = Map<String, Object?>.from(feature['properties'] as Map);
    final url = properties.remove('avatarUrl')?.toString() ?? '';
    final avatar = _avatarImages[url];
    properties['avatarIcon'] = avatar?['id'] ?? 'ccs-person';
    final uri = Uri.tryParse(url);
    if (avatar == null &&
        uri?.scheme == 'https' &&
        uri!.host.isNotEmpty &&
        !_avatarLoading.contains(url) &&
        !_avatarFailed.contains(url) &&
        _avatarLoading.length < 4 &&
        _avatarImages.length < 64) {
      unawaited(loadBeaconAvatar(url));
    }
    return {...feature, 'properties': properties};
  }).toList();

  Future<void> loadCameras() async {
    try {
      final data =
          jsonDecode(
                await rootBundle.loadString(
                  'assets/globe/speed_cameras_lv.json',
                ),
              )
              as Map;
      if (!mounted) return;
      cameras = (data['cameras'] as List)
          .map(
            (entry) => <String, Object?>{
              'type': 'Feature',
              'geometry': {
                'type': 'Point',
                'coordinates': [entry['lon'], entry['lat']],
              },
              'properties': {
                'kind': 'camera',
                'id': entry['id'],
                'icon': 'ccs-speed-camera',
                'color': '#ffbf47',
                'label': '',
              },
            },
          )
          .toList();
      await refresh();
    } catch (error) {
      debugPrint('Camera snapshot could not be loaded: $error');
    }
  }

  Future<void> showFilters() => widget.onFilter();

  Widget cameraCard() => Material(
    color: const Color(0xff101820),
    borderRadius: BorderRadius.circular(18),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.camera_alt, color: Color(0xffffbf47)),
              const SizedBox(width: 10),
              Expanded(
                child: CcsText(
                  'Fixed speed camera',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => setState(() {
                  selectedId = null;
                  selectedKind = null;
                }),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ],
          ),
          CcsText(
            'Mapped camera location. Coverage may be incomplete or outdated.',
            style: const TextStyle(color: Colors.white70),
          ),
          TextButton(
            onPressed: () => launchUrl(
              Uri.parse('https://www.openstreetmap.org/copyright'),
              mode: LaunchMode.externalApplication,
            ),
            child: const Text('© OpenStreetMap contributors · ODbL'),
          ),
        ],
      ),
    ),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(loadCameras());
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xff0b1323))
      ..addJavaScriptChannel(
        'CcsGlobe',
        onMessageReceived: (message) {
          if (!mounted) return;
          try {
            final data = jsonDecode(message.message);
            if (data is! Map) return;
            if (data['type'] == 'camera' &&
                data['lat'] is num &&
                data['lng'] is num &&
                data['zoom'] is num) {
              final lat = (data['lat'] as num).toDouble(),
                  lng = (data['lng'] as num).toDouble(),
                  zoom = (data['zoom'] as num).toDouble();
              if (lat.isFinite &&
                  lng.isFinite &&
                  zoom.isFinite &&
                  lat.abs() <= 90 &&
                  lng.abs() <= 180)
                widget.onCameraChanged?.call(lat, lng, zoom);
            } else if (data['type'] == 'follow') {
              setState(() => followActive = data['enabled'] == true);
            } else if (data['type'] == 'gesture') {
              setState(() => followActive = false);
              widget.onInteraction?.call();
            } else if (data['type'] == 'pick' &&
                data['lat'] is num &&
                data['lng'] is num) {
              final lat = (data['lat'] as num).toDouble(),
                  lng = (data['lng'] as num).toDouble();
              if (lat.isFinite &&
                  lng.isFinite &&
                  lat.abs() <= 90 &&
                  lng.abs() <= 180)
                widget.onPick?.call(lat, lng);
            } else if (data['type'] == 'error') {
              setState(
                () => error =
                    'Could not load the map. Check your connection and retry.',
              );
            } else if (data['type'] == 'ready') {
              ready = true;
              unawaited(syncAnimationVisibility());
              error = null;
              unawaited(applySavedStyle());
              previousMotion = null;
              previous = null;
              unawaited(refresh());
            } else if (data['type'] == 'dismissRoute') {
              widget.onDismissRoute?.call();
              setState(() {
                selectedKind = null;
                selectedId = null;
              });
              unawaited(refresh());
            } else if (data['type'] == 'clear') {
              setState(() {
                selectedKind = null;
                selectedId = null;
              });
            } else if (data['type'] == 'selectPeople') {
              if (data['ids'] is List) {
                unawaited(showClusterPeople(List<String>.from(data['ids'])));
              }
            } else if (data['type'] == 'select') {
              final kind = data['kind'], id = data['id'];
              if (const [
                    'spot',
                    'live',
                    'police',
                    'sos',
                    'camera',
                  ].contains(kind) &&
                  id is String) {
                setState(() {
                  selectedKind = kind;
                  selectedId = id;
                });
              }
            }
          } catch (_) {
            /* Ignore malformed/untrusted bridge messages. */
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri?.scheme == 'file' || request.url == 'about:blank') {
              return NavigationDecision.navigate;
            }
            // Attribution links open externally; never load them into the bridge.
            if (uri?.scheme == 'https' &&
                const {
                  'openfreemap.org',
                  'www.openstreetmap.org',
                  'openstreetmap.org',
                  'www.openmaptiles.org',
                  'openmaptiles.org',
                  'maplibre.org',
                }.contains(uri?.host)) {
              unawaited(launchUrl(uri!, mode: LaunchMode.externalApplication));
            }
            return NavigationDecision.prevent;
          },
          onWebResourceError: (failure) {
            if (failure.isForMainFrame == true && mounted) {
              setState(
                () => error =
                    'Could not load the map. Check your connection and retry.',
              );
            }
          },
        ),
      );
    unawaited(
      controller.loadFlutterAsset('assets/globe/index.html').catchError((
        Object _,
      ) {
        if (mounted) {
          setState(() => error = 'The map is unavailable on this device.');
        }
      }),
    );
    motionTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => unawaited(refreshMotion()),
    );
    timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(refresh()),
    );
  }

  Future<void> refreshMotion() async {
    if (!mounted ||
        !ready ||
        !active ||
        !widget.isVisible ||
        sendingMotion ||
        widget.readMotion == null)
      return;
    sendingMotion = true;
    try {
      final data = jsonEncode(widget.readMotion!());
      if (data != previousMotion) {
        await controller.runJavaScript(
          'window.ccsSetMotion(JSON.parse(${jsonEncode(data)}));',
        );
        previousMotion = data;
      }
    } catch (_) {
      previousMotion = null;
    } finally {
      sendingMotion = false;
    }
  }

  String? previousFixedFeatures, previousMovingFeatures;

  Future<void> refresh() async {
    if (!mounted || !ready || !active || !widget.isVisible || sending) return;
    sending = true;
    try {
      if (!iconsSent) {
        final icons = await globeMarkerImages();
        for (final asset in {
          regularUserCarIconAsset,
          verifiedUserCarIconAsset,
          friendUserCarIconAsset,
          ...spotCategoryIconAssets.values,
          ...spotCategoryLightIconAssets.values,
        }) {
          final bytes = await rootBundle.load(asset);
          // Original artwork is large; transfer only a marker-sized copy once.
          final codec = await ui.instantiateImageCodec(
            bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
            targetWidth: 128,
            allowUpscaling: false,
          );
          try {
            final frame = await codec.getNextFrame();
            try {
              final png = await frame.image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              if (png != null) {
                icons[asset] =
                    'data:image/png;base64,${base64Encode(png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes))}';
              }
            } finally {
              frame.image.dispose();
            }
          } finally {
            codec.dispose();
          }
        }
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder)..scale(2);
        const NavigationArrowPainter(0).paint(canvas, const Size(62, 62));
        final picture = recorder.endRecording();
        final arrow = await picture.toImage(124, 124);
        final arrowBytes = await arrow.toByteData(
          format: ui.ImageByteFormat.png,
        );
        if (arrowBytes != null) {
          icons['ccs-self-arrow'] =
              'data:image/png;base64,${base64Encode(arrowBytes.buffer.asUint8List())}';
        }
        arrow.dispose();
        picture.dispose();
        if (!mounted) return;
        await controller.runJavaScript(
          'window.ccsSetIcons(JSON.parse(${jsonEncode(jsonEncode(icons))}));',
        );
        for (final avatar in _avatarImages.values) {
          await controller.runJavaScript(
            'window.ccsSetIcons(JSON.parse(${jsonEncode(jsonEncode({avatar['id']!: avatar['png']!}))}));',
          );
        }
        iconsSent = true;
      }
      final frame = Map<String, Object?>.from(widget.readFeatures());
      if (widget.showControls && frame['routePreview'] != true) {
        frame['features'] = [...(frame['features'] as List), ...cameras];
      }
      frame['features'] = withBeaconAvatars(frame['features'] as List);
      if (widget.showControls) {
        unawaited(
          _proximityAudio.update(
            frame['features'] as List,
            widget.readMotion?.call(),
          ),
        );
      }
      final selection = frame['selection'];
      if (selection is Map && selection['token'] != selectionToken) {
        selectionToken = selection['token'];
        selectedKind = selection['id'] == null ? null : 'spot';
        selectedId = selection['id'] as String?;
      }
      final data = jsonEncode(frame);
      if (data != previous) {
        // Encode as a JS string, then parse: names cannot become executable code.
        final features = frame['features'] as List;
        bool moving(dynamic feature) => const [
          'live',
          'self',
          'route',
        ].contains(feature['properties']['kind']);
        final fixed = features.where((f) => !moving(f)).toList();
        final mobile = features.where(moving).toList();
        final fixedJson = jsonEncode(fixed), movingJson = jsonEncode(mobile);
        final full = previous == null;
        final patch = {
          'meta': {...frame}..remove('features'),
          if (full || fixedJson != previousFixedFeatures) 'fixed': fixed,
          if (full || movingJson != previousMovingFeatures) 'moving': mobile,
        };
        await controller.runJavaScript(
          'window.ccsSetPatch(JSON.parse(${jsonEncode(jsonEncode(patch))}));',
        );
        previousFixedFeatures = fixedJson;
        previousMovingFeatures = movingJson;
        previous = data;
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Map updates paused. Retry to reconnect.');
      }
    } finally {
      sending = false;
      if (mounted) setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    active = state == AppLifecycleState.resumed;
    previousMotion = null;
    unawaited(syncAnimationVisibility());
    if (active) unawaited(refresh());
  }

  Future<void> syncAnimationVisibility() async {
    if (!active || !widget.isVisible) unawaited(_proximityAudio.stop());
    if (!ready) return;
    try {
      await controller.runJavaScript(
        'window.ccsSetActive(${active && widget.isVisible});',
      );
    } catch (_) {
      /* The platform view may already be closing. */
    }
  }

  @override
  void didUpdateWidget(covariant GlobeMapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isVisible != widget.isVisible) {
      previousMotion = null;
      unawaited(syncAnimationVisibility());
      if (widget.isVisible) unawaited(refresh());
    }
  }

  @override
  void dispose() {
    active = false;
    unawaited(syncAnimationVisibility());
    timer?.cancel();
    motionTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> applySavedStyle() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted || !ready) return;
      final saved = prefs.getBool(ccsAdaptiveMapStylePreferenceKey) == true
          ? mapStyleForLocalTime(DateTime.now()).name
          : prefs.getString(ccsMapStylePreferenceKey);
      final next = saved == 'light' ? 'positron' : 'dark';
      if (next == style) return;
      setState(() {
        style = next;
        ready = false;
      });
      await controller.runJavaScript(
        'window.ccsSetStyle(${jsonEncode(next)});',
      );
    } catch (_) {}
  }

  Future<void> chooseStyle() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xff111216),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(18),
              child: CcsText(
                'Map style',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            for (final entry in {
              'positron': 'CCS Light',
              'dark': 'CCS Dark',
            }.entries)
              ListTile(
                leading: Icon(
                  entry.key == 'dark'
                      ? Icons.dark_mode_outlined
                      : Icons.light_mode_outlined,
                  color: Colors.white70,
                ),
                title: CcsText(
                  entry.value,
                  style: const TextStyle(color: Colors.white),
                ),
                trailing: style == entry.key
                    ? const Icon(Icons.check, color: Color(0xff008dff))
                    : null,
                onTap: () => Navigator.pop(context, entry.key),
              ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null || choice == style || !ready) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      ccsMapStylePreferenceKey,
      choice == 'positron' ? 'light' : 'dark',
    );
    await prefs.setBool(ccsAdaptiveMapStylePreferenceKey, false);
    if (!mounted) return;
    setState(() {
      style = choice;
      ready = false;
    });
    await controller.runJavaScript(
      'window.ccsSetStyle(${jsonEncode(choice)});',
    );
  }

  String get sharingCountdown {
    final seconds =
        (widget.sharingExpiresAt?.difference(DateTime.now()).inSeconds ?? 0)
            .clamp(0, 864000);
    return '${(seconds ~/ 3600).toString().padLeft(2, '0')}:${((seconds ~/ 60) % 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  Future<void> sharingOptions() async {
    if (!widget.isSharing) {
      await widget.onShareChanged(true);
      return;
    }
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.stop_circle_outlined),
              title: CcsText(trText('Stop sharing')),
              onTap: () => Navigator.pop(context, 'stop'),
            ),
            ListTile(
              leading: const Icon(Icons.more_time),
              title: CcsText(trText('Extend sharing')),
              onTap: () => Navigator.pop(context, 'extend'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    try {
      if (action == 'stop') await widget.onShareChanged(false);
      if (action == 'extend') await widget.onExtendSharing?.call();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: CcsText(trText('Could not update sharing. Please retry.')),
          ),
        );
    }
  }

  Widget control(
    String label,
    IconData icon,
    VoidCallback? onTap, {
    bool text = false,
    bool accent = false,
    bool amber = false,
    bool sharingActive = false,
    bool followSelected = false,
    bool large = false,
    bool fill = false,
  }) {
    final color = amber
        ? const Color(0xffeeb666)
        : followSelected
        ? const Color(0xffa3d8b7)
        : Colors.white;
    return Semantics(
      button: true,
      selected: followSelected,
      label: trText(label),
      child: Tooltip(
        message: trText(label),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (amber || large) ? 52 : 48,
              minWidth: (amber || large) ? 52 : 48,
            ),
            child: Center(
              heightFactor: 1,
              widthFactor: 1,
              child: Opacity(
                opacity: onTap == null ? .5 : 1,
                child: Container(
                  height: (amber || large) ? 44 : 36,
                  width: fill ? double.infinity : null,
                  padding: EdgeInsets.symmetric(
                    horizontal: text
                        ? 8
                        : (amber || large)
                        ? 11
                        : 9,
                  ),
                  decoration: BoxDecoration(
                    color: accent
                        ? null
                        : amber
                        ? const Color(0xff201a12)
                        : followSelected
                        ? const Color(0xff183c2d)
                        : const Color(0xff111319),
                    gradient: sharingActive
                        ? const LinearGradient(
                            colors: [Color(0xff13713c), Color(0xff19834c)],
                          )
                        : accent
                        ? const LinearGradient(
                            colors: [Color(0xff0646db), Color(0xff00a7d1)],
                          )
                        : null,
                    border: Border.all(
                      color: sharingActive
                          ? const Color(0xff35a563)
                          : amber
                          ? const Color(0xff635032)
                          : accent
                          ? const Color(0xff1273cc)
                          : followSelected
                          ? const Color(0xff467b5f)
                          : const Color(0xff33363e),
                    ),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        icon,
                        size: (amber || large) ? 22 : 18,
                        color: color,
                      ),
                      if (text) ...[
                        const SizedBox(width: 7),
                        Flexible(
                          child: CcsText(
                            trText(label),
                            textAlign: TextAlign.center,
                            maxLines: sharingActive ? 2 : 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: color,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final card = selectedId == null
        ? null
        : selectedKind == 'camera'
        ? cameraCard()
        : widget.cardBuilder(context, selectedKind!, selectedId!);
    return ColoredBox(
      color: const Color(0xff07080c),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: WebViewWidget(controller: controller)),
          if (widget.routeDistanceLabel != null)
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 58),
                  child: Material(
                    color: const Color(0xee10141c),
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      onTap: widget.onDismissRoute,
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.straighten,
                              size: 18,
                              color: Colors.lightBlueAccent,
                            ),
                            const SizedBox(width: 8),
                            CcsText(widget.routeDistanceLabel!),
                            const SizedBox(width: 10),
                            const Icon(Icons.close, size: 16),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (widget.showControls)
            Align(
              alignment: Alignment.topCenter,
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0xff0e1118),
                  border: Border(bottom: BorderSide(color: Color(0xff29313e))),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        if (widget.onBack != null)
                          control('Back', Icons.arrow_back, widget.onBack),
                        Expanded(
                          child: control(
                            'Styles',
                            Icons.layers_outlined,
                            ready ? chooseStyle : null,
                            text: true,
                            fill: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: control(
                            'Filters',
                            Icons.tune,
                            showFilters,
                            text: true,
                            fill: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: control(
                            widget.sharingBusy
                                ? trText('Updating...')
                                : widget.isSharing
                                ? '${trText('Sharing live')}\n$sharingCountdown'
                                : trText('Share live'),
                            widget.isSharing
                                ? Icons.wifi_tethering
                                : Icons.location_on_outlined,
                            widget.sharingBusy
                                ? null
                                : () => unawaited(sharingOptions()),
                            text: true,
                            accent: true,
                            sharingActive: widget.isSharing,
                            fill: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (error != null)
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 60),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CcsText(error!),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                error = null;
                                ready = false;
                                iconsSent = false;
                                style = 'dark';
                                previous = null;
                              });
                              unawaited(controller.reload());
                            },
                            child: const CcsText('Retry'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (widget.showControls && card == null) ...[
            Positioned(
              left: 8,
              bottom: 28,
              child: control(
                'Add alert',
                Icons.warning_amber_rounded,
                widget.onAddReport,
                amber: true,
              ),
            ),
            Positioned(
              right: 8,
              bottom: 28,
              child: control(
                'Follow my location',
                Icons.my_location,
                ready
                    ? () async {
                        await widget.onLocate();
                        await refresh();
                        await refreshMotion();
                        if (mounted && ready) {
                          await controller.runJavaScript('window.ccsFollow();');
                        }
                      }
                    : null,
                large: true,
                followSelected: followActive,
              ),
            ),
          ],
          if (card != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 24,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  control(
                    'Close preview',
                    Icons.close,
                    () => setState(() {
                      selectedId = null;
                      selectedKind = null;
                    }),
                  ),
                  card,
                ],
              ),
            ),
        ],
      ),
    );
  }
}
