import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:summit_academy/content/content_models.dart';
import 'package:summit_academy/content/course_covers.dart';

const _id = '11111111-1111-4111-8111-111111111111';
const _otherId = '44444444-4444-4444-8444-444444444444';
const _path = '$_id/22222222-2222-4222-8222-222222222222.png';
const _previous = '$_id/33333333-3333-4333-8333-333333333333.png';
Course _course({String id = _id, String? path, DateTime? deletedAt}) => Course(
  id: id,
  title: 'Course',
  instructor: 'Teacher',
  category: 'Civil',
  level: 'Beginner',
  pricePiasters: 100,
  coverPath: path,
  deletedAt: deletedAt,
);
Map<String, dynamic> _row({String id = _id, String? path = _path}) => {
  'id': id,
  'title': 'Course',
  'description': '',
  'instructor': 'Teacher',
  'category': 'Civil',
  'level': 'Beginner',
  'price_piasters': 100,
  'position': 0,
  'status': 'draft',
  'deleted_at': null,
  'cover_path': path,
};

Future<Uint8List> _makePng(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawPaint(ui.Paint()..color = const ui.Color(0xff225588));
  final picture = recorder.endRecording();
  ui.Image? image;
  try {
    image = await picture.toImage(width, height);
    final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    return Uint8List.fromList(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  } finally {
    image?.dispose();
    picture.dispose();
  }
}

// A valid PNG ancillary metadata chunk for verifying metadata stripping.
Uint8List _withText(Uint8List png) {
  final data = [
    ...ascii.encode('tEXt'),
    ...ascii.encode('Comment\x00private-metadata'),
  ];
  var crc = 0xffffffff;
  for (final byte in data) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
    }
  }
  crc ^= 0xffffffff;
  final length = ByteData(4)..setUint32(0, data.length - 4);
  final checksum = ByteData(4)..setUint32(0, crc);
  return Uint8List.fromList([
    ...png.sublist(0, png.length - 12),
    ...length.buffer.asUint8List(),
    ...data,
    ...checksum.buffer.asUint8List(),
    ...png.sublist(png.length - 12),
  ]);
}

class _Backend {
  final requests = <http.Request>[];
  String preparedPath = _path;
  Object? attachedOverride;
  Object? retiredOverride;
  List<String> retired = [];
  bool uploadFails = false,
      attachFails = false,
      attachResponseLost = false,
      abandonFails = false,
      removeFails = false,
      finishFails = false;
  Uint8List download = Uint8List(0);
  final Set<String> protectedPaths = {_previous};

