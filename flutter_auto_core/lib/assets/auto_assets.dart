import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Centralized access to Android Auto assets.
abstract final class AutoAssets {
  AutoAssets._();

  // Asset paths
  static const String aaIcon = 'assets/image/aa_icon.png';

  static const String androidAutoMarksHorizontalBlack =
      'assets/image/Android_auto_marks_horizontal_Black.svg';

  static const String androidAutoMarksHorizontalInverse =
      'assets/image/Android_auto_marks_horizontal_Inverse.svg';

  // ---------------------------------------------------------------------------
  // Raw asset loading
  // ---------------------------------------------------------------------------

  /// Load any asset as raw bytes.
  static Future<Uint8List> loadBytes(String assetPath) async {
    final data = await rootBundle.load(assetPath);

    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  /// Load an asset as text. Useful for reading SVG source.
  static Future<String> loadString(String assetPath) {
    return rootBundle.loadString(assetPath);
  }

  /// Load any asset as ByteData.
  static Future<ByteData> load(String assetPath) {
    return rootBundle.load(assetPath);
  }

  // ---------------------------------------------------------------------------
  // Android Auto icon
  // ---------------------------------------------------------------------------

  /// Returns an ImageProvider for the Android Auto icon.
  static ImageProvider<Object> get aaIconProvider => const AssetImage(aaIcon);

  /// Builds the Android Auto icon widget.
  static Widget aaIconImage({
    double? width,
    double? height,
    BoxFit fit = BoxFit.contain,
    FilterQuality filterQuality = FilterQuality.medium,
  }) {
    return Image.asset(
      aaIcon,
      width: width,
      height: height,
      fit: fit,
      filterQuality: filterQuality,
    );
  }

  // ---------------------------------------------------------------------------
  // Android Auto horizontal marks — black
  // ---------------------------------------------------------------------------

  static Future<String> loadAndroidAutoMarksBlack() {
    return loadString(androidAutoMarksHorizontalBlack);
  }

  static Widget androidAutoMarksBlack({
    double? width,
    double? height,
    BoxFit fit = BoxFit.contain,
    String? semanticsLabel,
  }) {
    return SvgPicture.asset(
      androidAutoMarksHorizontalBlack,
      width: width,
      height: height,
      fit: fit,
      semanticsLabel: semanticsLabel ?? 'Android Auto',
    );
  }

  // ---------------------------------------------------------------------------
  // Android Auto horizontal marks — inverse
  // ---------------------------------------------------------------------------

  static Future<String> loadAndroidAutoMarksInverse() {
    return loadString(androidAutoMarksHorizontalInverse);
  }

  static Widget androidAutoMarksInverse({
    double? width,
    double? height,
    BoxFit fit = BoxFit.contain,
    String? semanticsLabel,
  }) {
    return SvgPicture.asset(
      androidAutoMarksHorizontalInverse,
      width: width,
      height: height,
      fit: fit,
      semanticsLabel: semanticsLabel ?? 'Android Auto',
    );
  }
}
