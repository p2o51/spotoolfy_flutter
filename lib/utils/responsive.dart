import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 响应式设计断点常量
/// 用于在整个应用中统一响应式行为
abstract class Breakpoints {
  /// 极窄设备 (小型手机，如 iPhone SE)
  static const double compact = 350;

  /// 标准手机宽度
  static const double mobile = 400;

  /// 平板/大屏幕手机
  static const double tablet = 600;

  /// 桌面/超宽屏幕
  static const double desktop = 900;
}

/// 设备类型枚举
enum DeviceType {
  compact,
  mobile,
  tablet,
  desktop,
}

/// 页面布局分类
enum ResponsivePageType {
  shell,
  browse,
  detail,
  modal,
  preview,
}

/// 二级页面显示模式
enum SecondaryPageMode {
  fullScreen,
  sideSheet,
  centerDialog,
  bottomSheet,
}

enum AdaptiveModalContentLayout {
  wrapContent,
  fillHeight,
}

/// 统一的页面布局规格
class ResponsiveLayoutSpec {
  const ResponsiveLayoutSpec({
    required this.type,
    required this.maxWidth,
    required this.horizontalPadding,
    required this.preferTwoPane,
    required this.modalWidth,
    required this.modalMaxHeightFactor,
    required this.defaultMinTileWidth,
  });

  final ResponsivePageType type;
  final double maxWidth;
  final double horizontalPadding;
  final bool preferTwoPane;
  final double modalWidth;
  final double modalMaxHeightFactor;
  final double defaultMinTileWidth;

  EdgeInsets pagePadding({
    double vertical = 0,
  }) {
    return EdgeInsets.symmetric(
      horizontal: horizontalPadding,
      vertical: vertical,
    );
  }
}

extension ResponsiveExtension on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;

  double get screenHeight => MediaQuery.sizeOf(this).height;

  Size get screenSize => MediaQuery.sizeOf(this);

  bool get isCompact => screenWidth < Breakpoints.compact;

  bool get isNarrow => screenWidth < Breakpoints.mobile;

  bool get isLargeScreen => screenWidth >= Breakpoints.tablet;

  bool get isDesktop => screenWidth >= Breakpoints.desktop;

  bool get isMobile => screenWidth < Breakpoints.tablet;

  DeviceType get deviceType {
    if (screenWidth < Breakpoints.compact) return DeviceType.compact;
    if (screenWidth < Breakpoints.tablet) return DeviceType.mobile;
    if (screenWidth < Breakpoints.desktop) return DeviceType.tablet;
    return DeviceType.desktop;
  }

  int get gridCrossAxisCount {
    return adaptiveColumns(
      minTileWidth: layoutType(ResponsivePageType.browse).defaultMinTileWidth,
      min: 3,
      max: 6,
    );
  }

  double get horizontalPadding {
    return layoutType(ResponsivePageType.browse).horizontalPadding;
  }

  T responsive<T>({
    required T mobile,
    T? compact,
    T? tablet,
    T? desktop,
  }) {
    return switch (deviceType) {
      DeviceType.compact => compact ?? mobile,
      DeviceType.mobile => mobile,
      DeviceType.tablet => tablet ?? mobile,
      DeviceType.desktop => desktop ?? tablet ?? mobile,
    };
  }

  ResponsiveLayoutSpec layoutType(ResponsivePageType type) {
    final padding = responsive<double>(
      compact: 12,
      mobile: 16,
      tablet: 24,
      desktop: 32,
    );

    switch (type) {
      case ResponsivePageType.shell:
        return ResponsiveLayoutSpec(
          type: type,
          maxWidth: double.infinity,
          horizontalPadding: padding,
          preferTwoPane: isLargeScreen,
          modalWidth: responsive(
            mobile: 420,
            tablet: 520,
            desktop: 560,
          ),
          modalMaxHeightFactor: isLargeScreen ? 0.88 : 0.92,
          defaultMinTileWidth: 220,
        );
      case ResponsivePageType.browse:
        return ResponsiveLayoutSpec(
          type: type,
          maxWidth: responsive(
            mobile: double.infinity,
            tablet: 1040,
            desktop: 1280,
          ),
          horizontalPadding: padding,
          preferTwoPane: isLargeScreen,
          modalWidth: responsive(
            mobile: 420,
            tablet: 520,
            desktop: 560,
          ),
          modalMaxHeightFactor: isLargeScreen ? 0.88 : 0.92,
          defaultMinTileWidth: responsive(
            compact: 112,
            mobile: 132,
            tablet: 164,
            desktop: 176,
          ),
        );
      case ResponsivePageType.detail:
        return ResponsiveLayoutSpec(
          type: type,
          maxWidth: responsive(
            mobile: double.infinity,
            tablet: 960,
            desktop: 1080,
          ),
          horizontalPadding: padding,
          preferTwoPane: isLargeScreen,
          modalWidth: responsive(
            mobile: 420,
            tablet: 520,
            desktop: 560,
          ),
          modalMaxHeightFactor: isLargeScreen ? 0.9 : 0.94,
          defaultMinTileWidth: 260,
        );
      case ResponsivePageType.modal:
        return ResponsiveLayoutSpec(
          type: type,
          maxWidth: responsive(
            mobile: 560,
            tablet: 560,
            desktop: 620,
          ),
          horizontalPadding: responsive(
            compact: 12,
            mobile: 16,
            tablet: 20,
            desktop: 24,
          ),
          preferTwoPane: false,
          modalWidth: responsive(
            mobile: 420,
            tablet: 500,
            desktop: 560,
          ),
          modalMaxHeightFactor: isLargeScreen ? 0.86 : 0.92,
          defaultMinTileWidth: 220,
        );
      case ResponsivePageType.preview:
        return ResponsiveLayoutSpec(
          type: type,
          maxWidth: responsive(
            mobile: double.infinity,
            tablet: 980,
            desktop: 1120,
          ),
          horizontalPadding: padding,
          preferTwoPane: false,
          modalWidth: responsive(
            mobile: 420,
            tablet: 560,
            desktop: 620,
          ),
          modalMaxHeightFactor: isLargeScreen ? 0.9 : 0.94,
          defaultMinTileWidth: 180,
        );
    }
  }

  int adaptiveColumns({
    required double minTileWidth,
    int min = 1,
    int max = 6,
  }) {
    final availableWidth = math.max(
      0,
      screenWidth -
          (layoutType(ResponsivePageType.browse).horizontalPadding * 2),
    );
    if (availableWidth <= 0) {
      return min;
    }
    final columns = (availableWidth / minTileWidth).floor();
    return columns.clamp(min, max);
  }
}

