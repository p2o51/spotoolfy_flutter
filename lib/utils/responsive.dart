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
  /// 极窄设备 (< 350px)
  compact,

  /// 手机 (350px - 600px)
  mobile,

  /// 平板 (600px - 900px)
  tablet,

  /// 桌面 (> 900px)
  desktop,
}

/// 响应式设计工具扩展
extension ResponsiveExtension on BuildContext {
  /// 获取屏幕宽度
  double get screenWidth => MediaQuery.of(this).size.width;

  /// 获取屏幕高度
  double get screenHeight => MediaQuery.of(this).size.height;

  /// 获取屏幕尺寸
  Size get screenSize => MediaQuery.of(this).size;

  /// 判断是否为极窄屏幕 (< 350px)
  bool get isCompact => screenWidth < Breakpoints.compact;

  /// 判断是否为窄屏幕 (< 400px)
  bool get isNarrow => screenWidth < Breakpoints.mobile;

  /// 判断是否为大屏幕 (>= 600px)
  bool get isLargeScreen => screenWidth >= Breakpoints.tablet;

  /// 判断是否为超大屏幕 (>= 900px)
  bool get isDesktop => screenWidth >= Breakpoints.desktop;

  /// 判断是否为移动设备 (< 600px)
  bool get isMobile => screenWidth < Breakpoints.tablet;

  /// 获取当前设备类型
  DeviceType get deviceType {
    if (screenWidth < Breakpoints.compact) return DeviceType.compact;
    if (screenWidth < Breakpoints.tablet) return DeviceType.mobile;
    if (screenWidth < Breakpoints.desktop) return DeviceType.tablet;
    return DeviceType.desktop;
  }

  /// 根据屏幕宽度返回网格列数
  /// - compact/mobile: 3列
  /// - tablet: 5列
  /// - desktop: 6列
  int get gridCrossAxisCount {
    return switch (screenWidth) {
      > Breakpoints.desktop => 6,
      > Breakpoints.tablet => 5,
      _ => 3,
    };
  }

  /// 根据屏幕宽度返回水平内边距
  double get horizontalPadding {
    if (isCompact) return 8;
    if (isNarrow) return 12;
    return 16;
  }

  /// 根据设备类型选择值
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
}

/// 响应式布局构建器
/// 根据屏幕宽度自动选择合适的布局
class ResponsiveBuilder extends StatelessWidget {
  const ResponsiveBuilder({
    super.key,
    required this.mobile,
    this.compact,
    this.tablet,
    this.desktop,
  });

  /// 移动端布局 (必需，作为默认回退)
  final Widget mobile;

  /// 极窄屏幕布局 (可选)
  final Widget? compact;

  /// 平板布局 (可选)
  final Widget? tablet;

  /// 桌面布局 (可选)
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

/// 响应式值选择器
/// 根据屏幕宽度返回不同的值
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

/// 响应式 SizedBox
/// 根据屏幕宽度自动调整间距
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

/// 响应式 EdgeInsets
/// 提供常用的响应式内边距
class ResponsivePadding {
  /// 水平内边距
  static EdgeInsets horizontal(BuildContext context) {
    final padding = context.horizontalPadding;
    return EdgeInsets.symmetric(horizontal: padding);
  }

  /// 全部内边距
  static EdgeInsets all(BuildContext context) {
    final padding = context.horizontalPadding;
    return EdgeInsets.all(padding);
  }

  /// 自定义响应式内边距
  static EdgeInsets symmetric(
    BuildContext context, {
    double? horizontalCompact,
    double? horizontalMobile,
    double? horizontalTablet,
    double? verticalCompact,
    double? verticalMobile,
    double? verticalTablet,
  }) {
    return EdgeInsets.symmetric(
      horizontal: context.responsive<double>(
        compact: horizontalCompact ?? 8,
        mobile: horizontalMobile ?? 12,
        tablet: horizontalTablet ?? 16,
      ),
      vertical: context.responsive<double>(
        compact: verticalCompact ?? 8,
        mobile: verticalMobile ?? 12,
        tablet: verticalTablet ?? 16,
      ),
    );
  }
}

/// 二级页面显示模式
enum SecondaryPageMode {
  /// 全屏显示
  fullScreen,

