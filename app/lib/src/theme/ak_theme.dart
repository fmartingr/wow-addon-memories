/// The theme of the app. It is the look of the website (web/base.css): a dark theme, gold double borders, Cinzel
/// capitals and Alegreya Sans text. The colours come from `tokens.dart`, which `make app-theme` writes from the website.
/// The component values below (gradients, shadows) have the same literals as the components of `web/base.css`; the
/// theme parity check (`make theme-check`) fails when one side changes alone.
library;

import 'package:flutter/material.dart';

import 'tokens.dart';

// The literals of `.btn`, `.btn.primary` and `.panel` in web/base.css.
const Color _btnTop = Color(0xFF4A3818);
const Color _btnBottom = Color(0xFF21170A);
const Color _primaryTop = Color(0xFFE7BB68);
const Color _primaryBottom = Color(0xFFAE742B);
const Color _primaryEdge = Color(0xFFE3B76B);
const Color _primaryInk = Color(0xFF20180E);
const Color _panelInset = Color(0xFF0D1213);
const Color _panelGlow = Color(0x20C09958);
const Color _panelRule = Color(0xFF423B2D);
const Color _fieldFill = Color(0xFF0B1013);
const Color _meterTrack = Color(0xFF080C0E);

/// The border of a panel: the outer edge, a dark inset line and a faint gold line, as the `.panel` box shadows.
class AkPanelBorder extends ShapeBorder {
  const AkPanelBorder({this.radius = 5});

  final double radius;

  @override
  EdgeInsetsGeometry get dimensions => const EdgeInsets.all(1);

  RRect _rrect(Rect rect, double inset) => RRect.fromRectAndRadius(
    rect.deflate(inset),
    Radius.circular((radius - inset).clamp(0, radius)),
  );

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRRect(_rrect(rect, 1));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRRect(_rrect(rect, 0));

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    Paint line(Color c, double w) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..color = c;
    canvas.drawRRect(_rrect(rect, 0.5), line(Tokens.edge, 1));
    canvas.drawRRect(_rrect(rect, 2.5), line(_panelInset, 3));
    canvas.drawRRect(_rrect(rect, 4.5), line(_panelGlow, 1));
  }

  @override
  ShapeBorder scale(double t) => AkPanelBorder(radius: radius * t);
}

TextStyle _display(
  double size, {
  Color color = Tokens.goldLight,
  double spacing = 0.8,
  double weight = 600,
}) => TextStyle(
  fontFamily: Tokens.displayFamily,
  fontSize: size,
  color: color,
  letterSpacing: spacing,
  fontVariations: [FontVariation('wght', weight)],
  fontWeight: weight >= 700 ? FontWeight.w700 : FontWeight.w600,
);

TextStyle _body(double size, {Color color = Tokens.text, FontWeight? weight}) =>
    TextStyle(
      fontFamily: Tokens.bodyFamily,
      fontSize: size,
      color: color,
      fontWeight: weight,
      height: 1.35,
    );

TextTheme _textTheme() => TextTheme(
  displaySmall: _display(28),
  headlineMedium: _display(24),
  headlineSmall: _display(22),
  titleLarge: _display(20),
  titleMedium: _display(15, color: Tokens.gold, spacing: 1.4),
  titleSmall: _display(13),
  bodyLarge: _body(17),
  bodyMedium: _body(16),
  bodySmall: _body(14, color: Tokens.muted),
  labelLarge: _display(13, spacing: 0.8, weight: 700),
  labelMedium: _body(14, color: Tokens.muted, weight: FontWeight.w500),
  labelSmall: _body(12, color: Tokens.muted),
);

ColorScheme _scheme() => const ColorScheme.dark(
  primary: Tokens.gold,
  onPrimary: _primaryInk,
  primaryContainer: _btnTop,
  onPrimaryContainer: Tokens.goldLight,
  secondary: Tokens.goldDim,
  onSecondary: _primaryInk,
  secondaryContainer: Color(0xFF2B2314),
  onSecondaryContainer: Tokens.goldLight,
  tertiary: Tokens.blue,
  surface: Tokens.surface,
  onSurface: Tokens.text,
  onSurfaceVariant: Tokens.muted,
  surfaceContainerLowest: Tokens.bg,
  surfaceContainerLow: Tokens.surfaceLow,
  surfaceContainer: Tokens.surface,
  surfaceContainerHigh: Tokens.surfaceHi,
  surfaceContainerHighest: Tokens.surfaceHi,
  outline: Tokens.edge,
  outlineVariant: Tokens.edgeSoft,
  error: Tokens.red,
  onError: Color(0xFF2A0A06),
  errorContainer: Color(0xFF4A1A14),
  onErrorContainer: Color(0xFFFFD9D2),
);