class ResponsiveBuilder extends StatelessWidget {
  const ResponsiveBuilder({
    super.key,
    required this.mobile,
    this.compact,
    this.tablet,
    this.desktop,
  });

  final Widget mobile;
  final Widget? compact;
  final Widget? tablet;
  final Widget? desktop;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width >= Breakpoints.desktop && desktop != null) {
          return desktop!;
        }
        if (width >= Breakpoints.tablet && tablet != null) {
          return tablet!;
        }
        if (width < Breakpoints.compact && compact != null) {
          return compact!;
        }
        return mobile;
      },
    );
  }
}

class ResponsiveValue<T> extends StatelessWidget {
  const ResponsiveValue({
    super.key,
    required this.mobile,
    this.compact,
    this.tablet,
    this.desktop,
    required this.builder,
  });

  final T mobile;
  final T? compact;
  final T? tablet;
  final T? desktop;
  final Widget Function(BuildContext context, T value) builder;

  @override
  Widget build(BuildContext context) {
    final value = context.responsive<T>(
      mobile: mobile,
      compact: compact,
      tablet: tablet,
      desktop: desktop,
    );
    return builder(context, value);
  }
}

class ResponsiveGap extends StatelessWidget {
  const ResponsiveGap({
    super.key,
    this.compact = 8,
    this.mobile = 12,
    this.tablet = 16,
    this.desktop = 24,
    this.axis = Axis.horizontal,
  });

  final double compact;
  final double mobile;
  final double tablet;
  final double desktop;
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    final size = context.responsive<double>(
      compact: compact,
      mobile: mobile,
      tablet: tablet,
      desktop: desktop,
    );

    return axis == Axis.horizontal
        ? SizedBox(width: size)
        : SizedBox(height: size);
  }
}

class ResponsivePadding {
  static EdgeInsets horizontal(
    BuildContext context, {
    ResponsivePageType pageType = ResponsivePageType.browse,
  }) {
    final padding = context.layoutType(pageType).horizontalPadding;
    return EdgeInsets.symmetric(horizontal: padding);
  }

  static EdgeInsets all(
    BuildContext context, {
    ResponsivePageType pageType = ResponsivePageType.browse,
  }) {
    final padding = context.layoutType(pageType).horizontalPadding;
    return EdgeInsets.all(padding);
  }

