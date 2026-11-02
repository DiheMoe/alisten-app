import 'dart:math';
import 'dart:typed_data';

List<int> shortWav({int durationMs = 1000, int sampleRate = 8000}) {
  final sampleCount = durationMs * sampleRate ~/ 1000;
  final dataBytes = ByteData(sampleCount * 2);
  for (var i = 0; i < sampleCount; i++) {
    final sample = (sin(2 * pi * 440 * i / sampleRate) * 8000).round();
    dataBytes.setInt16(i * 2, sample, Endian.little);
  }
  final bytes = BytesBuilder();
  bytes.add('RIFF'.codeUnits);
  bytes.add(_uint32(36 + dataBytes.lengthInBytes));
  bytes.add('WAVEfmt '.codeUnits);
  bytes.add(_uint32(16));
  bytes.add(_uint16(1));
  bytes.add(_uint16(1));
  bytes.add(_uint32(sampleRate));
  bytes.add(_uint32(sampleRate * 2));
  bytes.add(_uint16(2));
  bytes.add(_uint16(16));
  bytes.add('data'.codeUnits);
  bytes.add(_uint32(dataBytes.lengthInBytes));
  bytes.add(dataBytes.buffer.asUint8List());
  return bytes.toBytes();
}

List<int> _uint16(int value) {
  return Uint8List(2)..buffer.asByteData().setUint16(0, value, Endian.little);
}

List<int> _uint32(int value) {
  return Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.little);
}