  /// 侧边Sheet (大屏幕推荐)
  sideSheet,

  /// 居中Dialog (表单/简单操作推荐)
  centerDialog,

  /// 底部Sheet
  bottomSheet,
}

/// 响应式导航工具类
/// 用于处理二级页面在不同屏幕尺寸下的显示方式
class ResponsiveNavigation {
  /// 显示二级页面
  /// 根据屏幕尺寸和页面类型自动选择最佳显示方式
  ///
  /// - [context] 当前 BuildContext
  /// - [child] 要显示的页面内容
  /// - [preferredMode] 首选显示模式（大屏幕使用）
  /// - [title] 页面标题（用于AppBar）
  /// - [maxWidth] 侧边Sheet/Dialog的最大宽度
  /// - [showCloseButton] 是否显示关闭按钮
  static Future<T?> showSecondaryPage<T>({
    required BuildContext context,
    required Widget child,
    SecondaryPageMode preferredMode = SecondaryPageMode.sideSheet,
    String? title,
    double maxWidth = 480,
    bool showCloseButton = true,
    bool barrierDismissible = true,
  }) {
    final isLarge = context.isLargeScreen;

    // 移动端始终使用全屏或底部Sheet
    if (!isLarge) {
      if (preferredMode == SecondaryPageMode.bottomSheet) {
        return _showBottomSheet<T>(
          context: context,
          child: child,
          title: title,
          showCloseButton: showCloseButton,
        );
      }
      return _showFullScreen<T>(
        context: context,
        child: child,
        title: title,
      );
    }

    // 大屏幕根据首选模式选择
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
          maxWidth: maxWidth,
          showCloseButton: showCloseButton,
          barrierDismissible: barrierDismissible,
        ),
      SecondaryPageMode.centerDialog => _showCenterDialog<T>(
          context: context,
          child: child,
          title: title,
          maxWidth: maxWidth,
          showCloseButton: showCloseButton,
          barrierDismissible: barrierDismissible,
        ),
      SecondaryPageMode.bottomSheet => _showBottomSheet<T>(
          context: context,
          child: child,
          title: title,
          showCloseButton: showCloseButton,
        ),
    };
  }

  /// 全屏导航
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

  /// 侧边Sheet (从右侧滑入)
  static Future<T?> _showSideSheet<T>({
    required BuildContext context,
    required Widget child,
    String? title,
    double maxWidth = 480,
    bool showCloseButton = true,
    bool barrierDismissible = true,
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
            child: Container(
              width: maxWidth,
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.8,
              ),
              child: _buildSheetContent(
                context: context,
                child: child,
                title: title,
                showCloseButton: showCloseButton,
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
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          )),
          child: child,
        );
      },
    );
  }

  /// 居中Dialog
  static Future<T?> _showCenterDialog<T>({
    required BuildContext context,
    required Widget child,
    String? title,
    double maxWidth = 480,
    bool showCloseButton = true,
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (context) => Dialog(
        child: Container(
          width: maxWidth,
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.9,
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          child: _buildSheetContent(
            context: context,
            child: child,
            title: title,
            showCloseButton: showCloseButton,
          ),
        ),
      ),
    );
  }

  /// 底部Sheet
  static Future<T?> _showBottomSheet<T>({
    required BuildContext context,
    required Widget child,
    String? title,
    bool showCloseButton = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      builder: (context) => _buildSheetContent(
        context: context,
        child: child,
        title: title,
        showCloseButton: showCloseButton,
      ),
    );
  }

  /// 构建Sheet内容（带可选标题栏）
  static Widget _buildSheetContent({
    required BuildContext context,
    required Widget child,
    String? title,
    bool showCloseButton = true,
  }) {
    if (title == null && !showCloseButton) {
      return child;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
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
        Expanded(child: child),
      ],
    );
  }
}

/// 响应式页面容器
/// 自动限制内容最大宽度，使大屏幕上的内容居中显示
class ResponsivePageContainer extends StatelessWidget {
  const ResponsivePageContainer({
    super.key,
    required this.child,
    this.maxWidth = 1200,
    this.padding,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: padding != null
            ? Padding(padding: padding!, child: child)
            : child,
      ),
    );
  }
}
