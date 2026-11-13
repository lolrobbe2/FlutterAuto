import 'package:material_ui/material_ui.dart';

/// Layout tokens for the built-in headunit component renderer.
///
/// Add this extension to [ThemeData.extensions] to customize the standard UI
/// without requiring individual applications to choose their own styling.
class HeadunitUiTheme extends ThemeExtension<HeadunitUiTheme> {
  final double pagePadding;
  final double sectionSpacing;
  final double cardRadius;
  final double carouselItemWidth;
  final double carouselHeight;
  final double buttonHeight;

  const HeadunitUiTheme({
    this.pagePadding = 24,
    this.sectionSpacing = 18,
    this.cardRadius = 20,
    this.carouselItemWidth = 224,
    this.carouselHeight = 224,
    this.buttonHeight = 52,
  }) : assert(pagePadding >= 0),
       assert(sectionSpacing >= 0),
       assert(cardRadius >= 0),
       assert(carouselItemWidth > 0),
       assert(carouselHeight > 0),
       assert(buttonHeight > 0);

  @override
  HeadunitUiTheme copyWith({
    double? pagePadding,
    double? sectionSpacing,
    double? cardRadius,
    double? carouselItemWidth,
    double? carouselHeight,
    double? buttonHeight,
  }) {
    return HeadunitUiTheme(
      pagePadding: pagePadding ?? this.pagePadding,
      sectionSpacing: sectionSpacing ?? this.sectionSpacing,
      cardRadius: cardRadius ?? this.cardRadius,
      carouselItemWidth: carouselItemWidth ?? this.carouselItemWidth,
      carouselHeight: carouselHeight ?? this.carouselHeight,
      buttonHeight: buttonHeight ?? this.buttonHeight,
    );
  }

  @override
  HeadunitUiTheme lerp(covariant HeadunitUiTheme? other, double t) {
    if (other == null) return this;
    return HeadunitUiTheme(
      pagePadding: _lerp(pagePadding, other.pagePadding, t),
      sectionSpacing: _lerp(sectionSpacing, other.sectionSpacing, t),
      cardRadius: _lerp(cardRadius, other.cardRadius, t),
      carouselItemWidth: _lerp(carouselItemWidth, other.carouselItemWidth, t),
      carouselHeight: _lerp(carouselHeight, other.carouselHeight, t),
      buttonHeight: _lerp(buttonHeight, other.buttonHeight, t),
    );
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;
}
