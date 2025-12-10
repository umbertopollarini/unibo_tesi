import 'package:flutter/material.dart';

/// Design System Premium per Health Blockchain App
/// Stile ispirato a iOS con gradienti eleganti e card moderne
class AppTheme {
  AppTheme._();

  // ═══════════════════════════════════════════════════════════════
  // PALETTE COLORI PREMIUM
  // ═══════════════════════════════════════════════════════════════

  /// Background principale dell'app
  static const Color backgroundMain = Color(0xFFF7F8FB);

  /// Background cards bianco puro
  static const Color cardBackground = Colors.white;

  /// Colore primario blu elegante (scuro)
  static const Color primaryDark = Color(0xFF1D2671);

  /// Colore primario blu medio
  static const Color primaryMedium = Color(0xFF0B5394);

  /// Colore iOS blu classico
  static const Color primaryiOS = Color(0xFF007AFF);

  /// Colore iOS blu chiaro
  static const Color primaryiOSLight = Color(0xFF0A84FF);

  /// Testo principale scuro
  static const Color textPrimary = Color(0xFF1D1D1F);

  /// Testo secondario grigio
  static const Color textSecondary = Color(0xFF6E6E73);

  /// Testo terziario grigio chiaro
  static const Color textTertiary = Color(0xFF8E8E93);

  // Colori per status badge
  static const Color statusSuccess = Colors.green;
  static const Color statusWarning = Colors.orange;
  static const Color statusInfo = Colors.blueGrey;

  // Colori accento
  static const Color accentIndigo = Colors.indigo;
  static const Color accentTeal = Colors.teal;
  static const Color accentPurple = Colors.deepPurple;
  static const Color accentAmber = Colors.amber;

  // Background per sezioni speciali
  static const Color darkBackground = Color(0xFF0B1225);
  static const Color surfaceLight = Color(0xFFF2F2F7);

  // ═══════════════════════════════════════════════════════════════
  // GRADIENTI PREMIUM
  // ═══════════════════════════════════════════════════════════════

  /// Gradient blu scuro elegante per header
  static const LinearGradient gradientPrimary = LinearGradient(
    colors: [primaryDark, primaryMedium],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Gradient scuro per summary cards
  static const LinearGradient gradientDark = LinearGradient(
    colors: [Color(0xFF141E30), Color(0xFF243B55)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Gradient blu per logo/icone
  static LinearGradient gradientLogo = LinearGradient(
    colors: [Colors.blue[600]!, Colors.blue[400]!],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ═══════════════════════════════════════════════════════════════
  // BORDER RADIUS
  // ═══════════════════════════════════════════════════════════════

  static const double radiusCard = 18.0;
  static const double radiusCardLarge = 20.0;
  static const double radiusMedium = 14.0;
  static const double radiusSmall = 12.0;
  static const double radiusButton = 16.0;
  static const double radiusModal = 24.0;
  static const double radiusPill = 14.0;

  // ═══════════════════════════════════════════════════════════════
  // SPAZIATURE
  // ═══════════════════════════════════════════════════════════════

  static const double paddingCard = 16.0;
  static const double paddingCardLarge = 20.0;
  static const double paddingSection = 24.0;
  static const double paddingScreen = 20.0;
  static const double gapSmall = 8.0;
  static const double gapMedium = 12.0;
  static const double gapLarge = 16.0;
  static const double gapXLarge = 20.0;

  // ═══════════════════════════════════════════════════════════════
  // SHADOW ELEVATIONS
  // ═══════════════════════════════════════════════════════════════

  /// Shadow sottile per card normali
  static List<BoxShadow> get shadowCard => [
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 12,
          offset: const Offset(0, 6),
        ),
      ];

  /// Shadow media per card importanti
  static List<BoxShadow> get shadowCardMedium => [
        BoxShadow(
          color: Colors.black.withOpacity(0.08),
          blurRadius: 15,
          offset: const Offset(0, 8),
        ),
      ];

  /// Shadow prominente per header cards
  static List<BoxShadow> get shadowCardLarge => [
        BoxShadow(
          color: Colors.black.withOpacity(0.12),
          blurRadius: 18,
          offset: const Offset(0, 10),
        ),
      ];

  /// Shadow per bottoni/elementi interattivi
  static List<BoxShadow> get shadowButton => [
        BoxShadow(
          color: Colors.black.withOpacity(0.1),
          blurRadius: 15,
          offset: const Offset(0, 5),
        ),
      ];

  // ═══════════════════════════════════════════════════════════════
  // STILI TESTO
  // ═══════════════════════════════════════════════════════════════

  static const String fontFamily = 'SF Pro Display';

  /// Titolo grande (28px, bold)
  static const TextStyle headingLarge = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.bold,
    color: textPrimary,
    fontFamily: fontFamily,
  );

  /// Titolo medio (20px, bold)
  static const TextStyle headingMedium = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.bold,
    color: textPrimary,
    fontFamily: fontFamily,
  );

  /// Titolo card (18px, w700)
  static const TextStyle cardTitle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: textPrimary,
    fontFamily: fontFamily,
  );

