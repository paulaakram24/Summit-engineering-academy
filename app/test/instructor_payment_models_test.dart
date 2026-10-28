import 'package:flutter_test/flutter_test.dart';
import 'package:summit_academy/commerce/instructor_payment_models.dart';

String id(int value) =>
    'ABCDEF00-0000-4000-8000-${value.toString().padLeft(12, '0')}';
Map<String, dynamic> profile() => {
  'instructor_id': id(1),
  'recipient_name': '  Fictional Receiver  ',
  'phone_number': '+12345678901',
  'method_configuration': 'instapay_only',
  'revision': 1,
};
Map<String, dynamic> binding() => {
  'course_id': id(2),
  'instructor_id': id(1),
  'revision': 1,
};
Map<String, dynamic> entry(int value) => {
  'instructor_id': id(value),
  'display_name': '  Example Instructor $value  ',
};
Map<String, dynamic> page(
  List<Object?> items, {
  bool more = false,
  Object? cursor,
}) => {'items': items, 'has_more': more, 'next_cursor': cursor};
final invalid = throwsA(isA<InstructorPaymentModelFailure>());

void main() {
  test(
    'profile exact five fields normalize UUID/name and retain canonical phone',
    () {
      final result = InstructorPaymentProfile.fromJson(profile());
      expect(result.instructorId, id(1).toLowerCase());
      expect(result.recipientName, 'Fictional Receiver');
      expect(result.phoneNumber, '+12345678901');
      expect(result.revision, 1);
      expect(
        result.methodConfiguration,
        InstructorPaymentMethodConfiguration.instapayOnly,
      );
    },
  );

  test('both method configurations round-trip their exact wire values', () {
    for (final configuration in InstructorPaymentMethodConfiguration.values) {
      final result = InstructorPaymentProfile.fromJson(
        profile()..['method_configuration'] = configuration.wireValue,
      );
      expect(result.methodConfiguration, configuration);
      expect(result.phoneNumber, '+12345678901');
    }
  });

  test('unknown/malformed method configuration is rejected', () {
    for (final value in [
      null,
      true,
      1,
      'vodafone_cash_only',
      'INSTAPAY_ONLY',
      'instapay_only ',
    ]) {
      expect(
        () => InstructorPaymentProfile.fromJson(
          profile()..['method_configuration'] = value,
        ),
        invalid,
      );
    }
  });

  test('canonical phones accept exact minimum and maximum digit counts', () {
    for (final value in [
      '1234567',
      '+1234567',
      '123456789012345',
      '+123456789012345',
    ]) {
      expect(
        InstructorPaymentProfile.fromJson(profile()..['phone_number'] = value)
            .phoneNumber,
        value,
      );
    }
  });

  test(
    'phones reject formatting, non-ASCII digits, controls and wrong types',
    () {
      for (final value in [
        null,
        1234567,
        '',
        '123456',
        '1234567890123456',
        ' 1234567',
        '1234567 ',
        '+ 1234567',
        '++1234567',
        '123-4567',
        '(123)4567',
        '١٢٣٤٥٦٧',
        '１２３４５６７',
        '1234567\n',
        '1234567\u0000',
      ]) {
        expect(
          () => InstructorPaymentProfile.fromJson(
            profile()..['phone_number'] = value,
          ),
          invalid,
        );
      }
    },
  );

  test('names count Unicode codepoints after ASCII-space trim', () {
    final name = List.filled(160, '😀').join();
    expect(
      InstructorPaymentProfile.fromJson(
        profile()..['recipient_name'] = ' $name ',
      ).recipientName,
      name,
    );
    expect(
      () => InstructorPaymentProfile.fromJson(
        profile()..['recipient_name'] = '${name}x',
      ),
      invalid,
    );
  });

  test(
    'names trim ASCII space only and retain internal and Unicode spaces',
    () {
      const name = '\u00a0Example  Receiver\u00a0';
      expect(
        InstructorPaymentProfile.fromJson(
          profile()..['recipient_name'] = ' $name ',
        ).recipientName,
        name,
      );
    },
  );

  test('names reject empty, space-only, and wrong types', () {
    for (final value in ['', '   ', null, 1, true]) {
      expect(
        () => InstructorPaymentProfile.fromJson(
          profile()..['recipient_name'] = value,
        ),
        invalid,
      );
    }
  });

  test('every ASCII control character is rejected in recipient names', () {
    for (final code in [...List.generate(32, (i) => i), 127]) {
      final name = 'A${String.fromCharCode(code)}B';
      expect(
        () => InstructorPaymentProfile.fromJson(
          profile()..['recipient_name'] = name,
        ),
        invalid,
      );
    }
  });

  test('current revisions accept 1 and int32 maximum', () {
    for (final revision in [1, 2147483647]) {
      expect(
        InstructorPaymentProfile.fromJson(profile()..['revision'] = revision)
            .revision,
        revision,
      );
      expect(
        CoursePaymentInstructor.fromJson(binding()..['revision'] = revision)
            .revision,
        revision,
      );
    }
  });

  test(
    'current revisions reject zero/create sentinel, overflow and nonintegers',
    () {
      for (final revision in [0, -1, 2147483648, 1.0, '1', null, true]) {
        expect(
          () => InstructorPaymentProfile.fromJson(
            profile()..['revision'] = revision,
          ),
          invalid,
        );
        expect(
          () => CoursePaymentInstructor.fromJson(
            binding()..['revision'] = revision,
          ),
          invalid,
        );
      }
    },
  );

  test('UUID validation shared across all model projections', () {
    for (final value in [
      null,
      1,
      '',
      '${id(1)} ',
      'not-a-uuid',
      'abcdef00-0000-4000-8000-00000000000g',
    ]) {
      expect(
        () => InstructorPaymentProfile.fromJson(
          profile()..['instructor_id'] = value,
        ),
        invalid,
      );
      expect(
        () =>
            CoursePaymentInstructor.fromJson(binding()..['course_id'] = value),
        invalid,
      );
      expect(
        () => CoursePaymentInstructor.fromJson(
          binding()..['instructor_id'] = value,
        ),
        invalid,
      );
      expect(
        () => PaymentInstructorDirectoryEntry.fromJson(
          entry(1)..['instructor_id'] = value,
        ),
        invalid,
      );
      expect(
        () => PaymentInstructorCursor.fromJson({'instructor_id': value}),
        invalid,
      );
    }
  });

  test('profile rejects missing keys one at a time', () {
    for (final key in profile().keys) {
      expect(
        () => InstructorPaymentProfile.fromJson(profile()..remove(key)),
        invalid,
      );
    }
  });

  test(
    'profile rejects extra/private/bank fields on otherwise valid baseline',
    () {
      for (final key in [
        'bank_name',
        'bank_account',
        'token',
        'pin',
        'created_by',
        'unknown',
      ]) {
        expect(
          () =>
              InstructorPaymentProfile.fromJson(profile()..[key] = 'forbidden'),
          invalid,
        );
      }
    },
  );

  test('binding exact three fields normalize both UUIDs', () {
    final result = CoursePaymentInstructor.fromJson(binding());
    expect(result.courseId, id(2).toLowerCase());
    expect(result.instructorId, id(1).toLowerCase());
    expect(result.revision, 1);
  });

  test('binding rejects missing and additional identity or session fields', () {
    for (final key in binding().keys) {
      expect(
        () => CoursePaymentInstructor.fromJson(binding()..remove(key)),
        invalid,
      );
    }
    for (final key in ['session_id', 'created_by', 'recipient_name']) {
      expect(
        () => CoursePaymentInstructor.fromJson(binding()..[key] = 'forbidden'),
        invalid,
      );
    }
  });

  test(
    'directory entry contains only normalized identity and display name',
    () {
      final result = PaymentInstructorDirectoryEntry.fromJson(entry(1));
      expect(result.instructorId, id(1).toLowerCase());
      expect(result.displayName, 'Example Instructor 1');
      expect(result.cursor.instructorId, result.instructorId);
    },
  );

  test('directory rejects receiving details, role claims, extras and missing fields', () {
    for (final key in [
      'phone_number',
      'recipient_name',
      'method_configuration',
      'bank_name',
      'is_admin',
      'revision',
    ]) {
      expect(
        () => PaymentInstructorDirectoryEntry.fromJson(
          entry(1)..[key] = 'forbidden',
        ),
        invalid,
      );
    }
    for (final key in entry(1).keys) {
      expect(
        () => PaymentInstructorDirectoryEntry.fromJson(entry(1)..remove(key)),
        invalid,
      );
    }
  });

  test('directory name validation rejects empty/oversize/nontext', () {
    for (final name in [
      '',
      '  ',
      List.filled(121, '😀').join(),
      'A\u0000B',
      null,
      1,
    ]) {
      expect(
        () => PaymentInstructorDirectoryEntry.fromJson(
          entry(1)..['display_name'] = name,
        ),
        invalid,
      );
    }
  });

  test('directory accepts newline and all non-NUL ASCII controls', () {
    for (final code in [...List.generate(31, (i) => i + 1), 127]) {
      final name = 'A${String.fromCharCode(code)}B';
      expect(
        PaymentInstructorDirectoryEntry.fromJson(
          entry(1)..['display_name'] = ' $name ',
        ).displayName,
        name,
      );
      expect(
        PaymentInstructorDirectoryEntry(
          instructorId: id(1),
          displayName: name,
        ).displayName,
        name,
      );
    }
    expect(
      PaymentInstructorDirectoryEntry.fromJson(
        entry(1)..['display_name'] = 'First\nLast',
      ).displayName,
      'First\nLast',
    );
  });

  test(
    'directory bounds count 1 through 120 runes with ASCII-only trimming',
    () {
      for (final name in ['A', List.filled(120, '😀').join(), '\u00a0', '\t']) {
        expect(
          PaymentInstructorDirectoryEntry.fromJson(
            entry(1)..['display_name'] = ' $name ',
          ).displayName,
          name,
        );
      }
      expect(
        () => PaymentInstructorDirectoryEntry(
          instructorId: id(1),
          displayName: List.filled(121, 'x').join(),
        ),
        invalid,
      );
    },
  );

  test('all JSON decoders reject nonobject inputs with sanitized failure', () {
    for (final decode in <Object Function(Object?)>[
      InstructorPaymentProfile.fromJson,
      CoursePaymentInstructor.fromJson,
      PaymentInstructorDirectoryEntry.fromJson,
      PaymentInstructorCursor.fromJson,
      PaymentInstructorPage.fromJson,
    ]) {
      for (final value in [
        null,
        'private diagnostic',
        1,
        [],
        <int, Object>{1: 'value'},
      ]) {
        expect(() => decode(value), invalid);
      }
    }
    const failure = InstructorPaymentModelFailure();
    expect(failure.toString(), failure.message);
    expect(
      failure.message,
      'The instructor payment setup data could not be verified.',
    );
  });

  test('public factories enforce invariants without JSON decoding', () {
    expect(
      () => InstructorPaymentProfile(
        instructorId: id(1),
        recipientName: 'A',
        phoneNumber: 'invalid',
        methodConfiguration: InstructorPaymentMethodConfiguration.instapayOnly,
        revision: 1,
      ),
      invalid,
    );
    expect(
      () => CoursePaymentInstructor(
        courseId: id(1),
        instructorId: id(2),
        revision: 0,
      ),
      invalid,
    );
    expect(
      () => PaymentInstructorDirectoryEntry(
        instructorId: id(1),
        displayName: 'A\u0000B',
      ),
      invalid,
    );
    expect(() => PaymentInstructorCursor(instructorId: 'invalid'), invalid);
  });

  test('cursor exact shape, canonical equality/hash and UUID ordering', () {
    final a = PaymentInstructorCursor.fromJson({'instructor_id': id(1)});
    final b = PaymentInstructorCursor(instructorId: id(1).toLowerCase());
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect({a, b}, hasLength(1));
    expect(a.toJson(), {'instructor_id': id(1).toLowerCase()});
    expect(
      a.compareTo(PaymentInstructorCursor(instructorId: id(2))),
      lessThan(0),
    );
    expect(
      () => PaymentInstructorCursor.fromJson({
        'instructor_id': id(1),
        'phone_number': 'forbidden',
      }),
      invalid,
    );
    expect(() => PaymentInstructorCursor.fromJson({}), invalid);
  });

  test('empty terminal page is valid with no cursor', () {
    final result = PaymentInstructorPage.fromJson(page([]));
    expect(result.items, isEmpty);
    expect(result.hasMore, isFalse);
    expect(result.nextCursor, isNull);
  });

  test('default twenty-row page requires cursor equal to last row', () {
    final result = PaymentInstructorPage.fromJson(
      page(
        List.generate(20, (i) => entry(i + 1)),
        more: true,
        cursor: {'instructor_id': id(20)},
      ),
    );
    expect(result.items, hasLength(20));
    expect(result.nextCursor, result.items.last.cursor);
    expect(result.hasMore, isTrue);
  });

  test('limit bounds allow 1 and 50 and reject zero/negative/51', () {
    for (final limit in [1, 50]) {
      final rows = List.generate(limit, (i) => entry(i + 1));
      expect(
        PaymentInstructorPage.fromJson(page(rows), limit: limit).items,
        hasLength(limit),
      );
    }
    for (final limit in [0, -1, 51]) {
      expect(
        () => PaymentInstructorPage.fromJson(page([]), limit: limit),
        invalid,
      );
      expect(
        () => PaymentInstructorPage(
          items: [],
          hasMore: false,
          nextCursor: null,
          limit: limit,
        ),
        invalid,
      );
    }
    expect(
      () =>
          PaymentInstructorPage.fromJson(page([entry(1), entry(2)]), limit: 1),
      invalid,
    );
    expect(
      () => PaymentInstructorPage.fromJson(
        page(List.generate(21, (i) => entry(i + 1))),
      ),
      invalid,
    );
  });

  test('page rejects descending UUIDs and case-insensitive duplicates', () {
    expect(
      () => PaymentInstructorPage.fromJson(page([entry(2), entry(1)])),
      invalid,
    );
    expect(
      () => PaymentInstructorPage.fromJson(
        page([entry(1), entry(1)..['instructor_id'] = id(1).toLowerCase()]),
      ),
      invalid,
    );
  });

  test(
    'after boundary excludes equal/older IDs and accepts strictly newer',
    () {
      final after = PaymentInstructorCursor(instructorId: id(2));
      for (final value in [1, 2]) {
        expect(
          () => PaymentInstructorPage.fromJson(
            page([entry(value)]),
            after: after,
          ),
          invalid,
        );
      }
      expect(
        PaymentInstructorPage.fromJson(
          page([entry(3)]),
          after: after,
        ).items.single.instructorId,
        id(3).toLowerCase(),
      );
    },
  );

  test('has_more requires full nonempty page and matching nonnull cursor', () {
    for (final value in [
      page([], more: true),
      page([entry(1)], more: true, cursor: {'instructor_id': id(1)}),
      page([entry(1), entry(2)], more: true),
      page([entry(1), entry(2)], more: true, cursor: {'instructor_id': id(1)}),
      page([entry(1), entry(2)], more: true, cursor: {'instructor_id': id(3)}),
    ]) {
      expect(() => PaymentInstructorPage.fromJson(value, limit: 2), invalid);
    }
  });

  test('terminal page rejects any cursor and malformed envelope fields', () {
    for (final value in [
      page([entry(1)], cursor: {'instructor_id': id(1)}),
      page([])..['has_more'] = 'false',
      page([])..['items'] = {},
      page([])..remove('next_cursor'),
      page([])..['recipient_name'] = 'forbidden',
      page([entry(1)..['phone_number'] = 'forbidden']),
      page(
        [entry(1)],
        more: true,
        cursor: {'instructor_id': id(1), 'revision': 1},
      ),
    ]) {
      expect(() => PaymentInstructorPage.fromJson(value, limit: 1), invalid);
    }
  });

  test('page snapshots source list and is unmodifiable', () {
    final source = [PaymentInstructorDirectoryEntry.fromJson(entry(1))];
    final result = PaymentInstructorPage(
      items: source,
      hasMore: false,
      nextCursor: null,
    );
    source.clear();
    expect(result.items, hasLength(1));
    expect(() => result.items.clear(), throwsUnsupportedError);
    expect(
      () =>
          result.items[0] = PaymentInstructorDirectoryEntry.fromJson(entry(2)),
      throwsUnsupportedError,
    );
    final cursorJson = result.items.single.cursor.toJson()
      ..['instructor_id'] = id(3);
    expect(cursorJson['instructor_id'], id(3));
    expect(result.items.single.instructorId, id(1).toLowerCase());
  });
}
