import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tr_live/services/api.dart';
import 'package:tr_live/widgets/common.dart';

void main() {
  test('fmtNumber binlik ayraç ekler', () {
    expect(fmtNumber('1234567'), '1.234.567');
    expect(fmtNumber(1000), '1.000');
    expect(fmtNumber('-5000'), '-5.000');
    expect(fmtNumber(null), '0');
    expect(fmtNumber('abc'), 'abc');
  });

  test('fmtDuration saat ve dakika', () {
    expect(fmtDuration(59), '0 dk');
    expect(fmtDuration(3600 + 5 * 60), '1 sa 5 dk');
  });

  test('parseColor geçerli ve geçersiz', () {
    expect(parseColor('#FFD700'), const Color(0xFFFFD700));
    expect(parseColor('FFD700'), isNull);
    expect(parseColor(null), isNull);
    expect(parseColor('#GGGGGG'), isNull);
  });

  test('listOf / mapOf güvenli dönüşüm', () {
    expect(listOf(null), isEmpty);
    expect(listOf([1, {'a': 1}]), [
      {'a': 1}
    ]);
    expect(mapOf('x'), isNull);
    expect(mapOf({'a': 1}), {'a': 1});
  });

  test('absoluteUrl göreli adresi tamamlar', () {
    expect(Api.absoluteUrl(null), isNull);
    expect(Api.absoluteUrl('https://a.com/x.png'), 'https://a.com/x.png');
    expect(Api.absoluteUrl('/uploads/x.png'), '${Api.baseUrl}/uploads/x.png');
  });
}