/// A button with a gradient, a border and the button font. Its look is `.btn` (or `.btn.primary`) of the website.
ButtonStyle _button({required bool primary}) {
  final top = primary ? _primaryTop : _btnTop;
  final bottom = primary ? _primaryBottom : _btnBottom;
  final edge = primary ? _primaryEdge : Tokens.goldDim;
  final ink = primary ? _primaryInk : Tokens.goldLight;
  return ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    ),
    foregroundColor: WidgetStatePropertyAll(ink),
    iconColor: WidgetStatePropertyAll(ink),
    backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
    shadowColor: const WidgetStatePropertyAll(Colors.transparent),
    elevation: const WidgetStatePropertyAll(0),
    overlayColor: WidgetStatePropertyAll(Colors.white.withValues(alpha: 0.1)),
    side: const WidgetStatePropertyAll(BorderSide.none),
    shape: const WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(3)),
      ),
    ),
    textStyle: WidgetStatePropertyAll(_display(13, color: ink, weight: 700)),
    backgroundBuilder: (context, states, child) {
      final hover = states.contains(WidgetState.hovered) && !primary;
      final box = DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: hover
                ? const [Color(0xFF6A5022), Color(0xFF2C1F0D)]
                : [top, bottom],
          ),
          border: Border.all(color: edge),
          borderRadius: BorderRadius.circular(3),
          boxShadow: const [
            BoxShadow(color: Colors.black, offset: Offset(0, 2)),
          ],
        ),
        child: child,
      );
      return states.contains(WidgetState.disabled)
          ? Opacity(opacity: 0.4, child: box)
          : box;
    },
  );
}

/// The dark theme of the app.
ThemeData buildAkTheme() {
  final scheme = _scheme();
  final text = _textTheme();
  OutlineInputBorder field(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(3),
    borderSide: BorderSide(color: c, width: w),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Tokens.bg,
    canvasColor: Tokens.bg,
    fontFamily: Tokens.bodyFamily,
    textTheme: text,
    primaryTextTheme: text,
    iconTheme: const IconThemeData(color: Tokens.gold),
    dividerTheme: const DividerThemeData(color: _panelRule, space: 1),
    focusColor: Tokens.goldLight,
    cardTheme: const CardThemeData(
      color: Tokens.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: AkPanelBorder(),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Tokens.surface,
      shape: const AkPanelBorder(),
      titleTextStyle: text.titleLarge,
      contentTextStyle: text.bodyMedium,
    ),
    appBarTheme: AppBarThemeData(
      backgroundColor: Tokens.surfaceLow,
      foregroundColor: Tokens.goldLight,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: _display(20, spacing: 1.2),
      shape: const Border(bottom: BorderSide(color: Tokens.edge, width: 2)),
    ),
    filledButtonTheme: FilledButtonThemeData(style: _button(primary: true)),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: _button(primary: false),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: _button(primary: false),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
        foregroundColor: const WidgetStatePropertyAll(Tokens.goldLight),
        textStyle: WidgetStatePropertyAll(_body(15, weight: FontWeight.w700)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
        foregroundColor: const WidgetStatePropertyAll(Tokens.goldLight),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _fieldFill,
      labelStyle: _body(16, color: Tokens.muted),
      border: field(Tokens.edgeSoft),
      enabledBorder: field(Tokens.edgeSoft),
      focusedBorder: field(Tokens.goldLight, 2),
      errorBorder: field(Tokens.red),
      focusedErrorBorder: field(Tokens.red, 2),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? _primaryInk : Tokens.muted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Tokens.gold : _fieldFill,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Tokens.goldDim),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: Tokens.gold,
      linearTrackColor: _meterTrack,
      linearMinHeight: 14,
      borderRadius: BorderRadius.zero,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: Tokens.gold,
      textColor: Tokens.text,
      titleTextStyle: _body(17),
      subtitleTextStyle: _body(15, color: Tokens.muted),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF0A1016),
      contentTextStyle: _body(16),
      actionTextColor: Tokens.goldLight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(4)),
        side: BorderSide(color: Tokens.goldDim),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: const Color(0xFF0A1016),
        border: Border.all(color: Tokens.goldDim),
        borderRadius: BorderRadius.circular(4),
      ),
      textStyle: _body(14),
    ),
    scrollbarTheme: const ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(Tokens.edge),
    ),
    dividerColor: _panelRule,
  );
}