  http.Response json(http.Request request, Object? value, [int status = 200]) =>
      http.Response(
        jsonEncode(value),
        status,
        request: request,
        headers: {'content-type': 'application/json'},
      );
  http.Response fail(http.Request request) => json(request, {
    'code': '42501',
    'message': 'private token URL details',
  }, 403);

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final endpoint = request.url.pathSegments.last;
    switch (endpoint) {
      case 'prepare_course_cover':
        return json(request, {'path': preparedPath});
      case 'attach_course_cover':
        if (attachResponseLost) {
          protectedPaths.add(_path);
          throw TimeoutException('private token URL details');
        }
        if (attachFails) return fail(request);
        protectedPaths.add(_path);
        return json(request, attachedOverride ?? _row());
      case 'abandon_course_cover':
        final path = (jsonDecode(request.body) as Map)['p_path'];
        if (abandonFails) return fail(request);
        if (!protectedPaths.contains(path)) retired.add(path as String);
        return json(request, null);
      case 'list_retired_course_covers':
        return json(request, retiredOverride ?? retired);
      case 'finish_course_cover_cleanup':
        return finishFails ? fail(request) : json(request, null);
    }
    if (request.method == 'GET') {
      return http.Response.bytes(
        download,
        200,
        request: request,
        headers: {'content-type': 'image/png'},
      );
    }
    if (request.method == 'DELETE') {
      final paths = ((jsonDecode(request.body) as Map)['prefixes'] as List);
      if (removeFails || paths.any(protectedPaths.contains)) {
        return fail(request);
      }
      return json(request, []);
    }
    if (request.method == 'POST' && request.url.path.contains('/storage/')) {
      return uploadFails
          ? fail(request)
          : json(request, {'Key': 'course-covers/$preparedPath'});
    }
    throw StateError('Unexpected test request');
  }

  List<http.Request> rpc(String name) =>
      requests.where((r) => r.url.path.endsWith('/$name')).toList();
  List<http.Request> get removals =>
      requests.where((r) => r.method == 'DELETE').toList();
  List<http.Request> get uploads => requests
      .where((r) => r.method == 'POST' && r.url.path.contains('/storage/'))
      .toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Uint8List png;
  setUpAll(() async {
    png = await _makePng(1, 1);
  });

  group('sanitizing', () {
    test('valid 1x1 PNG is reencoded and metadata is stripped', () async {
      final result = await sanitizeCoverImage(_withText(png));
      expect(result.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      expect(result.length, lessThanOrEqualTo(maxCoverPngBytes));
      expect(latin1.decode(result), isNot(contains('private-metadata')));
      final codec = await ui.instantiateImageCodec(result);
      try {
        expect(codec.frameCount, 1);
        final image = (await codec.getNextFrame()).image;
        try {
          expect(image.width, 1);
          expect(image.height, 1);
        } finally {
          image.dispose();
        }
      } finally {
        codec.dispose();
      }
    });
    test(
      'SVG, GIF, empty, corrupt JPEG/WebP and truncated PNG fail sanitized',
      () async {
        for (final bytes in [
          <int>[],
          utf8.encode('<svg/>'),
          ascii.encode('GIF89a'),
          [255, 216, 255, 0],
          ascii.encode('RIFF0000WEBP'),
          [137, 80, 78, 71, 13, 10, 26, 10],
        ]) {
          await expectLater(
            sanitizeCoverImage(Uint8List.fromList(bytes)),
            throwsA(isA<CourseCoverFailure>()),
          );
        }
      },
    );
    test('raw input over 5 MiB is rejected', () async {
      final bytes = Uint8List(maxCoverInputBytes + 1)..setRange(0, 8, png);
      await expectLater(
        sanitizeCoverImage(bytes),
        throwsA(isA<CourseCoverFailure>()),
      );
    });
    test('dimensions over 4096 rejected before codec instantiation', () async {
      await expectLater(
        sanitizeCoverImage(await _makePng(4097, 1)),
        throwsA(isA<CourseCoverFailure>()),
      );
    });
    test(
      'pixel count over 16 million rejected even at valid dimensions',
      () async {
        await expectLater(
          sanitizeCoverImage(await _makePng(4096, 4096)),
          throwsA(isA<CourseCoverFailure>()),
        );
      },
    );
  });

  group('private cover lifecycle', () {
    late _Backend backend;
    late SupabaseClient client;
    late CourseCoverService service;
    setUp(() {
      backend = _Backend()..download = png;
      client = SupabaseClient(
        'https://example.test',
        'sb_publishable_test',
        accessToken: () async => 'synthetic-user-jwt',
        httpClient: MockClient(backend.handle),
      );
      service = CourseCoverService(client);
    });
    tearDown(() async {
      await client.dispose();
    });

    test(
      'prepare upload attach uses private bucket and expected prior path',
      () async {
        final result = await service.replaceCover(
          _course(path: _previous),
          png,
        );
        expect(result.coverPath, _path);
        expect(jsonDecode(backend.rpc('prepare_course_cover').single.body), {
          'p_course_id': _id,
        });
        expect(jsonDecode(backend.rpc('attach_course_cover').single.body), {
          'p_course_id': _id,
          'p_path': _path,
          'p_expected_previous_path': _previous,
        });
        final upload = backend.uploads.single;
        expect(upload.url.path, '/storage/v1/object/course-covers/$_path');
        expect(
          upload.headers['content-type'],
          startsWith('multipart/form-data;'),
        );
        final multipart = latin1.decode(upload.bodyBytes);
        expect(multipart, contains('content-type: image/png'));
        expect(multipart, contains('name="cacheControl"\r\n\r\n0\r\n'));
        expect(upload.headers['x-upsert'], 'false');
        expect(multipart, contains(latin1.decode(png)));
        expect(
          backend.requests.every(
            (r) => r.headers['authorization'] == 'Bearer synthetic-user-jwt',
          ),
          isTrue,
        );
        expect(backend.removals, isEmpty);
        expect(backend.rpc('abandon_course_cover'), isEmpty);
      },
    );
    test('first cover sends an explicit null expected previous path', () async {
      await service.replaceCover(_course(), png);
      expect(jsonDecode(backend.rpc('attach_course_cover').single.body), {
        'p_course_id': _id,
        'p_path': _path,
        'p_expected_previous_path': null,
      });
    });
    test('invalid IDs, input and previous paths cause no requests', () async {
      for (final course in [
        _course(id: 'bad'),
        _course(path: '$_otherId/22222222-2222-4222-8222-222222222222.png'),
        _course(path: 'https://example.test/cover.png'),
        _course(deletedAt: DateTime.utc(2026)),
      ]) {
        await expectLater(
          service.replaceCover(course, png),
          throwsA(isA<CourseCoverFailure>()),
        );
      }
      await expectLater(
        service.replaceCover(_course(), Uint8List(maxCoverPngBytes + 1)),
        throwsA(isA<CourseCoverFailure>()),
      );
      await expectLater(
        service.replaceCover(_course(), Uint8List.fromList([1, 2])),
        throwsA(isA<CourseCoverFailure>()),
      );
      expect(backend.requests, isEmpty);
    });
    test(
      'wrong prefix, traversal and reused prepared path never upload or delete',
      () async {
        for (final path in [
          '$_otherId/22222222-2222-4222-8222-222222222222.png',
          '$_id/../x.png',
          _previous,
          '$_id/22222222-2222-4222-8222-222222222222.jpg',
        ]) {
          backend.preparedPath = path;
          await expectLater(
            service.replaceCover(_course(path: _previous), png),
            throwsA(isA<CourseCoverFailure>()),
          );
        }
        expect(backend.uploads, isEmpty);
        expect(backend.removals, isEmpty);
        expect(backend.rpc('abandon_course_cover'), isEmpty);
      },
    );
    test(
      'upload failure abandons before exact-path removal and finish',
      () async {
        backend.uploadFails = true;
        await expectLater(
          service.replaceCover(_course(path: _previous), png),
          throwsA(isA<CourseCoverFailure>()),
        );
        expect(backend.rpc('attach_course_cover'), isEmpty);
        expect(backend.rpc('abandon_course_cover'), hasLength(1));
        expect(jsonDecode(backend.removals.single.body), {
          'prefixes': [_path],
        });
        expect(
          jsonDecode(backend.rpc('finish_course_cover_cleanup').single.body),
          {'p_course_id': _id, 'p_path': _path},
        );
        final endpoints = backend.requests
            .map((r) => r.url.pathSegments.last)
            .toList();
        expect(
          endpoints.indexOf('abandon_course_cover'),
          lessThan(endpoints.indexOf('course-covers')),
        );
      },
    );
    test(
      'attach conflict cleans only new reservation and sanitizes error',
      () async {
        backend.attachFails = true;
        await expectLater(
          service.replaceCover(_course(path: _previous), png),
          throwsA(
            isA<CourseCoverFailure>().having(
              (e) => e.message,
              'sanitized',
              isNot(contains('private token')),
            ),
          ),
        );
        expect(jsonDecode(backend.removals.single.body), {
          'prefixes': [_path],
        });
      },
    );
    test('lost attach response cannot delete an attached path', () async {
      backend.attachResponseLost = true;
      await expectLater(
        service.replaceCover(_course(), png),
        throwsA(isA<CourseCoverFailure>()),
      );
      expect(backend.rpc('abandon_course_cover'), hasLength(1));
      // Backend abandon returns 200/null even though attach already committed.
      expect(backend.rpc('list_retired_course_covers'), hasLength(1));
      expect(backend.retired, isEmpty);
      expect(backend.removals, isEmpty);
      expect(backend.rpc('finish_course_cover_cleanup'), isEmpty);
    });
    test('abandon cleanup leaves omitted reservation for a later explicit pass', () async {
      backend.attachFails = true;
      backend.retired = List.generate(
        20,
        (i) =>
            '$_id/${i.toRadixString(16).padLeft(8, '0')}-1111-4111-8111-111111111111.png',
      );
      await expectLater(
        service.replaceCover(_course(), png),
        throwsA(isA<CourseCoverFailure>()),
      );
      expect(backend.retired, contains(_path));
      expect(backend.rpc('list_retired_course_covers'), hasLength(1));
      expect(backend.removals, isEmpty);
      expect(backend.rpc('finish_course_cover_cleanup'), isEmpty);
    });
    test(
      'malformed retirement listing after abandon authorizes no deletion',
      () async {
        backend.attachFails = true;
        backend.retiredOverride = [_path, '$_id/../unsafe.png'];
        await expectLater(
          service.replaceCover(_course(), png),
          throwsA(isA<CourseCoverFailure>()),
        );
        expect(backend.removals, isEmpty);
        expect(backend.rpc('finish_course_cover_cleanup'), isEmpty);
      },
    );
    test('uncertain abandon never proceeds to storage removal', () async {
      backend.attachFails = true;
      backend.abandonFails = true;
      await expectLater(
        service.replaceCover(_course(), png),
        throwsA(isA<CourseCoverFailure>()),
      );
      expect(backend.removals, isEmpty);
    });
    test(
      'wrong attach result is rejected and cleanup cannot remove reference',
      () async {
        backend.attachedOverride = _row(id: _otherId);
        await expectLater(
          service.replaceCover(_course(), png),
          throwsA(isA<CourseCoverFailure>()),
        );
        expect(backend.removals, isEmpty);
      },
    );
    test('removal failure leaves finish pending', () async {
      backend.attachFails = true;
      backend.removeFails = true;
      await expectLater(
        service.replaceCover(_course(), png),
        throwsA(isA<CourseCoverFailure>()),
      );
      expect(backend.removals, hasLength(1));
      expect(backend.rpc('finish_course_cover_cleanup'), isEmpty);
    });
    test('cleanup is one batch of at most 20 and reports pending work', () async {
      backend.retired = List.generate(
        21,
        (i) =>
            '$_id/${i.toRadixString(16).padLeft(8, '0')}-1111-4111-8111-111111111111.png',
      );
      final result = await service.cleanupRetired(_id);
      expect(result.attempted, 20);
      expect(result.cleaned, 20);
      expect(result.failed, 0);
      expect(result.mayHaveMore, isTrue);
      expect(backend.rpc('list_retired_course_covers'), hasLength(1));
      expect(backend.removals, hasLength(20));
      expect(backend.rpc('finish_course_cover_cleanup'), hasLength(20));
    });
    test(
      'cleanup referenced path is rejected by backend and not finished',
      () async {
        backend.retired = [_previous, _path];
        final result = await service.cleanupRetired(_id);
        expect(result.failed, 1);
        expect(result.cleaned, 1);
        expect(result.mayHaveMore, isTrue);
        expect(backend.rpc('finish_course_cover_cleanup'), hasLength(1));
        expect(
          jsonDecode(
            backend.rpc('finish_course_cover_cleanup').single.body,
          )['p_path'],
          _path,
        );
      },
    );
    test('cleanup validates whole batch before any deletion', () async {
      backend.retired = [
        _path,
        '$_otherId/22222222-2222-4222-8222-222222222222.png',
      ];
      await expectLater(
        service.cleanupRetired(_id),
        throwsA(isA<CourseCoverFailure>()),
      );
      expect(backend.removals, isEmpty);
      backend.retiredOverride = {'unexpected': 'private'};
      await expectLater(
        service.cleanupRetired(_id),
        throwsA(isA<CourseCoverFailure>()),
      );
    });
    test(
      'cleanup deduplicates paths and finish failures remain pending',
      () async {
        backend.retired = [_path, _path];
        backend.finishFails = true;
        final result = await service.cleanupRetired(_id);
        expect(result.attempted, 1);
        expect(result.cleaned, 0);
        expect(result.failed, 1);
        expect(result.mayHaveMore, isTrue);
        expect(backend.removals, hasLength(1));
      },
    );
    test(
      'empty cleanup and no-cover download perform no storage operations',
      () async {
        final result = await service.cleanupRetired(_id);
        expect(result.attempted, 0);
        expect(result.mayHaveMore, isFalse);
        expect(await service.downloadCover(_course()), isNull);
        expect(backend.requests, hasLength(1));
      },
    );
    test(
      'download uses JWT binary request with no signed or public URL',
      () async {
        expect(await service.downloadCover(_course(path: _path)), png);
        final request = backend.requests.single;
        expect(request.method, 'GET');
        expect(request.url.path, '/storage/v1/object/course-covers/$_path');
        expect(request.url.queryParameters, isEmpty);
        expect(request.headers['authorization'], 'Bearer synthetic-user-jwt');
      },
    );
    test('download rejects unsafe paths without requesting them', () async {
      for (final path in [
        '$_otherId/22222222-2222-4222-8222-222222222222.png',
        '$_id/../x.png',
        'https://example.test/x.png',
      ]) {
        await expectLater(
          service.downloadCover(_course(path: path)),
          throwsA(isA<CourseCoverFailure>()),
        );
      }
      expect(backend.requests, isEmpty);
    });
    test(
      'download rejects corrupt, oversized and excessive-dimension images',
      () async {
        for (final bytes in [
          Uint8List.fromList(ascii.encode('GIF89a')),
          Uint8List(maxCoverPngBytes + 1),
          await _makePng(4097, 1),
          Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
        ]) {
          backend.download = bytes;
          await expectLater(
            service.downloadCover(_course(path: _path)),
            throwsA(isA<CourseCoverFailure>()),
          );
        }
      },
    );
  });
}
