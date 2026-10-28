import 'dart:convert';
import 'dart:typed_data';

import 'material_models.dart' show MaterialKind;

/// Operational selection bound, not a business requirement or security scan.
const maxSelectedMaterialFileBytes = 20 * 1024 * 1024;

final class MaterialFileSelectionFailure implements Exception {
  const MaterialFileSelectionFailure();
  String get message =>
      'Choose a valid PDF or UTF-8 TXT file, no larger than 20 MiB.';
  @override
  String toString() => message;
}

void _require(bool valid) {
  if (!valid) throw const MaterialFileSelectionFailure();
}

bool _control(int code) => code < 32 || (code >= 127 && code <= 159);

/// An owned in-memory selection only: no path, upload, readiness, publication or
/// delivery capability. Header/tail and UTF-8 checks are conservative format
/// screening, not full PDF parsing, malware detection or safe-to-open evidence.
final class SelectedMaterialFile {
  factory SelectedMaterialFile.fromBytes({
    required MaterialKind kind,
    required String fileName,
    required List<int> bytes,
  }) {
    try {
      _require(kind == MaterialKind.pdf || kind == MaterialKind.file);
      _require(
        fileName.isNotEmpty &&
            fileName.runes.length <= 160 &&
            !fileName.contains('/') &&
            !fileName.contains('\\') &&
            !fileName.runes.any(_control),
      );
      final dot = fileName.lastIndexOf('.');
      _require(dot > 0 && fileName.substring(0, dot).trim().isNotEmpty);
      final extension = fileName.substring(dot + 1).toLowerCase();
      _require(
        extension == 'pdf' || (kind == MaterialKind.file && extension == 'txt'),
      );
      final length = bytes.length;
      _require(length > 0 && length <= maxSelectedMaterialFileBytes);
      final copy = Uint8List(length);
      for (var i = 0; i < length; ++i) {
        final value = bytes[i];
        // Uint8List conversion otherwise silently truncates out-of-range ints.
        _require(value >= 0 && value <= 255);
        copy[i] = value;
      }
      _require(bytes.length == length);
      if (extension == 'pdf') {
        _validatePdf(copy);
      } else {
        final text = utf8.decode(copy, allowMalformed: false);
        _require(
          !text.runes.any(
            (code) => _control(code) && code != 9 && code != 10 && code != 13,
          ),
        );
      }
      return SelectedMaterialFile._(
        kind,
        fileName,
        extension,
        extension == 'pdf' ? 'application/pdf' : 'text/plain',
        copy.asUnmodifiableView(),
      );
    } catch (_) {
      // Never expose parser exceptions, filenames, paths or contents.
      throw const MaterialFileSelectionFailure();
    }
  }

  const SelectedMaterialFile._(
    this.kind,
    this.fileName,
    this.extension,
    this.contentType,
    this.bytes,
  );
  final MaterialKind kind;
  final String fileName;

  /// Lowercase extension without the leading dot.
  final String extension;
  final String contentType;

  /// Independent owned bytes, including an unmodifiable buffer/view.
  final Uint8List bytes;
  int get byteLength => bytes.lengthInBytes;
}

void _validatePdf(Uint8List bytes) {
  _require(bytes.length >= 14);
  _require(
    bytes[0] == 37 &&
        bytes[1] == 80 &&
        bytes[2] == 68 &&
        bytes[3] == 70 &&
        bytes[4] == 45,
  );
  // Recognized PDF version line: 1.0–1.7 or 2.0, immediately at byte zero.
  _require(
    bytes[6] == 46 &&
        ((bytes[5] == 49 && bytes[7] >= 48 && bytes[7] <= 55) ||
            (bytes[5] == 50 && bytes[7] == 48)) &&
        (bytes[8] == 10 || bytes[8] == 13),
  );
  var end = bytes.length;
  // PDF whitespace is byte-defined; do not decode arbitrary binary PDF data.
  while (end > 0 && _pdfWhitespace(bytes[end - 1])) {
    --end;
  }
  _require(end >= 14);
  const marker = [37, 37, 69, 79, 70]; // %%EOF
  final start = end - marker.length;
  _require(bytes[start - 1] == 10 || bytes[start - 1] == 13);
  for (var i = 0; i < marker.length; ++i) {
    _require(bytes[start + i] == marker[i]);
  }
}

bool _pdfWhitespace(int byte) =>
    byte == 0 ||
    byte == 9 ||
    byte == 10 ||
    byte == 12 ||
    byte == 13 ||
    byte == 32;
