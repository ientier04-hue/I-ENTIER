import 'dart:ui' show PointerDeviceKind;

// Flutter 3.44 moved CupertinoPageTransitionsBuilder out of material.dart.
// ignore: unnecessary_import
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Palette partagée par l’expérience I-ENTIER.
abstract final class AppColors {
  static const primary = Color(0xFF176BFF);
  static const primaryDark = Color(0xFF0E55D2);
  static const primarySoft = Color(0xFFEAF1FF);
  static const teal = Color(0xFF0A8F8F);
  static const navy = Color(0xFF102A56);
  static const ink = Color(0xFF344054);
  static const muted = Color(0xFF667085);
  static const border = Color(0xFFE1E8F0);
  static const canvas = Color(0xFFF5F8FC);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFF3F6FA);
  static const tealSoft = Color(0xFFE5F7F3);
  static const disabled = Color(0xFFD5DDE8);
  static const error = Color(0xFFD92D20);
  static const success = Color(0xFF087A5B);
  static const warning = Color(0xFFB54708);
}

/// Même finition pour les cartes, qu’elles utilisent Material ou Container.
abstract final class AppDecorations {
  static const controlRadius = BorderRadius.all(Radius.circular(16));
  static const cardRadius = BorderRadius.all(Radius.circular(22));
  static const card = BoxDecoration(
    color: AppColors.surface,
    borderRadius: cardRadius,
    border: Border.fromBorderSide(BorderSide(color: AppColors.border)),
  );
  static const cardShadow = [
    BoxShadow(color: Color(0x08102A56), blurRadius: 18, offset: Offset(0, 5)),
  ];
  static final raisedCard = card.copyWith(boxShadow: cardShadow);
}

