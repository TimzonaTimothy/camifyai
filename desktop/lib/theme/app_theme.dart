import 'package:flutter/material.dart';

class AppColors {
  static const bg = Color(0xFF101313);
  static const surface = Color(0xFF141A17);
  static const card = Color(0xFF191E1D);
  static const cardHover = Color(0xFF232C26);
  static const border = Color(0xFF303936);
  static const accent = Color(0xFFC9EF9C);
  static const accentLight = Color(0xFFDEF6C3);
  static const accentDim = Color(0xFF253421);
  static const accentGlow = Color(0x40C9EF9C);
  static const onAccent = Color(0xFF162015);
  static const success = Color(0xFFA9D8AE);
  static const successDim = Color(0xFF203328);
  static const warning = Color(0xFFE3C286);
  static const warningDim = Color(0xFF332C20);
  static const error = Color(0xFFF1A49C);
  static const errorDim = Color(0xFF352421);
  static const textPrimary = Color(0xFFF1F5EE);
  static const textSecondary = Color(0xFFA0ACA6);
  static const textMuted = Color(0xFF86958C);
}

class AppTheme {
  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: AppColors.accent,
      onPrimary: AppColors.onAccent,
      secondary: AppColors.accentLight,
      onSecondary: AppColors.onAccent,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      error: AppColors.error,
      onError: AppColors.onAccent,
      outline: AppColors.border,
    );
    final base = ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorScheme: scheme,
        fontFamily: 'Inter');
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bg,
      primaryColor: AppColors.accent,
      textTheme: base.textTheme
          .apply(
            bodyColor: AppColors.textSecondary,
            displayColor: AppColors.textPrimary,
          )
          .copyWith(
            displayLarge: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w500,
                letterSpacing: -1.4,
                color: AppColors.textPrimary),
            displayMedium: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.9,
                color: AppColors.textPrimary),
            titleLarge: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.5,
                color: AppColors.textPrimary),
            titleMedium: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary),
            bodyLarge: const TextStyle(
                fontSize: 14, height: 1.6, color: AppColors.textPrimary),
            bodyMedium: const TextStyle(
                fontSize: 13, height: 1.6, color: AppColors.textSecondary),
            labelSmall: const TextStyle(
                fontSize: 11, letterSpacing: 0.3, color: AppColors.textMuted),
          )
          .apply(fontFamily: 'Inter'),
      appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.bg,
          foregroundColor: AppColors.textPrimary,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: false),
      cardTheme: CardThemeData(
          color: AppColors.card,
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: AppColors.border))),
      dividerTheme:
          const DividerThemeData(color: AppColors.border, thickness: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.accent, width: 1.5)),
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        labelStyle:
            const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.onAccent,
        elevation: 0,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
        textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600),
      )),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        side: const BorderSide(color: AppColors.border),
        minimumSize: const Size(48, 46),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      )),
      textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
              foregroundColor: AppColors.accent,
              textStyle:
                  const TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600))),
      dialogTheme: DialogThemeData(
          backgroundColor: AppColors.card,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: const BorderSide(color: AppColors.border))),
      bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: AppColors.card,
          surfaceTintColor: Colors.transparent,
          showDragHandle: true),
      snackBarTheme: SnackBarThemeData(
          backgroundColor: AppColors.cardHover,
          contentTextStyle: const TextStyle(color: AppColors.textPrimary),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      tabBarTheme: const TabBarThemeData(
          labelColor: AppColors.accent,
          unselectedLabelColor: AppColors.textMuted,
          indicatorColor: AppColors.accent,
          dividerColor: Colors.transparent),
      iconTheme: const IconThemeData(color: AppColors.textSecondary, size: 20),
      tooltipTheme: const TooltipThemeData(
          textStyle: TextStyle(fontFamily: 'Inter', color: AppColors.onAccent, fontSize: 12)),
      scrollbarTheme: ScrollbarThemeData(
          thumbColor: WidgetStateProperty.all(AppColors.border)),
    );
  }
}
