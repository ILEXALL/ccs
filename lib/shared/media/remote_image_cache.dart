import 'package:flutter/painting.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// One shared on-device cache for photos, avatars and map avatar decodes.
/// Keep complete URLs as keys, including version/signature query parameters.
class AppRemoteImageCache {
  AppRemoteImageCache._();
  static final CacheManager manager = CacheManager(
    Config(
      'ccsRemoteImagesV1',
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 500,
    ),
  );
}

/// Capture cache status before decoding/downloading, not after the file is saved.
class AppCachedImageProvider extends CachedNetworkImageProvider {
  AppCachedImageProvider(String url, {BaseCacheManager? manager})
    : wasCached = _isCached(manager ?? AppRemoteImageCache.manager, url),
      super(url, cacheManager: manager ?? AppRemoteImageCache.manager);

  final Future<bool> wasCached;

  static Future<bool> _isCached(BaseCacheManager manager, String url) async {
    try {
      final file = await manager.getFileFromCache(url);
      return file != null && await file.file.exists();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<CachedNetworkImageProvider> obtainKey(
    ImageConfiguration configuration,
  ) async {
    await wasCached;
    return this;
  }
}

AppCachedImageProvider cachedAppImage(String url) =>
    AppCachedImageProvider(url);

Future<bool> imageWasCached(ImageProvider provider) {
  if (provider is ResizeImage) return imageWasCached(provider.imageProvider);
  if (provider is AppCachedImageProvider) return provider.wasCached;
  return Future.value(false);
}
