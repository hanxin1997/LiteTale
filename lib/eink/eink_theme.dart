import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wild/theme/horizontal_page_transitions.dart';

const _paper = Color(0xFFFFFFFF);
const _ink = Color(0xFF101010);
const _mutedInk = Color(0xFF555555);
const _disabledInk = Color(0xFF666666);
const _disabledPaper = Color(0xFFE6E6E6);

/// Derive only display colors and material effects. Keeping the base typography
/// retains imported fonts, CJK fallbacks, locale-specific glyphs and text sizes;
/// none of the user's saved appearance preferences are changed.
ThemeData einkTheme(ThemeData base) {
  const colors = ColorScheme.light(
    primary: _ink,
    onPrimary: _paper,
    primaryContainer: _disabledPaper,
    onPrimaryContainer: _ink,
    primaryFixed: _disabledPaper,
    onPrimaryFixed: _ink,
    primaryFixedDim: _disabledPaper,
    onPrimaryFixedVariant: _ink,
    secondary: _ink,
    onSecondary: _paper,
    secondaryContainer: _disabledPaper,
    onSecondaryContainer: _ink,
    secondaryFixed: _disabledPaper,
    onSecondaryFixed: _ink,
    secondaryFixedDim: _disabledPaper,
    onSecondaryFixedVariant: _ink,
    tertiary: _ink,
    onTertiary: _paper,
    tertiaryContainer: _disabledPaper,
    onTertiaryContainer: _ink,
    tertiaryFixed: _disabledPaper,
    onTertiaryFixed: _ink,
    tertiaryFixedDim: _disabledPaper,
    onTertiaryFixedVariant: _ink,
    error: _ink,
    onError: _paper,
    errorContainer: _disabledPaper,
    onErrorContainer: _ink,
    surface: _paper,
    onSurface: _ink,
    onSurfaceVariant: _mutedInk,
    surfaceDim: _paper,
    surfaceBright: _paper,
    surfaceContainerLowest: _paper,
    surfaceContainerLow: _paper,
    surfaceContainer: _paper,
    surfaceContainerHigh: _paper,
    surfaceContainerHighest: _paper,
    outline: _ink,
    outlineVariant: _mutedInk,
    inverseSurface: _ink,
    onInverseSurface: _paper,
    inversePrimary: _paper,
    shadow: Colors.transparent,
    scrim: _ink,
    surfaceTint: Colors.transparent,
  );
  const border = BorderSide(color: _ink);
  const shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(12)),
    side: border,
  );

  ButtonStyle buttonStyle(ButtonStyle? original, {bool filled = false}) {
    final overrides = ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return _disabledPaper;
        return filled ? _ink : _paper;
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return _disabledInk;
        return filled ? _paper : _ink;
      }),
      side: WidgetStateProperty.resolveWith((states) {
        return BorderSide(
          color:
              states.contains(WidgetState.disabled) ? _disabledInk : _ink,
        );
      }),
      elevation: const WidgetStatePropertyAll(0),
      shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      splashFactory: NoSplash.splashFactory,
    );
    // ButtonStyle.merge fills null properties on its receiver. Keep this
    // display policy authoritative, filling only typography/layout from base.
    return overrides.merge(original);
  }

  Color controlFill(Set<WidgetState> states) {
    if (states.contains(WidgetState.disabled)) return _disabledPaper;
    return states.contains(WidgetState.selected) ? _ink : _paper;
  }

  Color controlInk(Set<WidgetState> states) {
    if (states.contains(WidgetState.disabled)) return _disabledInk;
    return states.contains(WidgetState.selected) ? _paper : _ink;
  }

  final textTheme = base.textTheme.apply(bodyColor: _ink, displayColor: _ink);
  return base.copyWith(
    brightness: Brightness.light,
    colorScheme: colors,
    // The Android display policy supplies actual zero route durations as well
    // as a static final frame. Keep every other platform builder untouched.
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        ...base.pageTransitionsTheme.builders,
        TargetPlatform.android: const EInkPageTransitionsBuilder(),
      },
    ),
    scaffoldBackgroundColor: _paper,
    canvasColor: _paper,
    cardColor: _paper,
    dialogBackgroundColor: _paper,
    primaryColor: _ink,
    primaryColorLight: _disabledPaper,
    primaryColorDark: _ink,
    secondaryHeaderColor: _paper,
    dividerColor: _mutedInk,
    disabledColor: _disabledInk,
    shadowColor: Colors.transparent,
    splashFactory: NoSplash.splashFactory,
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
    focusColor: _disabledPaper,
    textTheme: textTheme,
    primaryTextTheme: base.primaryTextTheme.apply(
      bodyColor: _paper,
      displayColor: _paper,
    ),
    iconTheme: base.iconTheme.copyWith(color: _ink, opacity: 1),
    primaryIconTheme: base.primaryIconTheme.copyWith(color: _paper, opacity: 1),
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: _paper,
      foregroundColor: _ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      iconTheme: base.appBarTheme.iconTheme?.copyWith(color: _ink, opacity: 1) ??
          const IconThemeData(color: _ink, opacity: 1),
      actionsIconTheme:
          base.appBarTheme.actionsIconTheme?.copyWith(color: _ink, opacity: 1) ??
          const IconThemeData(color: _ink, opacity: 1),
      titleTextStyle:
          (base.appBarTheme.titleTextStyle ?? textTheme.titleLarge)?.copyWith(
            color: _ink,
          ),
      toolbarTextStyle:
          (base.appBarTheme.toolbarTextStyle ?? textTheme.bodyMedium)?.copyWith(
            color: _ink,
          ),
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: _paper,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: _paper,
        systemNavigationBarDividerColor: _ink,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    ),
    cardTheme: base.cardTheme.copyWith(
      color: _paper,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shape: shape,
    ),
    dividerTheme: base.dividerTheme.copyWith(color: _mutedInk, thickness: 1),
    listTileTheme: base.listTileTheme.copyWith(
      textColor: _ink,
      iconColor: _ink,
      tileColor: _paper,
      selectedTileColor: _disabledPaper,
      selectedColor: _ink,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: buttonStyle(base.filledButtonTheme.style, filled: true),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: buttonStyle(base.elevatedButtonTheme.style, filled: true),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: buttonStyle(base.outlinedButtonTheme.style),
    ),
    textButtonTheme: TextButtonThemeData(
      style: buttonStyle(base.textButtonTheme.style),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.disabled) ? _disabledInk : _ink;
        }),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        splashFactory: NoSplash.splashFactory,
      ),
    ),
    checkboxTheme: base.checkboxTheme.copyWith(
      fillColor: WidgetStateProperty.resolveWith(controlFill),
      checkColor: WidgetStateProperty.resolveWith(controlInk),
      side: border,
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      splashRadius: 0,
    ),
    radioTheme: base.radioTheme.copyWith(
      fillColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.disabled) ? _disabledInk : _ink;
      }),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      splashRadius: 0,
    ),
    switchTheme: base.switchTheme.copyWith(
      trackColor: WidgetStateProperty.resolveWith(controlFill),
      thumbColor: WidgetStateProperty.resolveWith(controlInk),
      trackOutlineColor: const WidgetStatePropertyAll(_ink),
      trackOutlineWidth: const WidgetStatePropertyAll(1),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      splashRadius: 0,
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: _paper,
      selectedColor: _disabledPaper,
      secondarySelectedColor: _disabledPaper,
      disabledColor: _disabledPaper,
      labelStyle: (base.chipTheme.labelStyle ?? textTheme.labelLarge)?.copyWith(
        color: _ink,
      ),
      secondaryLabelStyle:
          (base.chipTheme.secondaryLabelStyle ?? textTheme.labelLarge)?.copyWith(
            color: _ink,
          ),
      checkmarkColor: _ink,
      side: border,
      elevation: 0,
      pressElevation: 0,
      shadowColor: Colors.transparent,
      selectedShadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      filled: true,
      fillColor: _paper,
      hoverColor: _paper,
      focusColor: _paper,
      border: const OutlineInputBorder(borderSide: border),
      enabledBorder: const OutlineInputBorder(borderSide: border),
      disabledBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: _disabledInk),
      ),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: _ink, width: 2),
      ),
      errorBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: _ink, width: 2),
      ),
      focusedErrorBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: _ink, width: 2),
      ),
      labelStyle: (base.inputDecorationTheme.labelStyle ?? textTheme.bodyLarge)
          ?.copyWith(color: _ink),
      hintStyle: (base.inputDecorationTheme.hintStyle ?? textTheme.bodyLarge)
          ?.copyWith(color: _mutedInk),
      helperStyle: (base.inputDecorationTheme.helperStyle ?? textTheme.bodySmall)
          ?.copyWith(color: _mutedInk),
      errorStyle: (base.inputDecorationTheme.errorStyle ?? textTheme.bodySmall)
          ?.copyWith(color: _ink),
      prefixIconColor: _ink,
      suffixIconColor: _ink,
    ),
    searchBarTheme: base.searchBarTheme.copyWith(
      backgroundColor: const WidgetStatePropertyAll(_paper),
      elevation: const WidgetStatePropertyAll(0),
      shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      side: const WidgetStatePropertyAll(border),
      textStyle: WidgetStatePropertyAll(textTheme.bodyLarge),
      hintStyle: WidgetStatePropertyAll(
        textTheme.bodyLarge?.copyWith(color: _mutedInk),
      ),
    ),
    navigationBarTheme: base.navigationBarTheme.copyWith(
      backgroundColor: _paper,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      indicatorColor: _disabledPaper,
      indicatorShape: shape,
      iconTheme: const WidgetStatePropertyAll(IconThemeData(color: _ink)),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        return textTheme.labelMedium?.copyWith(
          color: _ink,
          fontWeight:
              states.contains(WidgetState.selected)
                  ? FontWeight.bold
                  : FontWeight.normal,
        );
      }),
    ),
    bottomNavigationBarTheme: base.bottomNavigationBarTheme.copyWith(
      backgroundColor: _paper,
      elevation: 0,
      selectedItemColor: _ink,
      unselectedItemColor: _mutedInk,
      selectedIconTheme: const IconThemeData(color: _ink),
      unselectedIconTheme: const IconThemeData(color: _mutedInk),
    ),
    tabBarTheme: base.tabBarTheme.copyWith(
      labelColor: _ink,
      unselectedLabelColor: _mutedInk,
      dividerColor: _mutedInk,
      indicatorColor: _ink,
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    bottomSheetTheme: base.bottomSheetTheme.copyWith(
      backgroundColor: _paper,
      modalBackgroundColor: _paper,
      elevation: 0,
      modalElevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: shape,
      dragHandleColor: _ink,
    ),
    dialogTheme: base.dialogTheme.copyWith(
      backgroundColor: _paper,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shape: shape,
      titleTextStyle:
          (base.dialogTheme.titleTextStyle ?? textTheme.headlineSmall)?.copyWith(
            color: _ink,
          ),
      contentTextStyle:
          (base.dialogTheme.contentTextStyle ?? textTheme.bodyMedium)?.copyWith(
            color: _ink,
          ),
    ),
    popupMenuTheme: base.popupMenuTheme.copyWith(
      color: _paper,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shape: shape,
      textStyle: (base.popupMenuTheme.textStyle ?? textTheme.labelLarge)?.copyWith(
        color: _ink,
      ),
    ),
    snackBarTheme: base.snackBarTheme.copyWith(
      backgroundColor: _paper,
      contentTextStyle:
          (base.snackBarTheme.contentTextStyle ?? textTheme.bodyMedium)?.copyWith(
            color: _ink,
          ),
      actionTextColor: _ink,
      disabledActionTextColor: _disabledInk,
      closeIconColor: _ink,
      elevation: 0,
      shape: shape,
    ),
    progressIndicatorTheme: base.progressIndicatorTheme.copyWith(
      color: _ink,
      linearTrackColor: _disabledPaper,
      circularTrackColor: _disabledPaper,
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: _ink,
      inactiveTrackColor: _mutedInk,
      disabledActiveTrackColor: _disabledInk,
      disabledInactiveTrackColor: _disabledPaper,
      thumbColor: _ink,
      disabledThumbColor: _disabledInk,
      overlayColor: Colors.transparent,
      activeTickMarkColor: _paper,
      inactiveTickMarkColor: _ink,
      valueIndicatorColor: _ink,
      valueIndicatorTextStyle:
          (base.sliderTheme.valueIndicatorTextStyle ?? textTheme.labelSmall)
              ?.copyWith(color: _paper),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: _ink,
      selectionColor: _disabledPaper,
      selectionHandleColor: _ink,
    ),
    tooltipTheme: base.tooltipTheme.copyWith(
      decoration: const BoxDecoration(
        color: _paper,
        border: Border.fromBorderSide(border),
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
      textStyle: (base.tooltipTheme.textStyle ?? textTheme.bodySmall)?.copyWith(
        color: _ink,
      ),
    ),
    // Any adaptive Cupertino children inherit the same opaque display colors.
    cupertinoOverrideTheme: CupertinoThemeData(
      brightness: Brightness.light,
      primaryColor: _ink,
      primaryContrastingColor: _paper,
      scaffoldBackgroundColor: _paper,
      barBackgroundColor: _paper,
      textTheme: base.cupertinoOverrideTheme?.textTheme,
    ),
  );
}
