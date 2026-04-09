import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DeviceType
// ─────────────────────────────────────────────────────────────────────────────

enum DeviceType { mobile, tablet, desktop, tv }

// ─────────────────────────────────────────────────────────────────────────────
// DeviceInfo
// ─────────────────────────────────────────────────────────────────────────────

class DeviceInfo {
  final DeviceType type;
  final bool isLandscape;
  final double width;
  final double height;

  const DeviceInfo({
    required this.type,
    required this.isLandscape,
    required this.width,
    required this.height,
  });

  bool get isMobile  => type == DeviceType.mobile;
  bool get isTablet  => type == DeviceType.tablet;
  bool get isDesktop => type == DeviceType.desktop;
  bool get isTV      => type == DeviceType.tv;
}

// ─────────────────────────────────────────────────────────────────────────────
// getDeviceInfo
// ─────────────────────────────────────────────────────────────────────────────

/// Breakpoints:
///   mobile  : width < 600
///   tablet  : 600 ≤ width < 1000
///   desktop : 1000 ≤ width < 1280, or desktop OS platform
///   tv      : width ≥ 1280 in landscape (Android TV, large display)
DeviceInfo getDeviceInfo(BuildContext context) {
  final size        = MediaQuery.sizeOf(context);
  final w           = size.width;
  final h           = size.height;
  final isLandscape = w > h;

  final DeviceType type;
  if (w >= 1280 && isLandscape) {
    type = DeviceType.tv;
  } else if (w >= 1000) {
    type = DeviceType.desktop;
  } else if (w >= 600) {
    type = DeviceType.tablet;
  } else {
    type = DeviceType.mobile;
  }

  return DeviceInfo(type: type, isLandscape: isLandscape, width: w, height: h);
}

// ─────────────────────────────────────────────────────────────────────────────
// ResponsiveGrid
// ─────────────────────────────────────────────────────────────────────────────

class ResponsiveGrid {
  ResponsiveGrid._();

  /// Columns for poster/card grids (series, movies).
  static int getGridColumns(DeviceInfo device) => switch (device.type) {
        DeviceType.mobile  => 2,
        DeviceType.tablet  => device.isLandscape ? 4 : 3,
        DeviceType.desktop => 4,
        DeviceType.tv      => 5,
      };

  /// Columns for channel list tiles (wider cards).
  static int getChannelColumns(DeviceInfo device) => switch (device.type) {
        DeviceType.mobile  => 1,
        DeviceType.tablet  => 2,
        DeviceType.desktop => 3,
        DeviceType.tv      => 4,
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// ResponsiveSpacing
// ─────────────────────────────────────────────────────────────────────────────

class ResponsiveSpacing {
  ResponsiveSpacing._();

  static EdgeInsets getContentPadding(DeviceInfo device) => switch (device.type) {
        DeviceType.mobile  => const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        DeviceType.tablet  => const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        DeviceType.desktop => const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        DeviceType.tv      => const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
      };

  static double getItemSpacing(DeviceInfo device) => switch (device.type) {
        DeviceType.mobile  => 8.0,
        DeviceType.tablet  => 12.0,
        DeviceType.desktop => 16.0,
        DeviceType.tv      => 20.0,
      };

  static double getTitleFontSize(DeviceInfo device) => switch (device.type) {
        DeviceType.mobile  => 18.0,
        DeviceType.tablet  => 22.0,
        DeviceType.desktop => 26.0,
        DeviceType.tv      => 32.0,
      };

  static double getBodyFontSize(DeviceInfo device) => switch (device.type) {
        DeviceType.mobile  => 14.0,
        DeviceType.tablet  => 15.0,
        DeviceType.desktop => 16.0,
        DeviceType.tv      => 20.0,
      };

  static double getAppBarHeight(DeviceInfo device) => switch (device.type) {
        DeviceType.mobile  => 56.0,
        DeviceType.tablet  => 64.0,
        DeviceType.desktop => 64.0,
        DeviceType.tv      => 80.0,
      };

  static double getButtonHeight(DeviceInfo device) => switch (device.type) {
        DeviceType.mobile  => 44.0,
        DeviceType.tablet  => 48.0,
        DeviceType.desktop => 52.0,
        DeviceType.tv      => 60.0,
      };

  static double getIconSize(DeviceInfo device) => switch (device.type) {
        DeviceType.mobile  => 22.0,
        DeviceType.tablet  => 24.0,
        DeviceType.desktop => 26.0,
        DeviceType.tv      => 36.0,
      };

  /// Fixed row height for channel tiles inside a multi-column grid.
  static double getChannelTileHeight(DeviceInfo device) => switch (device.type) {
        DeviceType.mobile  => 72.0,
        DeviceType.tablet  => 76.0,
        DeviceType.desktop => 76.0,
        DeviceType.tv      => 96.0,
      };
}