/// Fondation Material 3 commune à tous les écrans.
abstract final class AppTheme {
  static ThemeData get light {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
          primary: AppColors.primary,
          secondary: AppColors.teal,
          error: AppColors.error,
          surface: AppColors.surface,
        ).copyWith(
          onPrimary: AppColors.surface,
          primaryContainer: AppColors.primarySoft,
          onPrimaryContainer: AppColors.primaryDark,
          secondaryContainer: AppColors.tealSoft,
          onSecondaryContainer: AppColors.success,
          onSurface: AppColors.ink,
          onSurfaceVariant: AppColors.muted,
          outline: AppColors.border,
          outlineVariant: const Color(0xFFEDF1F6),
          surfaceContainerLowest: AppColors.surface,
          surfaceContainerLow: const Color(0xFFFAFCFE),
          surfaceContainer: AppColors.surfaceMuted,
          surfaceContainerHigh: const Color(0xFFEDF2F7),
          surfaceContainerHighest: const Color(0xFFE7EDF4),
        );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.canvas,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );

    return base.copyWith(
      // Conserve les tailles et métriques de la typographie Material.
      textTheme: base.textTheme.copyWith(
        displaySmall: base.textTheme.displaySmall!.copyWith(
          color: AppColors.navy,
          fontWeight: FontWeight.w800,
          letterSpacing: -1,
        ),
        headlineLarge: base.textTheme.headlineLarge!.copyWith(
          color: AppColors.navy,
          fontWeight: FontWeight.w800,
          letterSpacing: -.8,
        ),
        headlineMedium: base.textTheme.headlineMedium!.copyWith(
          color: AppColors.navy,
          fontWeight: FontWeight.w800,
          letterSpacing: -.5,
        ),
        headlineSmall: base.textTheme.headlineSmall!.copyWith(
          color: AppColors.navy,
          fontWeight: FontWeight.w800,
          letterSpacing: -.25,
        ),
        titleLarge: base.textTheme.titleLarge!.copyWith(
          color: AppColors.navy,
          fontWeight: FontWeight.w800,
        ),
        titleMedium: base.textTheme.titleMedium!.copyWith(
          color: AppColors.navy,
          fontWeight: FontWeight.w700,
        ),
        titleSmall: base.textTheme.titleSmall!.copyWith(
          color: AppColors.navy,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: base.textTheme.bodyLarge!.copyWith(
          color: AppColors.ink,
          height: 1.45,
        ),
        bodyMedium: base.textTheme.bodyMedium!.copyWith(
          color: AppColors.ink,
          height: 1.4,
        ),
        bodySmall: base.textTheme.bodySmall!.copyWith(
          color: AppColors.muted,
          height: 1.35,
        ),
        labelLarge: base.textTheme.labelLarge!.copyWith(
          fontWeight: FontWeight.w700,
        ),
        labelMedium: base.textTheme.labelMedium!.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.canvas,
        foregroundColor: AppColors.navy,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 20,
        toolbarHeight: 64,
        iconTheme: IconThemeData(color: AppColors.navy),
        actionsIconTheme: IconThemeData(color: AppColors.navy),
        titleTextStyle: TextStyle(
          color: AppColors.navy,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppDecorations.cardRadius,
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 17,
        ),
        hintStyle: const TextStyle(color: AppColors.muted),
        labelStyle: const TextStyle(color: AppColors.muted),
        prefixIconColor: WidgetStateColor.resolveWith(_inputIconColor),
        suffixIconColor: WidgetStateColor.resolveWith(_inputIconColor),
        floatingLabelStyle: const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.w700,
        ),
        errorMaxLines: 2,
        disabledBorder: const OutlineInputBorder(
          borderRadius: AppDecorations.controlRadius,
          borderSide: BorderSide(color: AppColors.border),
        ),
        border: OutlineInputBorder(
          borderRadius: AppDecorations.controlRadius,
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppDecorations.controlRadius,
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppDecorations.controlRadius,
          borderSide: const BorderSide(color: AppColors.primary, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppDecorations.controlRadius,
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppDecorations.controlRadius,
          borderSide: BorderSide(color: scheme.error, width: 1.8),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.disabled,
          disabledForegroundColor: AppColors.muted,
          elevation: 0,
          minimumSize: const Size(48, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: AppDecorations.controlRadius,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size(48, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: AppDecorations.controlRadius,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primaryDark,
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.navy,
          minimumSize: const Size.square(48),
          shape: const CircleBorder(),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 3,
        focusElevation: 5,
        hoverElevation: 5,
      ),
      navigationBarTheme: const NavigationBarThemeData(
        height: 72,
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primarySoft,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: WidgetStatePropertyAll(IconThemeData(size: 24)),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
        ),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: AppColors.primarySoft,
        selectedIconTheme: IconThemeData(color: AppColors.primary, size: 25),
        unselectedIconTheme: IconThemeData(color: AppColors.muted, size: 24),
        selectedLabelTextStyle: TextStyle(
          color: AppColors.primary,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: AppColors.muted,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.primaryDark,
        unselectedLabelColor: AppColors.muted,
        labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        unselectedLabelStyle: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        indicatorColor: AppColors.primary,
        dividerColor: AppColors.border,
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        shadowColor: Color(0x24102A56),
        shape: RoundedRectangleBorder(
          borderRadius: AppDecorations.controlRadius,
          side: BorderSide(color: AppColors.border),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: AppColors.surface,
        modalBarrierColor: Color(0x8F102A56),
        showDragHandle: true,
        dragHandleColor: Color(0xFFB8C3D1),
        dragHandleSize: Size(42, 4),
        elevation: 0,
        modalElevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: const TextStyle(
          color: AppColors.navy,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
        contentTextStyle: const TextStyle(
          color: AppColors.ink,
          fontSize: 15,
          height: 1.45,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.navy,
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
        actionTextColor: const Color(0xFF9FD8FF),
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: AppDecorations.controlRadius,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: AppColors.surfaceMuted,
        selectedColor: AppColors.primarySoft,
        disabledColor: const Color(0xFFF1F3F6),
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        labelStyle: const TextStyle(
          color: AppColors.navy,
          fontWeight: FontWeight.w700,
        ),
        secondaryLabelStyle: const TextStyle(
          color: AppColors.primaryDark,
          fontWeight: FontWeight.w800,
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.primary,
        textColor: AppColors.ink,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        minTileHeight: 56,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.navy,
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        waitDuration: const Duration(milliseconds: 450),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: AppColors.primarySoft,
        circularTrackColor: AppColors.primarySoft,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }

  static Color _inputIconColor(Set<WidgetState> states) {
    if (states.contains(WidgetState.disabled)) return AppColors.muted;
    if (states.contains(WidgetState.error)) return AppColors.error;
    if (states.contains(WidgetState.focused)) return AppColors.primary;
    return AppColors.muted;
  }
}

/// Autorise le défilement par glisser à la souris sur Flutter Web et desktop.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    ...super.dragDevices,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
  };
}
