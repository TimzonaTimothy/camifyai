import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

abstract final class AppLayout {
  static EdgeInsets padding(BuildContext context) =>
      EdgeInsets.all(MediaQuery.sizeOf(context).width < 700 ? 20 : 32);
}

/// Stacks independent panels and header actions when their own available width is small.
class AdaptiveRow extends StatelessWidget {
  final List<Widget> children;
  final double breakpoint;
  final CrossAxisAlignment crossAxisAlignment;
  final MainAxisAlignment mainAxisAlignment;
  final MainAxisSize mainAxisSize;
  const AdaptiveRow(
      {super.key,
      required this.children,
      this.breakpoint = 560,
      this.crossAxisAlignment = CrossAxisAlignment.center,
      this.mainAxisAlignment = MainAxisAlignment.start,
      this.mainAxisSize = MainAxisSize.max});

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth >= breakpoint) {
          return Row(
              crossAxisAlignment: crossAxisAlignment,
              mainAxisAlignment: mainAxisAlignment,
              mainAxisSize: mainAxisSize,
              children: children);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final child in children)
              if (child is! Spacer)
                if (child is Flexible)
                  child.child
                else if (child is SizedBox &&
                    child.width != null &&
                    child.height == null)
                  SizedBox(height: child.width)
                else
                  child,
          ],
        );
      });
}

/// Gives a full table its natural readable width, with horizontal scrolling on small windows.
class ResponsiveTable extends StatelessWidget {
  final Widget child;
  final double minWidth;
  const ResponsiveTable({super.key, required this.child, this.minWidth = 760});
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
                width: constraints.maxWidth < minWidth
                    ? minWidth
                    : constraints.maxWidth,
                child: child));
      });
}

/// Authentication forms always scroll; the decorative panel only uses spacious windows.
class AuthLayout extends StatelessWidget {
  final List<Widget> children;
  const AuthLayout({super.key, required this.children});
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final form = children.last is Flexible
            ? (children.last as Flexible).child
            : children.last;
        final scrollableForm = LayoutBuilder(
            builder: (context, available) => SingleChildScrollView(
                  child: ConstrainedBox(
                      constraints:
                          BoxConstraints(minHeight: available.maxHeight),
                      child: form),
                ));
        if (constraints.maxWidth >= 1000 && constraints.maxHeight >= 720) {
          return Row(children: [
            children.first,
            Expanded(flex: 5, child: scrollableForm)
          ]);
        }
        return ColoredBox(
            color: AppColors.bg,
            child: Column(children: [
              const Padding(
                  padding: EdgeInsets.only(top: 28, bottom: 8),
                  child: Text('camifyai',
                      style: TextStyle(
                          color: AppColors.accent,
                          fontSize: 23,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -1))),
              Expanded(child: scrollableForm),
            ]));
      });
}

/// Comfortable gutters and a readable content width on ultrawide displays.
class AppPage extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  const AppPage({super.key, required this.child, this.padding});
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: padding ?? AppLayout.padding(context),
        child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1360),
                child: SizedBox(width: double.infinity, child: child))),
      );
}
