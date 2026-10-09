import 'package:flutter/cupertino.dart' show CupertinoLocalizations, DefaultCupertinoLocalizations;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Ek paket gerektirmeyen Türkçe Material metinleri (geri/menü ipuçları, kopyala/yapıştır, tarih seçici).
class TrMaterialLocalizations extends DefaultMaterialLocalizations {
  const TrMaterialLocalizations();

  static const LocalizationsDelegate<MaterialLocalizations> delegate = _TrMaterialDelegate();

  /// iOS bileşenleri için varsayılan (İngilizce) metinler; yalnızca 'tr' yerelinde eksik kalmasın diye.
  static const LocalizationsDelegate<CupertinoLocalizations> cupertinoDelegate = _TrCupertinoDelegate();

  static const _months = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];
  static const _days = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'];
  static const _shortDays = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];

  @override
  String get backButtonTooltip => 'Geri';
  @override
  String get closeButtonTooltip => 'Kapat';
  @override
  String get deleteButtonTooltip => 'Sil';
  @override
  String get showMenuTooltip => 'Menüyü göster';
  @override
  String get nextMonthTooltip => 'Sonraki ay';
  @override
  String get previousMonthTooltip => 'Önceki ay';
  @override
  String get okButtonLabel => 'TAMAM';
  @override
  String get cancelButtonLabel => 'VAZGEÇ';
  @override
  String get closeButtonLabel => 'KAPAT';
  @override
  String get continueButtonLabel => 'DEVAM';
  @override
  String get copyButtonLabel => 'Kopyala';
  @override
  String get cutButtonLabel => 'Kes';
  @override
  String get pasteButtonLabel => 'Yapıştır';
  @override
  String get selectAllButtonLabel => 'Tümünü seç';
  @override
  String get searchFieldLabel => 'Ara';
  @override
  String get datePickerHelpText => 'TARİH SEÇ';
  @override
  String get modalBarrierDismissLabel => 'Kapat';
  @override
  String get refreshIndicatorSemanticLabel => 'Yenile';
  @override
  int get firstDayOfWeekIndex => 1; // Pazartesi
  @override
  List<String> get narrowWeekdays => const ['P', 'P', 'S', 'Ç', 'P', 'C', 'C'];
  @override
  String formatMonthYear(DateTime date) => '${_months[date.month - 1]} ${date.year}';
  @override
  String formatMediumDate(DateTime date) => '${date.day} ${_months[date.month - 1].substring(0, 3)} ${_shortDays[date.weekday - 1]}';
  @override
  String formatFullDate(DateTime date) => '${date.day} ${_months[date.month - 1]} ${date.year} ${_days[date.weekday - 1]}';
}

class _TrMaterialDelegate extends LocalizationsDelegate<MaterialLocalizations> {
  const _TrMaterialDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'tr';

  @override
  Future<MaterialLocalizations> load(Locale locale) => SynchronousFuture<MaterialLocalizations>(const TrMaterialLocalizations());

  @override
  bool shouldReload(_TrMaterialDelegate old) => false;
}

class _TrCupertinoDelegate extends LocalizationsDelegate<CupertinoLocalizations> {
  const _TrCupertinoDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'tr';

  @override
  Future<CupertinoLocalizations> load(Locale locale) => SynchronousFuture<CupertinoLocalizations>(const DefaultCupertinoLocalizations());

  @override
  bool shouldReload(_TrCupertinoDelegate old) => false;
}
