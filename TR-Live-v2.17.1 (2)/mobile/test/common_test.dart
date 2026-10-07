import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tr_live/services/api.dart';
import 'package:tr_live/screens/agency_screen.dart' show periodTitle;
import 'package:tr_live/screens/ludo_screen.dart' show tokenCenter;
import 'package:tr_live/widgets/common.dart';

void main() {
  test('fmtNumber binlik ayraç ekler', () {
    expect(fmtNumber('1234567'), '1.234.567');
    expect(fmtNumber(1000), '1.000');
    expect(fmtNumber('-5000'), '-5.000');
    expect(fmtNumber(null), '0');
    expect(fmtNumber('abc'), 'abc');
  });

  test('fmtMoney kuruşu para birimine çevirir', () {
    expect(fmtMoney('5000'), '50,00 USD');
    expect(fmtMoney(123456, 'EUR'), '1.234,56 EUR');
    expect(fmtMoney(null), '0,00 USD');
  });

  test('periodTitle', () {
    expect(periodTitle('2026-10'), '2026-10');
    expect(periodTitle('W2026-09-28'), 'Hafta 2026-09-28');
  });

  test('Ludo taş konumları sunucu yoluyla uyumlu', () {
    // Kırmızı başlangıç (progress 0) → (1,6) hücresi merkezi
    expect(tokenCenter(0, 0, 0), const Offset(1.5, 6.5));
    // Yeşil başlangıç küresel kare 13 → (8,1)
    expect(tokenCenter(1, 0, 0), const Offset(8.5, 1.5));
    // Sarı başlangıç küresel kare 26 → (13,8)
    expect(tokenCenter(2, 0, 0), const Offset(13.5, 8.5));
    // Mavi başlangıç küresel kare 39 → (6,13)
    expect(tokenCenter(3, 0, 0), const Offset(6.5, 13.5));
    // Kırmızı ev sütunu ilk hücre (progress 51) → (1,7)
    expect(tokenCenter(0, 51, 0), const Offset(1.5, 7.5));
    // Kırmızı 50 → son ortak yol karesi (0,7)'den önceki (0,6)? küresel 50
    expect(tokenCenter(0, 50, 0), const Offset(0.5, 7.5));
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
