import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../assets/auto_assets.dart';

/// Brand colors shown on Google's Android Auto Partner Marketing Hub.
/// These colors may be used for surrounding UI/backgrounds; do not recolor the
/// Android Auto wordmark itself.
abstract final class AndroidAutoBrandColors {
  AndroidAutoBrandColors._();

  static const Color white = Color(0xFFFFFFFF);
  static const Color green = Color(0xFF34A853);
  static const Color black = Color(0xFF202124);
}

enum AndroidAutoWordmarkVariant {
  /// Select a monochrome asset from the background color.
  automatic,

  /// Official black wordmark asset; intended for white/light backgrounds.
  black,

  /// Official white/inverse wordmark asset; intended for dark or suitable
  /// colored backgrounds.
  inverse,
}

/// Android Auto horizontal wordmark with a solid background and conservative
/// clear space around it.
class AndroidAutoWordmark extends StatelessWidget {
  const AndroidAutoWordmark({
    super.key,
    required this.backgroundColor,
    this.markHeight = 28,
    this.clearSpace,
    this.variant = AndroidAutoWordmarkVariant.automatic,
    this.alignment = Alignment.center,
    this.semanticsLabel = 'Android Auto',
  }) : assert(markHeight > 0),
       assert(clearSpace == null || clearSpace >= markHeight,
           'Clear space should be at least the rendered wordmark height.');

  /// The widget paints this opaque solid color behind and around the mark.
  /// Pass a flat color rather than using the mark over photos/patterns.
  final Color backgroundColor;

  /// Height of the wordmark artwork, excluding the surrounding clear space.
  final double markHeight;

  /// Minimum padding on every side. Defaults to [markHeight], a conservative
  /// proxy for the full height of the capital “A” in the supplied asset.
  final double? clearSpace;

  /// In automatic mode, the color is selected using the background luminance
  /// and saturation. Use explicit variants only when you have checked the
  /// resulting contrast and background against the official guidance.
  final AndroidAutoWordmarkVariant variant;
  final AlignmentGeometry alignment;
  final String semanticsLabel;

  String _resolveAsset() {
    switch (variant) {
      case AndroidAutoWordmarkVariant.black:
        // WARNING: The black wordmark belongs on white/light backgrounds.
        return AutoAssets.androidAutoMarksHorizontalBlack;
      case AndroidAutoWordmarkVariant.inverse:
        // WARNING: The inverse (white) wordmark is for dark or suitable
        // colored backgrounds; it must not disappear against a light surface.
        return AutoAssets.androidAutoMarksHorizontalInverse;
      case AndroidAutoWordmarkVariant.automatic:
        final hsl = HSLColor.fromColor(backgroundColor);
        final luminance = backgroundColor.computeLuminance();
        final whiteContrast = _contrastRatio(
          AndroidAutoBrandColors.white,
          backgroundColor,
        );

        // Google's guidance prefers black on light backgrounds and white on
        // dark/colored backgrounds. Prefer the inverse on colored surfaces
        // when its contrast remains reasonable; otherwise choose the legible
        // monochrome option. This is a UI heuristic, not a replacement for
        // checking the actual creative/background with the brand guidance.
        final bool isColored = hsl.saturation >= 0.16;
        final bool useInverse =
            (isColored && whiteContrast >= 3.0) || luminance < 0.30;
        return useInverse
            ? AutoAssets.androidAutoMarksHorizontalInverse
            : AutoAssets.androidAutoMarksHorizontalBlack;
    }
  }

  static double _contrastRatio(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final lighter = la > lb ? la : lb;
    final darker = la > lb ? lb : la;
    return (lighter + 0.05) / (darker + 0.05);
  }

  @override
  Widget build(BuildContext context) {
    final asset = _resolveAsset();
    final space = clearSpace ?? markHeight;

    // WARNING — Keep the original SVG intact. Do not tint/recolor, skew,
    // rotate, blur, outline, shadow, stretch, or change its proportions/weight.
    // Horizontal is the preferred wordmark; a stacked version is not created
    // from these horizontal assets.
    return ColoredBox(
      color: backgroundColor,
      child: Padding(
        // WARNING — Google's minimum clear space is the full height of the
        // “A” on every side. The default uses the artwork height as a
        // conservative approximation; pass a larger measured value if needed.
        padding: EdgeInsets.all(space),
        child: Align(
          alignment: alignment,
          child: SvgPicture.asset(
            asset,
            height: markHeight,
            fit: BoxFit.contain,
            semanticsLabel: semanticsLabel,
          ),
        ),
      ),
    );
  }
}

/// Android Auto app launcher icon.
///
/// WARNING — Google's visual identity guidance limits this icon to UI screens
/// (or marketing collateral explicitly promoting/referring to the Android Auto
/// mobile app). Do not use it as a replacement for the Android Auto wordmark.
class AndroidAutoLauncherIcon extends StatelessWidget {
  const AndroidAutoLauncherIcon({
    super.key,
    required this.size,
    this.backgroundColor,
    this.padding = const EdgeInsets.all(0),
    this.fit = BoxFit.contain,
  }) : assert(size > 0);

  final double size;

  /// Optional solid surface around the icon. The logo asset itself is unchanged.
  final Color? backgroundColor;
  final EdgeInsetsGeometry padding;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final icon = Padding(
      padding: padding,
      child: Image.asset(
        AutoAssets.aaIcon,
        width: size,
        height: size,
        fit: fit,
        semanticLabel: 'Android Auto app launcher icon',
      ),
    );

    if (backgroundColor == null) return icon;
    return ColoredBox(color: backgroundColor!, child: icon);
  }
}

