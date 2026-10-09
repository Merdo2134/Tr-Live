import 'package:flutter/material.dart';

/// Uygulamanın tek renk ve stil kaynağı. Renkleri değiştirmek için yalnızca bu dosyayı düzenleyin.
class Pal {
  static const bg = Color(0xFF0A1424); // koyu lacivert zemin
  static const surface = Color(0xFF0F1D31); // kart ve çubuk yüzeyi
  static const surfaceHi = Color(0xFF14263D);
  static const outline = Color(0xFF1C5873); // ince turkuaz çerçeve
  static const cyan = Color(0xFF1FD6F5); // ana vurgu
  static const pink = Color(0xFFFF4F9A); // canlı / rozet
  static const amber = Color(0xFFFFC43D); // bildirim / altın
  static const purple = Color(0xFFB45CFF);
  static const red = Color(0xFFE5483D);
  static const text = Color(0xFFEAF4FA);
  static const textDim = Color(0xFF8AA5BB); // koyu zeminlerde en az 4.5:1 kontrast (WCAG AA)
  static const green = Color(0xFF22C55E); // onay / başarı
  static const orange = Color(0xFFFF7A18); // sıcak vurgu (canlı rozet, oda kartı)
  static const gold = Color(0xFFFFD54F); // Coin
  static const onBright = Color(0xFF00212A); // açık renkli zeminlerin üstündeki yazı (cyan, altın, yeşil)
}

/// Boşluk ölçüleri (dp). Ekranlarda bu değerler kullanılır; elle sayı yazılmaz.
class Gap {
  static const xs = 4.0;
  static const s = 8.0;
  static const m = 12.0;
  static const l = 16.0;
  static const xl = 24.0;
}

/// Köşe yuvarlaklıkları (dp).
class Rad {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
}

