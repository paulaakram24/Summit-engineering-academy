import 'package:flutter_test/flutter_test.dart';
import 'package:summit_academy/commerce/order_models.dart';

const orderId = 'aaaaaaaa-1111-4111-8111-111111111111';
const newerTieId = 'bbbbbbbb-1111-4111-8111-111111111111';
const courseId = 'cccccccc-1111-4111-8111-111111111111';
const sessionId = 'dddddddd-1111-4111-8111-111111111111';
const instant = '2026-10-21T12:34:56.123456Z';

Map<String, dynamic> orderRow({
  String id = orderId,
  String createdAt = instant,
  bool session = false,
}) => {
  'id': id,
  'kind': session ? 'session' : 'course',
  'course_id': courseId,
  'session_id': session ? sessionId : null,
  'course_title_snapshot': 'Structural engineering',
  'session_title_snapshot': session ? 'Concrete foundations' : null,
  'price_piasters': 12345,
  'currency': 'EGP',
  'state': 'pending',
  'created_at': createdAt,
};
Map<String, dynamic> envelope(
  List<Map<String, dynamic>> items, {
  bool more = false,
}) => {
  'items': items,
  'has_more': more,
  'next_cursor': more && items.isNotEmpty
      ? {'created_at': items.last['created_at'], 'id': items.last['id']}
      : null,
};
PendingOrderCursor cursor({String id = orderId, String createdAt = instant}) =>
    PendingOrderCursor.fromJson({'created_at': createdAt, 'id': id});