/// Optional partner lockup that keeps the Android Auto wordmark artwork
/// shorter than the supplied partner logo artwork.
///
/// WARNING — Google's guidance says your own logo must remain the primary
/// branding element and Android Auto must be secondary/smaller. Only use one
/// Android Auto wordmark per frame/screen. If several ingredient/partner brands
/// are shown, their placement and sizing must be equal. Review the entire
/// composition manually; a widget cannot inspect surrounding logos or screens.
class AndroidAutoPartnerLockup extends StatelessWidget {
  const AndroidAutoPartnerLockup({
    super.key,
    required this.partnerLogo,
    required this.partnerLogoHeight,
    required this.androidAutoMarkHeight,
    required this.backgroundColor,
    this.gap = 20,
    this.wordmarkVariant = AndroidAutoWordmarkVariant.automatic,
  }) : assert(partnerLogoHeight > 0),
       assert(androidAutoMarkHeight > 0),
       assert(androidAutoMarkHeight < partnerLogoHeight,
           'Android Auto wordmark should be smaller than the partner logo.'),
       assert(gap >= 0);

  final Widget partnerLogo;
  final double partnerLogoHeight;
  final double androidAutoMarkHeight;
  final Color backgroundColor;
  final double gap;
  final AndroidAutoWordmarkVariant wordmarkVariant;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(height: partnerLogoHeight, child: partnerLogo),
        SizedBox(width: gap),
        AndroidAutoWordmark(
          backgroundColor: backgroundColor,
          markHeight: androidAutoMarkHeight,
          variant: wordmarkVariant,
        ),
      ],
    );
  }
}

/// Legal disclosure helper for marketing/partner creatives that use the
/// Android Auto wordmark. Provide the exact attribution statement generated by
/// Google's Legal line generator for the granted permission and chosen locale.
///
/// WARNING — The Partner Marketing Hub says Google brand features require
/// explicit permission and creative approval. This widget does not grant
/// permission or guarantee legal/brand compliance. For a wordmark creative,
/// include the applicable attribution line and smartphone-requirements text;
/// check the current legal requirements for each medium and locale.
class AndroidAutoMarketingLegalFooter extends StatelessWidget {
  const AndroidAutoMarketingLegalFooter({
    super.key,
    required this.attributionStatement,
    this.textStyle,
    this.textAlign = TextAlign.center,
    this.showAvailabilityDisclaimer = false,
  }) : assert(attributionStatement != '');

  /// Use the exact approved attribution text; do not invent or paraphrase it.
  final String attributionStatement;
  final TextStyle? textStyle;
  final TextAlign textAlign;
  final bool showAvailabilityDisclaimer;

  static const String smartphoneRequirements =
      'Compatible Android phone and compatible active data plan required.';

  static const String availabilityDisclaimer =
      'Some features may not be available in all countries and may vary by car '
      'and/or device manufacturer. Internet connection may be required. '
      'Use features when safe to do so.';

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = textStyle ?? Theme.of(context).textTheme.bodySmall;
    final lines = <String>[
      attributionStatement.trim(),
      smartphoneRequirements,
      if (showAvailabilityDisclaimer) availabilityDisclaimer,
    ];

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Text(
        lines.join('\n'),
        style: effectiveStyle,
        textAlign: textAlign,
      ),
    );
  }
}

/*
WARNING — Android Auto visual identity rules based on Google's Partner
Marketing Hub (visual identity, color palette, and legal requirements pages):

• Prefer the horizontal wordmark. Use an official stacked asset only when space
  is limited; never manufacture a stacked mark from the horizontal SVG.
• Use only the supplied approved monochrome black/white wordmark assets. Keep
  the mark black on white/light backgrounds and inverse white on dark or
  appropriately colored backgrounds, always with sufficient contrast.
• Keep clear space on every side equal to the full height of the capital “A”.
• Do not recolor, alter the weight, stretch, rotate, blur, outline, or add a
  shadow/effect to the wordmark. Do not use the app icon or Android bot in its
  place; do not use the Google logo, Android bot, Android wordmark, or outdated
  Android Auto marks in association with Android Auto.
• Avoid busy patterns and imagery unless enough contrast is guaranteed.
• Keep your own logo as the primary branding element and Android Auto as the
  secondary ingredient brand. Android Auto's wordmark must be smaller than the
  partner's logo. Use one wordmark per frame/screen. Give other partner brands
  equal placement and sizing when shown together.
• The launcher icon is for UI screens, or for marketing material that explicitly
  promotes/refers to the Android Auto mobile app; do not substitute it for the
  wordmark. The “Works with Android Auto” badge is only for side-by-side use
  with other partner/competitor ingredient badges. That badge is not bundled
  in this app's assets.
• Marketing creative using Android Auto trademarks requires explicit permission
  and approval from Google's brand team. The current legal page requires an
  attribution statement and smartphone-requirements disclaimer when using the
  Android Auto wordmark. Use Google's Legal line generator for exact attribution.
  For USB-connected Android Auto marketing, the published short requirement is:
  “Compatible Android phone and compatible active data plan required.”
• Where “Android Auto” appears in marketing text, the current legal guidance
  says to use “Android Auto™” on the first/most prominent textual mention,
  except on social media posts; don't put ™ after “Android” when referring to
  Android Auto. Check current/localized requirements before publication.

These widgets enforce some layout and background choices programmatically, but
cannot detect every use across a whole screen/app, determine whether a creative
has been approved, verify trademark permissions, or replace Google's current
brand/legal guidance. Always review the complete composition.

Sources:
https://partnermarketinghub.withgoogle.com/brands/android-auto/visual-identity/visual-identity/
https://partnermarketinghub.withgoogle.com/brands/android-auto/visual-identity/color-palette/
https://partnermarketinghub.withgoogle.com/brands/android-auto/legal-and-trademarks/legal-requirements/
*/
