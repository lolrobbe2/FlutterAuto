import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'android_auto_branding.dart';

/// Fullscreen branding-only placeholder for the Android Auto video surface.
///
/// Uses the root Overlay so the splash fills the application window instead
/// of being constrained by the dimensions of FfmpegVideoView or its parents.
///
/// Shows Flutter Auto as the primary identity and the supplied Android Auto
/// horizontal wordmark as the smaller secondary mark.
///
/// No Flutter logo, status message, progress indicator, or connection text.
class FlutterAutoSplashScreen extends StatefulWidget {
  const FlutterAutoSplashScreen({
    super.key,
    this.backgroundColor = const Color(0xFF101820),
    this.foregroundColor = Colors.white,
    this.titleSize = 120,
    this.showAndroidAutoWordmark = true,
  }) : assert(titleSize > 0);

  final Color backgroundColor;
  final Color foregroundColor;
  final double titleSize;
  final bool showAndroidAutoWordmark;

  @override
  State<FlutterAutoSplashScreen> createState() =>
      _FlutterAutoSplashScreenState();
}

class _FlutterAutoSplashScreenState extends State<FlutterAutoSplashScreen> {
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final overlay = Overlay.of(context, rootOverlay: true);

      _overlayEntry = OverlayEntry(
        builder: (context) => Positioned.fill(
          child: _FullscreenBranding(
            backgroundColor: widget.backgroundColor,
            foregroundColor: widget.foregroundColor,
            titleSize: widget.titleSize,
            showAndroidAutoWordmark: widget.showAndroidAutoWordmark,
          ),
        ),
      );

      overlay.insert(_overlayEntry!);
    });
  }

  @override
  void didUpdateWidget(covariant FlutterAutoSplashScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _overlayEntry?.markNeedsBuild();
  }

  @override
  void dispose() {
    _overlayEntry?.remove();
    _overlayEntry?.dispose();
    _overlayEntry = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The visible splash is rendered by the root overlay, not by this
    // potentially size-constrained location in the widget tree.
    return const SizedBox.shrink();
  }
}

class _FullscreenBranding extends StatelessWidget {
  const _FullscreenBranding({
    required this.backgroundColor,
    required this.foregroundColor,
    required this.titleSize,
    required this.showAndroidAutoWordmark,
  });

  final Color backgroundColor;
  final Color foregroundColor;
  final double titleSize;
  final bool showAndroidAutoWordmark;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      child: SizedBox.expand(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final height = constraints.maxHeight;

            final double titleFontSize = math.min(
              titleSize,
              (height * 0.22).clamp(36.0, 104.0).toDouble(),
            );

            // Keep Android Auto secondary, but large enough to be clearly visible.
            final double wordmarkHeight = math.min(
              math.min(height * 0.17, width * 0.095),
              titleFontSize * 0.62,
            );

            return Padding(
              padding: EdgeInsets.symmetric(
                horizontal: width * 0.06,
                vertical: height * 0.05,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Primary branding: Flutter Auto.
                  Expanded(
                    flex: 5,
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Semantics(
                          header: true,
                          child: Text(
                            'Flutter Auto',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: foregroundColor,
                              fontSize: titleFontSize,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                              height: 1.1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  if (showAndroidAutoWordmark) ...[
                    SizedBox(width: width * 0.04),

                    // Secondary branding: Android Auto.
                    Expanded(
                      flex: 6,
                      child: LayoutBuilder(
                        builder: (context, markConstraints) {
                          final availableMarkWidth = math.max(
                            1.0,
                            markConstraints.maxWidth - wordmarkHeight * 2,
                          );

                          return Center(
                            child: AndroidAutoWordmark(
                              backgroundColor: backgroundColor,
                              markWidth: availableMarkWidth,
                              markHeight: wordmarkHeight,
                              clearSpace: wordmarkHeight,
                              variant: AndroidAutoWordmarkVariant.automatic,
                              orientation:
                                  AndroidAutoWordmarkOrientation.automatic,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
