import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:ccs_app/shared/media/remote_image_cache.dart';

void main() {
  final originalOverrides = HttpOverrides.current;
  TestWidgetsFlutterBinding.ensureInitialized();
  // This integration test serves files from a local HTTP server.
  HttpOverrides.global = originalOverrides;

  test(
    'disk cache deduplicates downloads and survives restart while offline',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ccs-disk-cache-test-',
      );
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => directory.path);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var requests = 0;
      server.listen((request) async {
        requests++;
        request.response.headers.set(
          HttpHeaders.cacheControlHeader,
          'max-age=86400',
        );
        request.response.headers.set(
          HttpHeaders.contentTypeHeader,
          'image/png',
        );
        request.response.add([
          1,
          2,
          3,
          request.uri.queryParameters['v'] == '2' ? 2 : 1,
        ]);
        await request.response.close();
      });
      CacheManager manager = AppRemoteImageCache.manager;
      final url = 'http://127.0.0.1:${server.port}/cover.png?v=1';
      try {
        final provider = cachedAppImage(url);
        expect(identical(provider.cacheManager, manager), isTrue);
        expect(await provider.wasCached, isFalse);
        final results = await Future.wait(
          List.generate(3, (_) => manager.getSingleFile(url)),
        );
        expect(requests, 1);
        expect(await results.first.readAsBytes(), [1, 2, 3, 1]);
        await manager.getSingleFile(url);
        expect(requests, 1);
        expect(await cachedAppImage(url).wasCached, isTrue);
        expect(
          await provider.wasCached,
          isFalse,
        ); // The initial decision is stable.
        final changed = await manager.getSingleFile(
          url.replaceAll('v=1', 'v=2'),
        );
        expect(await changed.readAsBytes(), [1, 2, 3, 2]);
        expect(requests, 2);
        await manager.dispose();
        await server.close(force: true);
        manager = CacheManager(
          Config(
            'ccsRemoteImagesV1',
            stalePeriod: const Duration(days: 30),
            maxNrOfCacheObjects: 500,
          ),
        );
        expect(
          await AppCachedImageProvider(url, manager: manager).wasCached,
          isTrue,
        );
        final offline = await manager.getSingleFile(url);
        expect(await offline.readAsBytes(), [1, 2, 3, 1]);
        expect(requests, 2);
      } finally {
        await server.close(force: true);
        await manager.emptyCache();
        await manager.dispose();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        // Only the unique directory created by this test is removed.
        await directory.delete(recursive: true);
      }
    },
  );
}
