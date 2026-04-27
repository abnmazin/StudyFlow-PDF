class ResponsiveBreakpoints {
  static const double mobile = 600;
  static const double tablet = 1024;

  static bool isMobile(double width) => width < mobile;

  static bool isTablet(double width) => width >= mobile && width < tablet;

  static bool isDesktop(double width) => width >= tablet;

  static double sidebarWidth(double width) {
    if (isMobile(width)) {
      return (width * 0.84).clamp(260.0, 320.0).toDouble();
    }
    if (isTablet(width)) {
      return 248;
    }
    return 288;
  }

  static double rightPanelWidth(double width) {
    if (width < 420) {
      return (width * 0.9).clamp(250.0, 320.0).toDouble();
    }
    if (isTablet(width)) {
      return 280;
    }
    return 320;
  }

  static double dialogWidth(double width, {double max = 600}) {
    return (width * 0.92).clamp(280.0, max).toDouble();
  }
}
