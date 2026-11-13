import 'dart:typed_data';

/// One H.264 access unit reconstructed as an Annex-B byte sequence.
///
/// The demo asset is encoded with AUD NAL units, so access-unit boundaries are
/// explicit. This parser is intentionally scoped to that controlled asset; it
/// is not a general-purpose H.264 bitstream parser.
class H264AccessUnit {
  final Uint8List data;
  final bool isKeyFrame;

  const H264AccessUnit({required this.data, required this.isKeyFrame});
}

class H264AnnexBParser {
  const H264AnnexBParser._();

  static const List<int> _startCode = <int>[0, 0, 0, 1];

  /// Splits an AUD-delimited Annex-B stream into complete H.264 access units.
  ///
  /// Parameter-set NAL units before the first AUD are retained with the first
  /// access unit. Every returned access unit contains at least one VCL NAL.
  /// The first access unit must be an IDR so a newly connected decoder can
  /// start without depending on frames that it has not received.
  static List<H264AccessUnit> parse(Uint8List bytes) {
    final List<Uint8List> nalUnits = _splitNalUnits(bytes);
    final List<H264AccessUnit> accessUnits = <H264AccessUnit>[];
    final List<Uint8List> current = <Uint8List>[];
    bool currentHasVcl = false;
    bool currentHasIdr = false;
    bool sawAccessUnitDelimiter = false;

    void finishCurrent() {
      if (!currentHasVcl) {
        current.clear();
        currentHasIdr = false;
        return;
      }

      int totalLength = 0;
      for (final Uint8List nalUnit in current) {
        totalLength += _startCode.length + nalUnit.length;
      }

      final Uint8List accessUnitData = Uint8List(totalLength);
      int offset = 0;
      for (final Uint8List nalUnit in current) {
        accessUnitData.setRange(offset, offset + _startCode.length, _startCode);
        offset += _startCode.length;
        accessUnitData.setRange(offset, offset + nalUnit.length, nalUnit);
        offset += nalUnit.length;
      }

      accessUnits.add(
        H264AccessUnit(data: accessUnitData, isKeyFrame: currentHasIdr),
      );
      current.clear();
      currentHasVcl = false;
      currentHasIdr = false;
    }

    for (final Uint8List nalUnit in nalUnits) {
      final int nalUnitType = nalUnit[0] & 0x1f;
      if (nalUnitType == 9) {
        sawAccessUnitDelimiter = true;
        if (currentHasVcl) {
          finishCurrent();
        }
      }

      current.add(nalUnit);
      if (nalUnitType == 1 || nalUnitType == 5) {
        currentHasVcl = true;
      }
      if (nalUnitType == 5) {
        currentHasIdr = true;
      }
    }

    finishCurrent();

    if (!sawAccessUnitDelimiter) {
      throw const FormatException(
        'The demo H.264 stream must contain AUD NAL units.',
      );
    }
    if (accessUnits.isEmpty) {
      throw const FormatException('The H.264 stream contains no video frames.');
    }
    if (!accessUnits.first.isKeyFrame) {
      throw const FormatException(
        'The first H.264 access unit must contain an IDR frame.',
      );
    }

    return List<H264AccessUnit>.unmodifiable(accessUnits);
  }

  static List<Uint8List> _splitNalUnits(Uint8List bytes) {
    final List<_StartCodePosition> startCodes = <_StartCodePosition>[];
    int index = 0;

    while (index + 2 < bytes.length) {
      if (bytes[index] != 0 || bytes[index + 1] != 0) {
        index++;
        continue;
      }

      if (index + 3 < bytes.length &&
          bytes[index + 2] == 0 &&
          bytes[index + 3] == 1) {
        startCodes.add(_StartCodePosition(index, 4));
        index += 4;
        continue;
      }

      if (bytes[index + 2] == 1) {
        startCodes.add(_StartCodePosition(index, 3));
        index += 3;
        continue;
      }

      index++;
    }

    if (startCodes.isEmpty) {
      throw const FormatException('No Annex-B start codes were found.');
    }

    for (int leading = 0; leading < startCodes.first.offset; leading++) {
      if (bytes[leading] != 0) {
        throw const FormatException(
          'Unexpected data before the first Annex-B start code.',
        );
      }
    }

    final List<Uint8List> nalUnits = <Uint8List>[];
    for (int i = 0; i < startCodes.length; i++) {
      final _StartCodePosition start = startCodes[i];
      final int nalStart = start.offset + start.length;
      int nalEnd = i + 1 < startCodes.length
          ? startCodes[i + 1].offset
          : bytes.length;

      // Annex-B permits trailing_zero_8bits after an RBSP. They are not part
      // of the NAL unit and can be removed without changing the bitstream.
      while (nalEnd > nalStart && bytes[nalEnd - 1] == 0) {
        nalEnd--;
      }

      if (nalEnd > nalStart) {
        nalUnits.add(Uint8List.fromList(bytes.sublist(nalStart, nalEnd)));
      }
    }

    if (nalUnits.isEmpty) {
      throw const FormatException('The Annex-B stream contains no NAL units.');
    }

    return nalUnits;
  }
}

class _StartCodePosition {
  final int offset;
  final int length;

  const _StartCodePosition(this.offset, this.length);
}