void main() {
  final invalid = throwsA(isA<PendingOrderModelFailure>());
  test('course exact ten-field projection is an intent only, not payment or access', () {
    final row = orderRow();
    expect(row, hasLength(10));
    final order = PendingOrder.fromJson(row);
    expect(order.id, orderId);
    expect(order.kind, PendingOrderKind.course);
    expect(order.courseId, courseId);
    expect(order.sessionId, isNull);
    expect(order.sessionTitleSnapshot, isNull);
    expect(order.pricePiasters, 12345);
    expect(order.currency, 'EGP');
    expect(order.state, PendingOrderState.pending);
    expect(PendingOrderState.values, [PendingOrderState.pending]);
  });
  test('session projection preserves both immutable title snapshots and no HTML interpretation', () {
    final order = PendingOrder.fromJson({
      ...orderRow(session: true),
      'session_title_snapshot': '<b>Concrete & foundations</b>',
    });
    expect(order.kind, PendingOrderKind.session);
    expect(order.sessionId, sessionId);
    expect(order.courseTitleSnapshot, 'Structural engineering');
    expect(order.sessionTitleSnapshot, '<b>Concrete & foundations</b>');
  });
  test(
    'only course/session kinds are accepted, never bundles or coerced values',
    () {
      for (final kind in ['bundle', 'Course', '', 'pending', true, 1, null]) {
        expect(
          () => PendingOrder.fromJson({...orderRow(), 'kind': kind}),
          invalid,
        );
      }
    },
  );
  test('currency and state are exactly EGP/pending; no paid/approved/expired states', () {
    for (final state in [
      'paid',
      'approved',
      'rejected',
      'expired',
      'Pending',
      '',
      true,
      null,
    ]) {
      expect(
        () => PendingOrder.fromJson({...orderRow(), 'state': state}),
        invalid,
      );
    }
    for (final currency in ['USD', 'egp', '', 1, null]) {
      expect(
        () => PendingOrder.fromJson({...orderRow(), 'currency': currency}),
        invalid,
      );
    }
  });
  test('all IDs are UUIDs without whitespace; valid case variants normalize consistently', () {
    for (final field in ['id', 'course_id', 'session_id']) {
      for (final value in ['bad', '', '$orderId\n', ' $orderId', 1, null]) {
        expect(
          () =>
              PendingOrder.fromJson({...orderRow(session: true), field: value}),
          invalid,
          reason: field,
        );
      }
    }
    final order = PendingOrder.fromJson({
      ...orderRow(session: true),
      'id': orderId.toUpperCase(),
      'course_id': courseId.toUpperCase(),
      'session_id': sessionId.toUpperCase(),
    });
    expect(order.id, orderId);
    expect(order.courseId, courseId);
    expect(order.sessionId, sessionId);
  });
  test('course kind requires null session ID and title, independently', () {
    expect(
      () => PendingOrder.fromJson({...orderRow(), 'session_id': sessionId}),
      invalid,
    );
    expect(
      () => PendingOrder.fromJson({
        ...orderRow(),
        'session_title_snapshot': 'Unexpected session',
      }),
      invalid,
    );
    expect(
      () => PendingOrder.fromJson({
        ...orderRow(),
        'session_id': sessionId,
        'session_title_snapshot': 'Session',
      }),
      invalid,
    );
  });
  test(
    'session kind requires session UUID and both nonempty title snapshots',
    () {
      for (final field in ['course_title_snapshot', 'session_title_snapshot']) {
        for (final value in [null, '', '   ', true, 1]) {
          expect(
            () => PendingOrder.fromJson({
              ...orderRow(session: true),
              field: value,
            }),
            invalid,
          );
        }
      }
      expect(
        () => PendingOrder.fromJson({
          ...orderRow(session: true),
          'session_id': null,
        }),
        invalid,
      );
    },
  );
  test('title limits count Unicode runes, not UTF16 units', () {
    for (final field in ['course_title_snapshot', 'session_title_snapshot']) {
      final order = PendingOrder.fromJson({
        ...orderRow(session: true),
        field: '😀' * 160,
      });
      expect(
        field == 'course_title_snapshot'
            ? order.courseTitleSnapshot
            : order.sessionTitleSnapshot,
        '😀' * 160,
      );
      expect(
        () => PendingOrder.fromJson({
          ...orderRow(session: true),
          field: '😀' * 161,
        }),
        invalid,
      );
    }
  });
  test('title requiredness uses catalog ASCII-space rule, preserves display text and blocks NUL', () {
    final text = '  \t\u00a0Engineering  ';
    final order = PendingOrder.fromJson({
      ...orderRow(),
      'course_title_snapshot': text,
    });
    expect(order.courseTitleSnapshot, text);
    expect(
      () => PendingOrder.fromJson({
        ...orderRow(),
        'course_title_snapshot': '\t\u00a0',
      }),
      returnsNormally,
    );
    for (final field in ['course_title_snapshot', 'session_title_snapshot']) {
      expect(
        () => PendingOrder.fromJson({
          ...orderRow(session: true),
          field: 'Title\u0000PRIVATE_CANARY',
        }),
        invalid,
      );
    }
  });
  test(
    'price remains bounded integer piasters with no decimal/string coercion',
    () {
      for (final value in [0, 2147483647]) {
        expect(
          PendingOrder.fromJson({...orderRow(), 'price_piasters': value})
              .pricePiasters,
          value,
        );
      }
      for (final value in [-1, 2147483648, 1.0, '1', true, null]) {
        expect(
          () => PendingOrder.fromJson({...orderRow(), 'price_piasters': value}),
          invalid,
        );
      }
    },
  );
  test(
    'all ten JSON fields are required including nullable session fields',
    () {
      for (final field in orderRow().keys) {
        expect(
          () => PendingOrder.fromJson({...orderRow()}..remove(field)),
          invalid,
          reason: field,
        );
      }
      for (final shape in [null, [], 'PRIVATE_CANARY', 1]) {
        expect(() => PendingOrder.fromJson(shape), invalid);
      }
    },
  );
  test('valid baseline plus any buyer/internal/private/delivery/expiry field is rejected', () {
    for (final field in [
      'buyer_id',
      'user_id',
      'internal_notes',
      'token',
      'playback_url',
      'receipt_path',
      'target_url',
      'body_text',
      'paid',
      'access_grant',
      'expires_at',
    ]) {
      expect(
        () => PendingOrder.fromJson({...orderRow(), field: 'PRIVATE_CANARY'}),
        invalid,
        reason: field,
      );
    }
  });
  test(
    'created_at preserves all PostgreSQL microseconds and the adjacent instant',
    () {
      final order = PendingOrder.fromJson(orderRow());
      expect(order.createdAt.isUtc, isTrue);
      expect(order.createdAt.millisecond, 123);
      expect(order.createdAt.microsecond, 456);
      final next = PendingOrder.fromJson(
        orderRow(createdAt: '2026-10-21T12:34:56.123457Z'),
      );
      expect(next.createdAt.difference(order.createdAt).inMicroseconds, 1);
    },
  );
  test('explicit numeric timezones normalize to the identical UTC microsecond instant', () {
    final expected = PendingOrder.fromJson(orderRow()).createdAt;
    for (final value in [
      '2026-10-21T12:34:56.123456+00:00',
      '2026-10-21T14:34:56.123456+02:00',
      '2026-10-21T07:04:56.123456-05:30',
      '2026-10-21t12:34:56.123456z',
    ]) {
      final actual = PendingOrder.fromJson(orderRow(createdAt: value))
          .createdAt;
      expect(actual, expected);
      expect(actual.isUtc, isTrue);
    }
  });
  test('invalid date/time rollover never silently normalizes', () {
    for (final value in [
      '2025-02-29T00:00:00Z',
      '2026-02-30T00:00:00Z',
      '2026-04-31T00:00:00Z',
      '2026-00-01T00:00:00Z',
      '2026-13-01T00:00:00Z',
      '2026-01-00T00:00:00Z',
      '2026-01-01T24:00:00Z',
      '2026-01-01T00:60:00Z',
      '2026-01-01T00:00:60Z',
    ]) {
      expect(
        () => PendingOrder.fromJson(orderRow(createdAt: value)),
        invalid,
        reason: value,
      );
    }
  });
  test('date-only, timeless, zone-less, malformed offsets and trailing content are rejected', () {
    for (final value in [
      '2026-10-21',
      '12:34:56Z',
      '2026-10-21T12:34:56',
      '2026-10-21T12:34Z',
      '2026-10-21T12:34:56+24:00',
      '2026-10-21T12:34:56+02:60',
      '2026-10-21T12:34:56+2:00',
      '2026-10-21T12:34:56Z\n',
      '2026-10-21T12:34:56Z PRIVATE_CANARY',
      'infinity',
      '-infinity',
      '',
    ]) {
      expect(
        () => PendingOrder.fromJson(orderRow(createdAt: value)),
        invalid,
        reason: value,
      );
    }
  });
  test('fraction accepts zero to six digits but rejects precision loss and empty fraction', () {
    for (final suffix in ['', '.1', '.123', '.123456']) {
      expect(
        () => PendingOrder.fromJson(
          orderRow(createdAt: '2026-10-21T12:34:56${suffix}Z'),
        ),
        returnsNormally,
      );
    }
    for (final suffix in ['.', '.1234567', '.1234560', ',123456']) {
      expect(
        () => PendingOrder.fromJson(
          orderRow(createdAt: '2026-10-21T12:34:56${suffix}Z'),
        ),
        invalid,
      );
    }
  });
  test('Gregorian leap dates and distant future are valid without expiry/clock assumptions', () {
    for (final value in [
      '2000-02-29T00:00:00Z',
      '2400-02-29T00:00:00.000001Z',
      '0001-01-01T00:00:00Z',
      '9999-12-31T23:59:59.999999Z',
    ]) {
      expect(
        () => PendingOrder.fromJson(orderRow(createdAt: value)),
        returnsNormally,
      );
    }
    for (final value in [
      '1900-02-29T00:00:00Z',
      '0000-01-01T00:00:00Z',
      '0001-01-01T00:00:00+01:00',
      '9999-12-31T23:59:59-01:00',
    ]) {
      expect(() => PendingOrder.fromJson(orderRow(createdAt: value)), invalid);
    }
    expect(
      () => PendingOrderCursor(createdAt: DateTime(2026), id: orderId),
      invalid,
    );
  });
  test(
    'timestamp JSON must be a string, not epoch, DateTime or coerced value',
    () {
      for (final value in [null, true, 0, DateTime.utc(2026), {}]) {
        expect(
          () => PendingOrder.fromJson({...orderRow(), 'created_at': value}),
          invalid,
        );
      }
    },
  );
  test('cursor requires exactly the timestamp and UUID pair', () {
    for (final value in [
      null,
      {},
      {'created_at': instant},
      {'id': orderId},
      {'created_at': instant, 'id': 'bad'},
      {'created_at': instant, 'id': orderId, 'buyer': 'PRIVATE_CANARY'},
      {'created_at': '2026-02-30T00:00:00Z', 'id': orderId},
    ]) {
      expect(() => PendingOrderCursor.fromJson(value), invalid);
    }
  });
  test(
    'cursor chronological comparison descends at exact microsecond precision',
    () {
      final newer = cursor(createdAt: '2026-10-21T12:34:56.123457Z');
      final older = cursor(createdAt: '2026-10-21T12:34:56.123455Z');
      expect(newer.compareTo(cursor()), lessThan(0));
      expect(older.compareTo(cursor()), greaterThan(0));
    },
  );
  test('UUID ties descend and cursor equality/hash normalize UUID case and timezone', () {
    expect(cursor(id: newerTieId).compareTo(cursor()), lessThan(0));
    final equivalent = cursor(
      id: orderId.toUpperCase(),
      createdAt: '2026-10-21T14:34:56.123456+02:00',
    );
    expect(equivalent, cursor());
    expect(equivalent.hashCode, cursor().hashCode);
    expect({equivalent, cursor()}, hasLength(1));
  });
  test('cursor JSON round-trip retains six fractional digits rather than milliseconds', () {
    final encoded = cursor().toJson();
    expect(encoded, {'created_at': instant, 'id': orderId});
    expect(PendingOrderCursor.fromJson(encoded), cursor());
    expect(
      cursor(createdAt: '2026-10-21T12:34:56.000001Z').toJson()['created_at'],
      '2026-10-21T12:34:56.000001Z',
    );
  });
  test('page defaults to 20 and accepts up to 50 in descending UUID/time order', () {
    List<Map<String, dynamic>> rows(int count) => List.generate(
      count,
      (i) => orderRow(
        id: '${(count - i).toRadixString(16).padLeft(8, '0')}-1111-4111-8111-111111111111',
      ),
    );
    final first = PendingOrderPage.fromJson(envelope(rows(20), more: true));
    expect(first.items, hasLength(20));
    expect(first.nextCursor, first.items.last.cursor);
    final maximum = PendingOrderPage.fromJson(envelope(rows(50)), limit: 50);
    expect(maximum.items, hasLength(50));
    expect(maximum.hasMore, isFalse);
    expect(maximum.nextCursor, isNull);
    expect(PendingOrderPage.fromJson(envelope([])).items, isEmpty);
  });
  test('page limit and count guards reject 0/51 and an overfull response', () {
    for (final limit in [0, -1, 51]) {
      expect(
        () => PendingOrderPage.fromJson(envelope([]), limit: limit),
        invalid,
      );
    }
    expect(
      () => PendingOrderPage.fromJson(
        envelope([orderRow(id: newerTieId), orderRow()]),
        limit: 1,
      ),
      invalid,
    );
    expect(
      () => PendingOrderPage(
        items: [],
        hasMore: false,
        nextCursor: null,
        limit: 51,
      ),
      invalid,
    );
  });
  test(
    'duplicate order IDs are rejected even with changed time or UUID casing',
    () {
      for (final duplicate in [
        orderRow(),
        orderRow(id: orderId.toUpperCase()),
        orderRow(createdAt: '2026-10-20T00:00:00Z'),
      ]) {
        expect(
          () => PendingOrderPage.fromJson(envelope([orderRow(), duplicate])),
          invalid,
        );
      }
    },
  );
  test(
    'page must strictly follow descending order and supplied after boundary',
    () {
      expect(
        () => PendingOrderPage.fromJson(
          envelope([orderRow(), orderRow(id: newerTieId)]),
        ),
        invalid,
      );
      expect(
        () => PendingOrderPage.fromJson(
          envelope([orderRow(id: newerTieId)]),
          after: cursor(),
        ),
        invalid,
      );
      expect(
        () =>
            PendingOrderPage.fromJson(envelope([orderRow()]), after: cursor()),
        invalid,
      );
      expect(
        () => PendingOrderPage.fromJson(
          envelope([orderRow(createdAt: '2026-10-20T00:00:00Z')]),
          after: cursor(),
        ),
        invalid,
        reason:
            'The boundary order ID cannot reappear at a different timestamp.',
      );
      final accepted = PendingOrderPage.fromJson(
        envelope([orderRow()]),
        after: cursor(id: newerTieId),
      );
      expect(accepted.items.single.id, orderId);
    },
  );
  test(
    'has-more cursor is exactly last returned row including microseconds',
    () {
      final value = envelope([orderRow()], more: true);
      expect(
        () => PendingOrderPage.fromJson({
          ...value,
          'next_cursor': {
            'created_at': '2026-10-21T12:34:56.123455Z',
            'id': orderId,
          },
        }, limit: 1),
        invalid,
      );
      expect(
        () => PendingOrderPage.fromJson({
          ...value,
          'next_cursor': {'created_at': instant, 'id': newerTieId},
        }, limit: 1),
        invalid,
      );
      final accepted = PendingOrderPage.fromJson(value, limit: 1);
      expect(accepted.nextCursor, cursor());
    },
  );
  test('has-more cardinality and terminal cursor must agree with the page', () {
    for (final value in [
      envelope([orderRow()], more: true),
      {'items': [], 'has_more': true, 'next_cursor': cursor().toJson()},
      {
        ...envelope([orderRow()]),
        'next_cursor': cursor().toJson(),
      },
      {
        ...envelope([orderRow()], more: true),
        'next_cursor': null,
      },
    ]) {
      expect(() => PendingOrderPage.fromJson(value), invalid);
    }
  });
  test('page envelope is exact, strictly typed and validates each row', () {
    for (final value in [
      null,
      [],
      {...envelope([]), 'buyer_id': 'PRIVATE_CANARY'},
      {'items': [], 'has_more': false},
      {'items': null, 'has_more': false, 'next_cursor': null},
      {...envelope([]), 'has_more': 0},
      {
        ...envelope([]),
        'items': [null],
      },
      envelope([
        {...orderRow(), 'state': 'paid'},
      ]),
    ]) {
      expect(() => PendingOrderPage.fromJson(value), invalid);
    }
  });
  test('page items are copied and immutable; changing source JSON cannot rewrite the model', () {
    final row = orderRow();
    final source = [PendingOrder.fromJson(row)];
    final page = PendingOrderPage(
      items: source,
      hasMore: false,
      nextCursor: null,
    );
    source.clear();
    row['price_piasters'] = 1;
    expect(page.items.single.pricePiasters, 12345);
    expect(page.items, hasLength(1));
    expect(() => page.items.clear(), throwsUnsupportedError);
    expect(
      () => page.items.add(PendingOrder.fromJson(orderRow(id: newerTieId))),
      throwsUnsupportedError,
    );
  });
  test('failure text never interpolates an unknown private field or timestamp body', () {
    for (final value in [
      {...orderRow(), 'internal_notes': 'PRIVATE_CANARY'},
      {...orderRow(), 'created_at': 'PRIVATE_CANARY'},
    ]) {
      try {
        PendingOrder.fromJson(value);
        fail('Must reject');
      } on PendingOrderModelFailure catch (error) {
        expect(
          error.toString(),
          'The pending-order data could not be verified.',
        );
        expect(error.toString(), isNot(contains('PRIVATE_CANARY')));
      }
    }
  });
}
