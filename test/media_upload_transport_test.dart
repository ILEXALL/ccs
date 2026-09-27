import 'dart:io';

import 'package:ccs_app/shared/media/media_upload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'signed upload sends bytes and the server-selected cache header',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final received = server.first.then((request) async {
        expect(request.method, 'PUT');
        expect(request.headers.contentType?.mimeType, 'image/jpeg');
        expect(
          request.headers.value(HttpHeaders.cacheControlHeader),
          'public, max-age=300, must-revalidate',
        );
        final body = await request.fold<List<int>>(
          [],
          (all, part) => all..addAll(part),
        );
        expect(body, [1, 2, 3]);
        request.response.statusCode = 200;
        await request.response.close();
      });
      await putBytesToPresignedUrl(
        uploadUrl: 'http://127.0.0.1:${server.port}/synthetic.jpg',
        bytes: [1, 2, 3],
        contentType: 'image/jpeg',
        cacheControl: 'public, max-age=300, must-revalidate',
      );
      await received;
    },
  );

  test(
    'storage rejection is surfaced instead of reporting a successful upload',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final received = server.first.then((request) async {
        await request.drain<void>();
        request.response.statusCode = 403;
        await request.response.close();
      });
      await expectLater(
        putBytesToPresignedUrl(
          uploadUrl: 'http://127.0.0.1:${server.port}/synthetic.jpg',
          bytes: [1],
          contentType: 'image/jpeg',
        ),
        throwsException,
      );
      await received;
    },
  );
}
