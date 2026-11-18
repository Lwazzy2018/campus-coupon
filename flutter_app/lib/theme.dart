import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Campus Coupon colours - EXACT values measured pixel-by-pixel from the
/// Phase 2 Figma mobile screens (Mobile Screens/*.png). Nothing else is used.
///
///   #003261  header bar, status bar, buttons, titles, selected chip
///   #D9D9D9  input fields, filter chips, stat tiles, balance box, info boxes
///   #F3EBEB  event / coupon cards, Date & Time box
///   #FEFEFE  page background, bottom bar
///   #5188BD  field hints, subtitles, descriptions, labels
///   #3878B4  "Manage | Monitor | Empower", "Redemption Code", secondary text
///   #4DBBEA  links: "Forgot password?", "Register", "Login", "See All"
///   #FE0707  points cost (500 / 300 / 250)
///   #FF0000  "RSVP" label on the RSVP button
///   #2CC617  "Coupon Redeemed" tick
///   #15BA41  "Active Events" play icon
///   #000000  body text and icons
///   #FFFFFF  text on navy
/// The gold coin is the Figma coin image itself (assets/images/coin.png).
class CC {
  static const navy = Color(0xFF003261);
  static const field = Color(0xFFD9D9D9);
  static const card = Color(0xFFF3EBEB);
  static const background = Color(0xFFFEFEFE);
  static const labelBlue = Color(0xFF5188BD);
  static const textBlue = Color(0xFF3878B4);
  static const link = Color(0xFF4DBBEA);
  static const points = Color(0xFFFE0707);
  static const rsvpRed = Color(0xFFFF0000);
  static const success = Color(0xFF2CC617);
  static const activeGreen = Color(0xFF15BA41);
  static const black = Color(0xFF000000);
  static const white = Color(0xFFFFFFFF);

  // ---- White CUT look (Home, Events, Coupons, Profile...) ----
  // Same colour family as the ASP.NET portal: white pages, navy accents,
  // the CUT logo and a thin red + gold line from the CUT shield.
  // Login and Register keep the Figma colours above.
  static const cutBlue = Color(0xFF0C4386);    // CUT logo blue (feature tile gradient)
  static const cutRed = Color(0xFFB02319);     // CUT shield red
  static const cutGold = Color(0xFFFFC933);    // CUT shield gold
  static const tileBg = Color(0xFFF6F8FB);     // very light boxes (Figma grey, lightened)
  static const border = Color(0xFFE6E9EF);     // fine card borders
  static const muted = Color(0xFF8A8FA0);      // secondary text (portal "muted")
  static const bodyText = Color(0xFF5B6475);   // small labels on tiles
  static const greenText = Color(0xFF1E7A1E);  // "Going", "+100"
  static const greenSoft = Color(0xFFEAF7E4);  // soft green pill / icon box
  static const redSoft = Color(0xFFFBEEEE);    // soft red icon box
  static const blueSoft = Color(0xFFEEF3FA);   // soft blue icon box
  static const approve = Color(0xFF2DBE2D);    // portal approve green

  /// Navy -> CUT blue: the "Upcoming events" feature tile.
  static const featureGradient = LinearGradient(
    colors: [navy, cutBlue],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Faint shadow under white cards.
  static const cardShadow = [
    BoxShadow(color: Color(0x0A003261), blurRadius: 6, offset: Offset(0, 2)),
  ];
}

ThemeData buildTheme() {
  // Plain ColorScheme (not fromSeed) so Material 3 cannot invent extra tones:
  // every colour on screen comes from the Figma palette above.
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: CC.navy,
    onPrimary: CC.white,
    primaryContainer: CC.navy,
    onPrimaryContainer: CC.white,
    secondary: CC.labelBlue,
    onSecondary: CC.white,
    secondaryContainer: CC.field,
    onSecondaryContainer: CC.black,
    tertiary: CC.textBlue,
    onTertiary: CC.white,
    error: CC.points,
    onError: CC.white,
    surface: CC.background,
    onSurface: CC.black,
    onSurfaceVariant: CC.black,
    surfaceTint: Colors.transparent, // stops the M3 tint on bars, cards, dialogs
    outline: CC.labelBlue,
    surfaceContainerLowest: CC.background,
    surfaceContainerLow: CC.background,
    surfaceContainer: CC.background,
    surfaceContainerHigh: CC.background, // dialogs
    surfaceContainerHighest: CC.field,
    outlineVariant: CC.field,
    inverseSurface: CC.navy,
    onInverseSurface: CC.white,
    inversePrimary: CC.link,
    tertiaryContainer: CC.card,
    onTertiaryContainer: CC.black,
    errorContainer: CC.card,
    onErrorContainer: CC.points,
    shadow: CC.black,
    scrim: CC.black,
  );

  final base = ThemeData(useMaterial3: true, colorScheme: scheme, scaffoldBackgroundColor: CC.background);

  return base.copyWith(
    // Navy header + navy status bar with white icons, as on every mobile screen
    appBarTheme: const AppBarTheme(
      backgroundColor: CC.navy,
      foregroundColor: CC.white,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      centerTitle: true,
      iconTheme: IconThemeData(color: CC.white),
      actionsIconTheme: IconThemeData(color: CC.white),
      titleTextStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: CC.white),
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: CC.navy,
        statusBarIconBrightness: Brightness.light, // Android
        statusBarBrightness: Brightness.dark, // iOS
      ),
    ),

    // Bottom bar: white with black icons and labels (Figma). The open tab is navy.
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: CC.background,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Colors.transparent,
      elevation: 0,
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? CC.navy : CC.black,
          )),
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontSize: 12,
            color: states.contains(WidgetState.selected) ? CC.navy : CC.black,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          )),
    ),

    // Grey rounded inputs, #5188BD hints, black icons (Login / Registration screens)
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: CC.field,
      hintStyle: const TextStyle(color: CC.labelBlue, fontWeight: FontWeight.w600),
      labelStyle: const TextStyle(color: CC.labelBlue, fontWeight: FontWeight.w600),
      prefixIconColor: CC.black,
      suffixIconColor: CC.black,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: CC.navy, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: CC.points, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: CC.points, width: 2),
      ),
      errorStyle: const TextStyle(color: CC.points, fontWeight: FontWeight.w600),
    ),

    // Navy filled buttons (Login, Register, Redeem Coupons, Done, RSVP)
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: CC.navy,
        foregroundColor: CC.white,
        disabledBackgroundColor: CC.field,
        disabledForegroundColor: CC.black,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        minimumSize: const Size.fromHeight(50),
        textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: CC.link, textStyle: const TextStyle(fontWeight: FontWeight.w600)),
    ),

    progressIndicatorTheme: const ProgressIndicatorThemeData(color: CC.navy, refreshBackgroundColor: CC.background),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: CC.navy,
      contentTextStyle: TextStyle(color: CC.white, fontWeight: FontWeight.w600),
      actionTextColor: CC.link,
      behavior: SnackBarBehavior.floating,
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: CC.navy,
      selectionColor: CC.field,
      selectionHandleColor: CC.navy,
    ),
    listTileTheme: const ListTileThemeData(iconColor: CC.black, textColor: CC.black),
    dividerTheme: const DividerThemeData(color: CC.field),
  );
}