  static EdgeInsets symmetric(
    BuildContext context, {
    ResponsivePageType pageType = ResponsivePageType.browse,
    double? horizontalCompact,
    double? horizontalMobile,
    double? horizontalTablet,
    double? verticalCompact,
    double? verticalMobile,
    double? verticalTablet,
  }) {
    final horizontal = context.responsive<double>(
      compact: horizontalCompact ?? 8,
      mobile:
          horizontalMobile ?? context.layoutType(pageType).horizontalPadding,
      tablet:
          horizontalTablet ?? context.layoutType(pageType).horizontalPadding,
      desktop:
          horizontalTablet ?? context.layoutType(pageType).horizontalPadding,
    );
    final vertical = context.responsive<double>(
      compact: verticalCompact ?? 8,
      mobile: verticalMobile ?? 12,
      tablet: verticalTablet ?? 16,
      desktop: verticalTablet ?? 20,
    );
    return EdgeInsets.symmetric(horizontal: horizontal, vertical: vertical);
  }
}

class ResponsiveNavigation {
  static Future<T?> showSecondaryPage<T>({
    required BuildContext context,
    required Widget child,
    SecondaryPageMode preferredMode = SecondaryPageMode.sideSheet,
    String? title,
    double? maxWidth,
    bool showCloseButton = true,
    bool barrierDismissible = true,
  }) {
    final spec = context.layoutType(ResponsivePageType.detail);
    final resolvedMaxWidth = maxWidth ?? spec.modalWidth;
    final isLarge = spec.preferTwoPane;

    if (!isLarge) {
      if (preferredMode == SecondaryPageMode.bottomSheet) {
        return _showBottomSheet<T>(
          context: context,
          child: child,
          title: title,
          showCloseButton: showCloseButton,
          pageType: ResponsivePageType.detail,
        );
      }
      return _showFullScreen<T>(
        context: context,
        child: child,
        title: title,
      );
    }

    return switch (preferredMode) {
      SecondaryPageMode.fullScreen => _showFullScreen<T>(
          context: context,
          child: child,
          title: title,
        ),
      SecondaryPageMode.sideSheet => _showSideSheet<T>(
          context: context,
          child: child,
          title: title,
          maxWidth: resolvedMaxWidth,
          showCloseButton: showCloseButton,
          barrierDismissible: barrierDismissible,
          pageType: ResponsivePageType.detail,
        ),
      SecondaryPageMode.centerDialog => _showCenterDialog<T>(
          context: context,
          child: child,
          title: title,
          maxWidth: resolvedMaxWidth,
          showCloseButton: showCloseButton,
          barrierDismissible: barrierDismissible,
          pageType: ResponsivePageType.detail,
        ),
      SecondaryPageMode.bottomSheet => _showBottomSheet<T>(
          context: context,
          child: child,
          title: title,
          showCloseButton: showCloseButton,
          pageType: ResponsivePageType.detail,
        ),
    };
  }

  static Future<T?> showAdaptiveModalPage<T>({
    required BuildContext context,
    required Widget child,
    String? title,
    double? maxWidth,
    bool showCloseButton = true,
    bool showDragHandle = true,
    bool barrierDismissible = true,
    SecondaryPageMode largeScreenMode = SecondaryPageMode.centerDialog,
    AdaptiveModalContentLayout contentLayout =
        AdaptiveModalContentLayout.wrapContent,
  }) {
    final spec = context.layoutType(ResponsivePageType.modal);
    final resolvedMaxWidth = maxWidth ?? spec.modalWidth;

    if (!context.isLargeScreen) {
      return _showBottomSheet<T>(
        context: context,
        child: child,
        title: title,
        showCloseButton: showCloseButton,
        showDragHandle: showDragHandle,
        contentLayout: contentLayout,
        pageType: ResponsivePageType.modal,
      );
    }

    if (largeScreenMode == SecondaryPageMode.sideSheet) {
      return _showSideSheet<T>(
        context: context,
        child: child,
        title: title,
        maxWidth: resolvedMaxWidth,
        showCloseButton: showCloseButton,
        barrierDismissible: barrierDismissible,
        contentLayout: contentLayout,
        pageType: ResponsivePageType.modal,
      );
    }

    return _showCenterDialog<T>(
      context: context,
      child: child,
      title: title,
      maxWidth: resolvedMaxWidth,
      showCloseButton: showCloseButton,
      barrierDismissible: barrierDismissible,
      contentLayout: contentLayout,
      pageType: ResponsivePageType.modal,
    );
  }

