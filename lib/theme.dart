import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// RA7AlTV design tokens (royal blue + turquoise), dark and light.
@immutable
class Ra7al extends ThemeExtension<Ra7al> {
  final Color bg, rail, card, input, line, active, text, muted, faint, accent, onAccent, brand, live, placeholder;
  const Ra7al({
    required this.bg,
    required this.rail,
    required this.card,
    required this.input,
    required this.line,
    required this.active,
    required this.text,
    required this.muted,
    required this.faint,
    required this.accent,
    required this.onAccent,
    required this.brand,
    required this.live,
    required this.placeholder,
  });

  static const dark = Ra7al(
    bg: Color(0xFF0A1022),
    rail: Color(0xFF0E1530),
    card: Color(0xFF121A38),
    input: Color(0xFF141D3D),
    line: Color(0xFF1E2850),
    active: Color(0xFF1C2A66),
    text: Color(0xFFF2F5FF),
    muted: Color(0xFFA9B4D6),
    faint: Color(0xFF8F9AC0),
    accent: Color(0xFF22D3EE),
    onAccent: Color(0xFF04212E),
    brand: Color(0xFF2563EB),
    live: Color(0xFFF08A7E),
    placeholder: Color(0xFF142456),
  );

  static const light = Ra7al(
    bg: Color(0xFFF5F7FC),
    rail: Color(0xFFFFFFFF),
    card: Color(0xFFFFFFFF),
    input: Color(0xFFEEF2FB),
    line: Color(0xFFDDE3F0),
    active: Color(0xFFE3EBFF),
    text: Color(0xFF0B1533),
    muted: Color(0xFF4F5B80),
    faint: Color(0xFF5E6A91),
    accent: Color(0xFF0E7490),
    onAccent: Color(0xFFFFFFFF),
    brand: Color(0xFF2563EB),
    live: Color(0xFFC2412F),
    placeholder: Color(0xFFDCE5FB),
  );

  @override
  Ra7al copyWith() => this;

  @override
  Ra7al lerp(ThemeExtension<Ra7al>? other, double t) {
    if (other is! Ra7al) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return Ra7al(
      bg: l(bg, other.bg),
      rail: l(rail, other.rail),
      card: l(card, other.card),
      input: l(input, other.input),
      line: l(line, other.line),
      active: l(active, other.active),
      text: l(text, other.text),
      muted: l(muted, other.muted),
      faint: l(faint, other.faint),
      accent: l(accent, other.accent),
      onAccent: l(onAccent, other.onAccent),
      brand: l(brand, other.brand),
      live: l(live, other.live),
      placeholder: l(placeholder, other.placeholder),
    );
  }
}

extension Ra7alX on BuildContext {
  Ra7al get c => Theme.of(this).extension<Ra7al>() ?? Ra7al.dark;

  /// Brand gradient (neon blue -> cyan) used for active and primary elements.
  LinearGradient get brandGradient => LinearGradient(colors: [c.brand, c.accent]);
}

ThemeData buildTheme(Brightness b) {
  final t = b == Brightness.dark ? Ra7al.dark : Ra7al.light;
  final base = ThemeData(brightness: b, useMaterial3: true);
  TextTheme text;
  try {
    text = GoogleFonts.ibmPlexSansArabicTextTheme(base.textTheme);
  } catch (_) {
    text = base.textTheme;
  }
  text = text.apply(bodyColor: t.text, displayColor: t.text);
  return base.copyWith(
    scaffoldBackgroundColor: t.bg,
    canvasColor: t.bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: t.brand,
      brightness: b,
    ).copyWith(
      primary: t.accent,
      onPrimary: t.onAccent,
      secondary: t.brand,
      surface: t.card,
      onSurface: t.text,
      error: t.live,
    ),
    textTheme: text,
    dividerColor: t.line,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: ZoomPageTransitionsBuilder(),
      TargetPlatform.windows: ZoomPageTransitionsBuilder(),
      TargetPlatform.macOS: ZoomPageTransitionsBuilder(),
      TargetPlatform.linux: ZoomPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
    focusColor: t.accent.withValues(alpha: 0.38),
    hoverColor: t.accent.withValues(alpha: 0.12),
    extensions: [t],
  );
}

InputDecoration fieldDecoration(BuildContext context, {String? hint, Widget? prefix, Widget? suffix}) {
  final c = context.c;
  OutlineInputBorder border(Color col, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: col, width: w),
      );
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: c.faint),
    filled: true,
    fillColor: c.input,
    prefixIcon: prefix,
    suffixIcon: suffix,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    enabledBorder: border(c.line),
    focusedBorder: border(c.accent, 2),
    border: border(c.line),
  );
}