/// Material 3 yazı ölçeği (sp / satır yüksekliği). Android'in standardı; sosyal uygulamalarda gövde 14-16, etiket 11-12, başlık 16-22 kullanılır.
TextTheme _textTheme() {
  TextStyle t(double size, double line, FontWeight w, [double spacing = 0]) => TextStyle(fontSize: size, height: line / size, fontWeight: w, letterSpacing: spacing, color: Pal.text);
  return TextTheme(
    displayLarge: t(57, 64, FontWeight.w400, -0.25),
    displayMedium: t(45, 52, FontWeight.w400),
    displaySmall: t(36, 44, FontWeight.w400),
    headlineLarge: t(32, 40, FontWeight.w600),
    headlineMedium: t(28, 36, FontWeight.w600),
    headlineSmall: t(24, 32, FontWeight.w600),
    titleLarge: t(22, 28, FontWeight.w700),
    titleMedium: t(16, 24, FontWeight.w600, 0.15),
    titleSmall: t(14, 20, FontWeight.w600, 0.1),
    bodyLarge: t(16, 24, FontWeight.w400, 0.5),
    bodyMedium: t(14, 20, FontWeight.w400, 0.25),
    bodySmall: t(12, 16, FontWeight.w400, 0.4),
    labelLarge: t(14, 20, FontWeight.w600, 0.1),
    labelMedium: t(12, 16, FontWeight.w600, 0.5),
    labelSmall: t(11, 16, FontWeight.w600, 0.5),
  );
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: Pal.cyan, brightness: Brightness.dark).copyWith(
    primary: Pal.cyan,
    onPrimary: const Color(0xFF00212A),
    secondary: Pal.pink,
    tertiary: Pal.amber,
    surface: Pal.surface,
    onSurface: Pal.text,
    surfaceContainerHighest: Pal.surfaceHi,
    primaryContainer: Pal.surfaceHi,
    onPrimaryContainer: Pal.text,
    outline: Pal.outline,
    error: Pal.red,
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    textTheme: _textTheme(),
    // Dokunma hedefi en az 48x48 dp (Android erişilebilirlik standardı).
    materialTapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.standard,
    scaffoldBackgroundColor: Pal.bg,
    canvasColor: Pal.bg,
    dividerColor: Pal.outline.withValues(alpha: 0.5),
    appBarTheme: const AppBarTheme(
      backgroundColor: Pal.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(color: Pal.text, fontSize: 20, fontWeight: FontWeight.w700),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Pal.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Colors.transparent,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: s.contains(WidgetState.selected) ? Pal.cyan : Pal.textDim, size: 28)),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(fontSize: 11, color: s.contains(WidgetState.selected) ? Pal.cyan : Pal.textDim)),
    ),
    cardTheme: CardThemeData(color: Pal.surface, surfaceTintColor: Colors.transparent, shape: shape, margin: const EdgeInsets.symmetric(vertical: 5)),
    dialogTheme: DialogThemeData(backgroundColor: Pal.surface, surfaceTintColor: Colors.transparent, shape: shape),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Pal.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: Pal.surfaceHi, contentTextStyle: const TextStyle(color: Pal.text), shape: shape),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Pal.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Pal.outline)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Pal.outline)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Pal.cyan, width: 1.6)),
      hintStyle: const TextStyle(color: Pal.textDim),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(backgroundColor: Pal.cyan, foregroundColor: const Color(0xFF00212A), shape: shape, minimumSize: const Size(64, 48)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(foregroundColor: Pal.cyan, side: const BorderSide(color: Pal.outline), shape: shape, minimumSize: const Size(64, 48))),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: Pal.cyan, minimumSize: const Size(48, 48))),
    floatingActionButtonTheme: FloatingActionButtonThemeData(backgroundColor: Pal.cyan, foregroundColor: const Color(0xFF00212A), shape: shape),
    chipTheme: ChipThemeData(backgroundColor: Pal.surface, side: const BorderSide(color: Pal.outline), labelStyle: const TextStyle(color: Pal.text), shape: const StadiumBorder()),
    listTileTheme: const ListTileThemeData(iconColor: Pal.cyan, textColor: Pal.text),
    switchTheme: SwitchThemeData(thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Pal.cyan : Pal.textDim)),
    tabBarTheme: const TabBarThemeData(labelColor: Pal.cyan, unselectedLabelColor: Pal.textDim, indicatorColor: Pal.cyan),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: Pal.cyan),
  );
}

/// Ekran genişliğine göre ölçüler: telefon, katlanabilir/küçük tablet ve tablet için tek kural.
class Resp {
  static double width(BuildContext c) => MediaQuery.sizeOf(c).width;

  /// Oda kartı sütunu: dar telefon 2, geniş telefon/katlanabilir 3, tablet 4-5.
  static int roomColumns(double w) => w < 600 ? 2 : (w < 840 ? 3 : (w < 1100 ? 4 : 5));

  // Android pencere boyutu sınıfları (dp): compact < 600, medium 600-839, expanded 840-1199, large ≥ 1200.
  static bool isCompact(double w) => w < 600;
  static bool isMedium(double w) => w >= 600 && w < 840;

  /// Ekran kenar boşluğu: telefonda 16, tablette 24, geniş ekranda 32 (Material düzen ızgarası).
  static double margin(double w) => w < 600 ? 16 : (w < 1200 ? 24 : 32);

  /// Uygulama içeriğinin en geniş hâli; geniş ekranlarda ortalanır.
  static const maxContent = 1200.0;
}

/// Tüm uygulamayı saran kap: yazı ölçeğini sınırlar, geniş ekranda içeriği ortalar.
Widget appFrame(BuildContext context, Widget? child) {
  final mq = MediaQuery.of(context);
  final scale = mq.textScaler.clamp(minScaleFactor: 0.85, maxScaleFactor: 1.3);
  return MediaQuery(
    data: mq.copyWith(textScaler: scale),
    child: ColoredBox(
      color: Pal.bg,
      child: SafeArea(top: false, left: false, right: false, child: Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: Resp.maxContent), child: child))),
    ),
  );
}
