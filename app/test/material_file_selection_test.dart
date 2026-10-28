import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:summit_academy/content/material_file_selection.dart';
import 'package:summit_academy/content/material_models.dart' show MaterialKind;

List<int> pdf({String version = '1.7', String ending = '\n%%EOF\n'}) => [
  ...ascii.encode('%PDF-$version\n'),
  0,
  255,
  128,
  ...ascii.encode(ending),
];
SelectedMaterialFile select(
  List<int> bytes, {
  String name = 'Example.pdf',
  MaterialKind kind = MaterialKind.pdf,
}) => SelectedMaterialFile.fromBytes(kind: kind, fileName: name, bytes: bytes);
final invalid = throwsA(isA<MaterialFileSelectionFailure>());

void main() {
  test('PDF selection exposes normalized extension, MIME and exact length', () {
    final bytes = pdf();
    final result = select(bytes, name: 'Example.PdF');
    expect(result.kind, MaterialKind.pdf);
    expect(result.fileName, 'Example.PdF');
    expect(result.extension, 'pdf');
    expect(result.contentType, 'application/pdf');
    expect(result.byteLength, bytes.length);
    expect(result.bytes, bytes);
  });

  test('file kind accepts only screened PDF and UTF-8 TXT', () {
    expect(select(pdf(), kind: MaterialKind.file).extension, 'pdf');
    final result = select(
      utf8.encode('Example text'),
      name: 'Example.TXT',
      kind: MaterialKind.file,
    );
    expect(result.extension, 'txt');
    expect(result.contentType, 'text/plain');
    expect(result.kind, MaterialKind.file);
  });

  test('video/link/assignment kinds are refused even with valid PDF bytes', () {
    for (final kind in [
      MaterialKind.video,
      MaterialKind.link,
      MaterialKind.assignment,
    ]) {
      expect(() => select(pdf(), kind: kind), invalid);
    }
  });

  test('PDF kind cannot accept TXT', () {
    expect(
      () => select(utf8.encode('Example text'), name: 'Example.txt'),
      invalid,
    );
  });

  test(
    'unsupported image/Office/archive/video/script extensions are rejected',
    () {
      for (final extension in [
        'png',
        'jpg',
        'jpeg',
        'doc',
        'docx',
        'xlsx',
        'zip',
        '7z',
        'mp4',
        'js',
        'html',
        'exe',
      ]) {
        expect(
          () => select(
            pdf(),
            name: 'Example.$extension',
            kind: MaterialKind.file,
          ),
          invalid,
        );
      }
    },
  );

  test('empty bytes are rejected for both accepted formats', () {
    expect(() => select([]), invalid);
    expect(
      () => select([], kind: MaterialKind.file, name: 'Empty.txt'),
      invalid,
    );
  });

  test('one byte TXT is accepted at lower size boundary', () {
    expect(select([65], kind: MaterialKind.file, name: 'A.txt').byteLength, 1);
  });

  test(
    '20 MiB operational boundary is accepted exactly and excess is rejected',
    () {
      expect(maxSelectedMaterialFileBytes, 20971520);
      final bytes = Uint8List(maxSelectedMaterialFileBytes);
      bytes.setRange(0, 9, ascii.encode('%PDF-1.7\n'));
      bytes.setRange(bytes.length - 6, bytes.length, ascii.encode('\n%%EOF'));
      expect(select(bytes).byteLength, maxSelectedMaterialFileBytes);
      expect(
        () => select(Uint8List(maxSelectedMaterialFileBytes + 1)),
        invalid,
      );
    },
  );

  test('integer values are range checked before any Uint8 truncation', () {
    for (final byte in [-1, 256, 511, 1000000]) {
      final bytes = pdf()..[10] = byte;
      expect(() => select(bytes), invalid);
    }
  });

  test(
    'copy owns data independently from caller List and typed-buffer aliases',
    () {
      final source = pdf();
      final selected = select(source);
      source[0] = 0;
      source.clear();
      expect(selected.bytes[0], 37);
      final typed = Uint8List.fromList(pdf());
      final alias = typed.buffer.asUint8List();
      final other = select(typed);
      alias[0] = 0;
      expect(other.bytes[0], 37);
    },
  );

  test('exposed bytes and buffer-derived views cannot mutate selection', () {
    final selected = select(pdf());
    expect(() => selected.bytes[0] = 0, throwsUnsupportedError);
    expect(() => selected.bytes.setAll(0, [0]), throwsUnsupportedError);
    expect(
      () => selected.bytes.buffer.asUint8List()[0] = 0,
      throwsUnsupportedError,
    );
    expect(
      () => Uint8List.sublistView(selected.bytes)[0] = 0,
      throwsUnsupportedError,
    );
    expect(selected.bytes[0], 37);
  });

  test('filename allows Unicode and spaces and measures at most 160 runes', () {
    final name = '${List.filled(156, '😀').join()}.pdf';
    expect(select(pdf(), name: name).fileName, name);
    expect(select(pdf(), name: 'Example course notes.pdf').extension, 'pdf');
    expect(() => select(pdf(), name: 'x$name'), invalid);
  });

  test('filename must be basename, not path, traversal or URI', () {
    for (final name in [
      '/tmp/A.pdf',
      '../A.pdf',
      'folder/A.pdf',
      r'C:\A.pdf',
      r'folder\A.pdf',
      'content://A.pdf',
      'file:///A.pdf',
    ]) {
      expect(() => select(pdf(), name: name), invalid);
    }
  });

  test('filename rejects all C0/C1 controls including NUL and DEL', () {
    for (final code in [
      ...List.generate(32, (i) => i),
      ...List.generate(33, (i) => i + 127),
    ]) {
      expect(
        () => select(pdf(), name: 'A${String.fromCharCode(code)}.pdf'),
        invalid,
      );
    }
  });

  test(
    'missing extension, empty/blank stem and disguised suffix are rejected',
    () {
      for (final name in [
        '',
        ' ',
        'A',
        '.pdf',
        ' .pdf',
        'A.pdf ',
        'A.pdf.exe',
        'A.pdf.',
        'A.',
      ]) {
        expect(() => select(pdf(), name: name), invalid);
      }
    },
  );

  test('known PDF versions and CR/LF header lines pass screening', () {
    for (final version in ['1.0', '1.7', '2.0']) {
      expect(select(pdf(version: version)).extension, 'pdf');
    }
    expect(select(ascii.encode('%PDF-1.7\r\n%%EOF')).extension, 'pdf');
  });

  test('PDF requires header at byte zero and recognized version line', () {
    for (final text in [
      'garbage\n%PDF-1.7\n%%EOF',
      '%PDF-9.9\n%%EOF',
      '%PDF-1.8\n%%EOF',
      '%PDF-2.1\n%%EOF',
      '%PDF-1.7garbage\n%%EOF',
      '%PDF-\n%%EOF',
    ]) {
      expect(() => select(ascii.encode(text)), invalid);
    }
  });

  test('PDF requires line-start EOF marker at trimmed tail', () {
    for (final ending in [
      '',
      '\n%%EO',
      '\n%%EOFgarbage',
      '\n%%EOF\ntrailing',
      '%%EOF\n',
    ]) {
      expect(() => select(pdf(ending: ending)), invalid);
    }
    expect(select(pdf(ending: '\r%%EOF\x00\t\r\n\x0c ')).extension, 'pdf');
  });

  test('PDF is binary and must not be decoded as UTF-8 text', () {
    final selected = select(pdf());
    expect(selected.bytes, containsAllInOrder([0, 255, 128]));
  });

  test('TXT supports Unicode, LF/CR/TAB and preserves original bytes', () {
    final bytes = utf8.encode('Résumé هندسة 😀\tNotes\r\nNext\n');
    expect(
      select(bytes, kind: MaterialKind.file, name: 'Notes.txt').bytes,
      bytes,
    );
  });

  test('TXT rejects malformed/truncated/overlong/surrogate UTF-8', () {
    for (final bytes in [
      [255],
      [128],
      [195],
      [195, 40],
      [192, 128],
      [237, 160, 128],
      [244, 144, 128, 128],
    ]) {
      expect(
        () => select(bytes, kind: MaterialKind.file, name: 'Notes.txt'),
        invalid,
      );
    }
  });

  test('TXT rejects NUL and all other C0/C1 controls except LF/CR/TAB', () {
    for (final code in [
      ...List.generate(32, (i) => i),
      ...List.generate(33, (i) => i + 127),
    ]) {
      if ([9, 10, 13].contains(code)) continue;
      expect(
        () => select(
          utf8.encode('A${String.fromCharCode(code)}B'),
          kind: MaterialKind.file,
          name: 'Notes.txt',
        ),
        invalid,
      );
    }
  });

  test('PDF extension rejects text and TXT rejects binary image/PDF bytes', () {
    expect(() => select(utf8.encode('Not a PDF')), invalid);
    expect(
      () => select(pdf(), name: 'Notes.txt', kind: MaterialKind.file),
      invalid,
    );
    expect(
      () => select(
        [137, 80, 78, 71, 13, 10, 26, 10],
        name: 'Notes.txt',
        kind: MaterialKind.file,
      ),
      invalid,
    );
  });

  test(
    'failure message is constant and never includes filename or contents',
    () {
      try {
        select(utf8.encode('PRIVATE CONTENT'), name: '/private/SECRET.pdf');
        fail('Expected rejection');
      } on MaterialFileSelectionFailure catch (error) {
        expect(error.toString(), const MaterialFileSelectionFailure().message);
        expect(
          error.message,
          'Choose a valid PDF or UTF-8 TXT file, no larger than 20 MiB.',
        );
      }
    },
  );
}