  static Future<T?> showAdaptiveDialog<T>({
    required BuildContext context,
    required Widget child,
    String? title,
    double? maxWidth,
    bool showCloseButton = false,
    bool barrierDismissible = true,
  }) {
    return showAdaptiveModalPage<T>(
      context: context,
      child: child,
      title: title,
      maxWidth: maxWidth,
      showCloseButton: showCloseButton,
      barrierDismissible: barrierDismissible,
      largeScreenMode: SecondaryPageMode.centerDialog,
    );
  }

  static Future<T?> _showFullScreen<T>({
    required BuildContext context,
    required Widget child,
    String? title,
  }) {
    return Navigator.of(context).push<T>(
      MaterialPageRoute(
        builder: (context) => title != null
            ? Scaffold(
                appBar: AppBar(title: Text(title)),
                body: child,
              )
            : child,
      ),
    );
  }

  static Future<T?> _showSideSheet<T>({
    required BuildContext context,
    required Widget child,
    required ResponsivePageType pageType,
    String? title,
    required double maxWidth,
    bool showCloseButton = true,
    bool barrierDismissible = true,
    AdaptiveModalContentLayout contentLayout =
        AdaptiveModalContentLayout.fillHeight,
  }) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            elevation: 16,
            color: Theme.of(context).colorScheme.surface,
            child: SizedBox(
              width:
                  math.min(maxWidth, MediaQuery.sizeOf(context).width * 0.82),
              child: _buildSheetContent(
                context: context,
                child: child,
                title: title,
                showCloseButton: showCloseButton,
                contentLayout: contentLayout,
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(
            CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
          ),
          child: child,
        );
      },
    );
  }

  static Future<T?> _showCenterDialog<T>({
    required BuildContext context,
    required Widget child,
    required ResponsivePageType pageType,
    String? title,
    required double maxWidth,
    bool showCloseButton = true,
    bool barrierDismissible = true,
    AdaptiveModalContentLayout contentLayout =
        AdaptiveModalContentLayout.fillHeight,
  }) {
    final spec = context.layoutType(pageType);
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: SizedBox(
          width: math.min(maxWidth, MediaQuery.sizeOf(context).width * 0.9),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight:
                  MediaQuery.sizeOf(context).height * spec.modalMaxHeightFactor,
            ),
            child: _buildSheetContent(
              context: context,
              child: child,
              title: title,
              showCloseButton: showCloseButton,
              contentLayout: contentLayout,
            ),
          ),
        ),
      ),
    );
  }

  static Future<T?> _showBottomSheet<T>({
    required BuildContext context,
    required Widget child,
    required ResponsivePageType pageType,
    String? title,
    bool showCloseButton = true,
    bool showDragHandle = true,
    AdaptiveModalContentLayout contentLayout =
        AdaptiveModalContentLayout.fillHeight,
  }) {
    final spec = context.layoutType(pageType);
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      constraints: BoxConstraints(
        maxHeight:
            MediaQuery.sizeOf(context).height * spec.modalMaxHeightFactor,
      ),
      builder: (context) => DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: _buildSheetContent(
          context: context,
          child: child,
          title: title,
          showCloseButton: showCloseButton,
          showDragHandle: showDragHandle,
          contentLayout: contentLayout,
        ),
      ),
    );
  }

  static Widget _buildSheetContent({
    required BuildContext context,
    required Widget child,
    String? title,
    bool showCloseButton = true,
    bool showDragHandle = false,
    AdaptiveModalContentLayout contentLayout =
        AdaptiveModalContentLayout.fillHeight,
  }) {
    if (title == null && !showCloseButton && !showDragHandle) {
      return child;
    }

    final body = switch (contentLayout) {
      AdaptiveModalContentLayout.wrapContent =>
        Flexible(fit: FlexFit.loose, child: child),
      AdaptiveModalContentLayout.fillHeight => Expanded(child: child),
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showDragHandle)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        if (title != null || showCloseButton)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor,
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              children: [
                if (showCloseButton)
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                if (title != null)
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (title == null) const Spacer(),
              ],
            ),
          ),
        body,
      ],
    );
  }
}

class ResponsivePageContainer extends StatelessWidget {
  const ResponsivePageContainer({
    super.key,
    required this.child,
    this.pageType = ResponsivePageType.browse,
    this.maxWidth,
    this.padding,
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final ResponsivePageType pageType;
  final double? maxWidth;
  final EdgeInsetsGeometry? padding;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final spec = context.layoutType(pageType);
    final resolvedMaxWidth = maxWidth ?? spec.maxWidth;
    final effectiveChild = padding != null
        ? Padding(
            padding: padding!,
            child: child,
          )
        : child;

    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: resolvedMaxWidth),
        child: effectiveChild,
      ),
    );
  }
}
