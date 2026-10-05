import 'package:ccs_app/features/map/screens/location_picker_screen.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:ccs_app/features/map/screens/globe_map_screen.dart';

void main() {
  testWidgets('location confirmation clears Android system navigation', (
    tester,
  ) async {
    WebViewPlatform.instance = _Platform();
    await tester.binding.setSurfaceSize(const Size(393, 800));
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 48);
    addTearDown(() {
      tester.view.resetPadding();
      tester.view.resetDevicePixelRatio();
      tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      const MaterialApp(
        home: LocationPickerScreen(initialLocation: LatLng(57, 24)),
      ),
    );
    await tester.pump();
    final button = find.widgetWithText(ElevatedButton, 'Use this Location');
    expect(button, findsOneWidget);
    expect(tester.getRect(button).bottom, lessThanOrEqualTo(752));
    expect(tester.widget<ElevatedButton>(button).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final size in [
    const Size(320, 720),
    const Size(393, 800),
    const Size(800, 393),
  ]) {
    testWidgets('globe fills available body at $size', (tester) async {
      final original = WebViewPlatform.instance;
      WebViewPlatform.instance = _Platform();
      addTearDown(() {
        if (original != null) WebViewPlatform.instance = original;
      });
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: const SizedBox(
              height: 62,
              child: Center(child: Text('App navigation: Map selected')),
            ),
            body: GlobeMapScreen(
              readFeatures: () => {'type': 'FeatureCollection', 'features': []},
              isSharing: false,
              sharingBusy: false,
              onShareChanged: (_) async {},
              cardBuilder: (_, kind, id) => const SizedBox.shrink(),
              onFilter: () async {},
              onAddReport: () async {},
              onLocate: () async {},
            ),
          ),
        ),
      );
      await tester.pump();
      final map = tester.getRect(find.byKey(const Key('native-map')));
      expect(find.byTooltip('Back'), findsNothing);
      expect(map.top, 0);
      expect(map.bottom, size.height - 62);
      expect(find.text('App navigation: Map selected'), findsOneWidget);
      expect(map.width, size.width);
      final add = tester.getRect(find.byTooltip('Add alert'));
      final filters = tester.getRect(find.byTooltip('Filters'));
      final share = tester.getRect(find.byTooltip('Share live'));
      final styles = tester.getRect(find.byTooltip('Styles'));
      expect(add.overlaps(filters), isFalse);
      expect(styles.top, share.top);
      expect(filters.top, share.top);
      expect(styles.overlaps(filters), isFalse);
      expect(filters.overlaps(share), isFalse);
      expect(add.left, lessThan(16));
      expect(add.bottom, greaterThan(map.bottom - 40));
      expect(share.right, greaterThan(size.width - 20));
      expect(share.top, lessThan(20));
      expect(share.height, greaterThanOrEqualTo(44));
      expect(add.bottom, lessThan(map.bottom));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets('spot preview and sharing keep the app navigation in place', (
    tester,
  ) async {
    WebViewPlatform.instance = _Platform();
    bool? requestedSharing;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: const Text('Map selected'),
          body: GlobeMapScreen(
            isSharing: false,
            sharingBusy: false,
            onShareChanged: (value) async {
              requestedSharing = value;
            },
            readFeatures: () => {'type': 'FeatureCollection', 'features': []},
            cardBuilder: (_, kind, id) => kind == 'spot' && id == 'sample'
                ? const SizedBox(height: 120, child: Text('Sample spot card'))
                : null,
            onFilter: () async {},
            onAddReport: () async {},
            onLocate: () async {},
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Share live'));
    expect(requestedSharing, isTrue);
    _Controller.channel!.onMessageReceived(
      const JavaScriptMessage(
        message: '{"type":"select","kind":"spot","id":"sample"}',
      ),
    );
    await tester.pump();
    expect(find.text('Sample spot card'), findsOneWidget);
    expect(find.text('Map selected'), findsOneWidget);
    expect(find.byType(GlobeMapScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Close preview'));
    await tester.pump();
    expect(find.text('Sample spot card'), findsNothing);
    expect(find.text('Map selected'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _Platform extends WebViewPlatform {
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) => _Controller(params);
  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => _Delegate(params);
  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _View(params);
}

class _Controller extends PlatformWebViewController {
  static JavaScriptChannelParams? channel;
  _Controller(super.params) : super.implementation();
  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  @override
  Future<void> setBackgroundColor(Color color) async {}
  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams params) async {
    channel = params;
  }

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {}
  @override
  Future<void> loadFlutterAsset(String key) async {}
}

class _Delegate extends PlatformNavigationDelegate {
  _Delegate(super.params) : super.implementation();
  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback callback,
  ) async {}
  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async {}
}

class _View extends PlatformWebViewWidget {
  _View(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) =>
      const ColoredBox(key: Key('native-map'), color: Colors.blue);
}