  /// Sottotitolo card (15px, w700)
  static const TextStyle cardSubtitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: textPrimary,
    fontFamily: fontFamily,
  );

  /// Corpo testo (16px, w600)
  static const TextStyle bodyLarge = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: textSecondary,
    fontFamily: fontFamily,
  );

  /// Corpo testo normale (14px, w600)
  static const TextStyle bodyMedium = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: textSecondary,
    fontFamily: fontFamily,
  );

  /// Caption/label (12px, w600)
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: textTertiary,
    fontFamily: fontFamily,
  );

  /// Label piccolo (11px, w700, uppercase)
  static const TextStyle labelSmall = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: textTertiary,
    fontFamily: fontFamily,
    letterSpacing: 0.2,
  );

  /// Testo bianco per card scure
  static const TextStyle bodyWhite = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: Colors.white,
    fontFamily: fontFamily,
  );

  // ═══════════════════════════════════════════════════════════════
  // COMPONENTI RIUTILIZZABILI
  // ═══════════════════════════════════════════════════════════════

  /// Card container standard con shadow e bordi arrotondati
  static BoxDecoration cardDecoration({Color? color}) => BoxDecoration(
        color: color ?? cardBackground,
        borderRadius: BorderRadius.circular(radiusCard),
        boxShadow: shadowCard,
      );

  /// Card container large
  static BoxDecoration cardDecorationLarge({Color? color}) => BoxDecoration(
        color: color ?? cardBackground,
        borderRadius: BorderRadius.circular(radiusCardLarge),
        boxShadow: shadowCardMedium,
      );

  /// Badge/Pill decoration
  static BoxDecoration pillDecoration(Color color, {bool subtle = true}) =>
      BoxDecoration(
        color: color.withOpacity(subtle ? 0.08 : 0.12),
        border: Border.all(
          color: color.withOpacity(subtle ? 0.15 : 0.2),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(radiusPill),
      );

  /// Avatar circolare con background colorato
  static BoxDecoration avatarDecoration(Color color) => BoxDecoration(
        color: color.withOpacity(0.12),
        shape: BoxShape.circle,
      );

  /// Bottone primario style
  static ButtonStyle primaryButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: primaryMedium,
    foregroundColor: Colors.white,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusButton),
    ),
    padding: const EdgeInsets.symmetric(
      horizontal: paddingCardLarge,
      vertical: gapMedium,
    ),
  );

  /// Bottone outlined style
  static ButtonStyle outlinedButtonStyle = OutlinedButton.styleFrom(
    side: BorderSide(color: primaryMedium.withOpacity(0.3)),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusMedium),
    ),
    foregroundColor: primaryMedium,
    padding: const EdgeInsets.symmetric(
      horizontal: paddingCard,
      vertical: gapMedium,
    ),
  );

  // ═══════════════════════════════════════════════════════════════
  // THEME DATA GLOBALE
  // ═══════════════════════════════════════════════════════════════

  static ThemeData get lightTheme => ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: fontFamily,
        useMaterial3: true,
        scaffoldBackgroundColor: backgroundMain,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryiOS,
          brightness: Brightness.light,
          primary: primaryMedium,
          surface: cardBackground,
          background: backgroundMain,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: cardBackground,
          foregroundColor: textPrimary,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: textPrimary,
            fontFamily: fontFamily,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: primaryButtonStyle,
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: outlinedButtonStyle,
        ),
        cardTheme: CardThemeData(
          color: cardBackground,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusCard),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surfaceLight,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusSmall),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: paddingCard,
            vertical: gapMedium,
          ),
        ),
      );

  // ═══════════════════════════════════════════════════════════════
  // WIDGET HELPER FUNCTIONS
  // ═══════════════════════════════════════════════════════════════

  /// Crea un pill/badge informativo
  static Widget buildPill({
    required String label,
    required String value,
    required Color color,
    bool uppercase = true,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: pillDecoration(color),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            uppercase ? label.toUpperCase() : label,
            style: labelSmall.copyWith(color: color),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: bodyMedium.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// Crea uno status badge piccolo
  static Widget buildStatusBadge({
    required String text,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  /// Crea un avatar circolare con icona
  static Widget buildAvatar({
    required IconData icon,
    required Color color,
    double size = 40,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: avatarDecoration(color),
      child: Icon(
        icon,
        color: color,
        size: size * 0.55,
      ),
    );
  }
}
