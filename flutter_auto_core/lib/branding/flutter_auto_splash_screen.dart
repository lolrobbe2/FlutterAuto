import 'package:flutter/material.dart';

import 'android_auto_branding.dart';

/// Default Flutter Auto splash/placeholder for the video surface.
///
/// Intended to be used with `FfmpegVideoView(splashScreen: ...)` while no video
/// frame has been rendered yet.
///
/// BRANDING WARNINGS:
/// - The Flutter Auto identity is primary; the Android Auto wordmark is
///   secondary and rendered smaller.
/// - Keep the supplied Android Auto SVG unchanged. Do not tint, crop, skew,
///   stretch, rotate, outline, or add effects to the wordmark.
/// - The wordmark is placed on a solid background with clear space supplied
///   by [AndroidAutoWordmark]. Avoid placing photography, patterns, or other
///   graphics behind it.
/// - Showing this widget does not grant permission to use Google's marks or
///   guarantee brand/legal approval. Confirm the current Google guidelines
///   and any required attribution before distributing marketing materials.
class FlutterAutoSplashScreen extends StatelessWidget {
  const FlutterAutoSplashScreen({
    super.key,
    this.message = '',
    this.backgroundColor = const Color(0xFF101820),
    this.accentColor = const Color(0xFF8EDBFF),
    this.showProgress = true,
    this.showAndroidAutoWordmark = true,
  });

  /// Short status shown beneath the brand lockup.
  final String message;

  /// Solid background used behind the whole splash and wordmark.
  final Color backgroundColor;

  /// Accent used only for Flutter Auto's own UI icon and progress indicator,
  /// never applied to the Android Auto wordmark asset.
  final Color accentColor;

  final bool showProgress;

  /// Set false if the Android Auto mark is not appropriate for a given screen.
  final bool showAndroidAutoWordmark;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: backgroundColor,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bool compact =
              constraints.maxHeight < 350 || constraints.maxWidth < 460;
          final double iconSize = compact ? 36 : 48;
          final double titleSize = compact ? 25 : 32;
          final double markHeight = compact ? 16 : 20;
          final double verticalGap = compact ? 10 : 16;

          return Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(compact ? 12 : 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // This icon is Flutter Auto's own UI motif, not a substitute
                    // or alteration of the Android Auto wordmark.
                    Container(
                      width: iconSize + 20,
                      height: iconSize + 20,
                      decoration: BoxDecoration(
                        color: const Color(0xFF202A35),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.directions_car_filled_rounded,
                        size: iconSize,
                        color: accentColor,
                        semanticLabel: 'Flutter Auto',
                      ),
                    ),
                    SizedBox(height: verticalGap),
                    Semantics(
                      header: true,
                      child: Text(
                        'Flutter Auto',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: titleSize,
                          height: 1.1,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                    SizedBox(height: compact ? 2 : 6),
                    Text(
                      'Your Android Auto display',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: compact ? 12 : 14,
                      ),
                    ),
                    if (showAndroidAutoWordmark) ...[
                      SizedBox(height: verticalGap),
                      // WARNING: Keep this as a single, unmodified official
                      // horizontal wordmark. Flutter Auto remains the larger,
                      // primary identity on this screen.
                      AndroidAutoWordmark(
                        backgroundColor: backgroundColor,
                        markHeight: markHeight,
                        clearSpace: markHeight,
                        variant: AndroidAutoWordmarkVariant.inverse,
                      ),
                    ],
                    SizedBox(height: verticalGap),
                    if (showProgress) ...[
                      SizedBox(
                        width: compact ? 18 : 22,
                        height: compact ? 18 : 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                        ),
                      ),
                      SizedBox(height: compact ? 8 : 12),
                    ],
                    if (message.trim().isNotEmpty)
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.78),
                          fontSize: compact ? 12 : 14,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
