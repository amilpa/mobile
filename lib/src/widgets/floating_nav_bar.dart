import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';

/// Height of the [FloatingNavBar], without its margins.
const kFloatingNavBarHeight = 68.0;

/// Space between the [FloatingNavBar] and the edges of the screen.
const _kHorizontalMargin = 16.0;
const _kBottomMargin = 10.0;

/// Padding between the bar and its pills.
const _kInnerPadding = 5.0;

const _kPillAnimationDuration = Duration(milliseconds: 420);

/// A destination of the [FloatingNavBar].
typedef FloatingNavBarItem = ({IconData icon, String label});

/// A bottom navigation bar floating above the content, as a rounded pill.
///
/// The selected item sits on a lighter pill, which slides to the newly selected item when it
/// changes.
class const FloatingNavBar({
  required final List<FloatingNavBarItem> items,
  required final int currentIndex,
  required final ValueChanged<int> onTap,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final barColor = (isDark ? colorScheme.surfaceContainerHigh : colorScheme.surfaceContainer)
        .withValues(alpha: 0.88);
    final pillColor = isDark ? colorScheme.surfaceContainerHighest : colorScheme.surfaceDim;
    const radius = BorderRadius.all(Radius.circular(kFloatingNavBarHeight / 2));

    return Padding(
      padding: EdgeInsets.fromLTRB(
        _kHorizontalMargin,
        0,
        _kHorizontalMargin,
        MediaQuery.viewPaddingOf(context).bottom + _kBottomMargin,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.12),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              height: kFloatingNavBarHeight,
              padding: const EdgeInsets.all(_kInnerPadding),
              decoration: BoxDecoration(
                color: barColor,
                borderRadius: radius,
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final itemWidth = constraints.maxWidth / items.length;
                  return Stack(
                    children: [
                      AnimatedPositioned(
                        duration: _kPillAnimationDuration,
                        curve: Curves.easeOutBack,
                        left: itemWidth * currentIndex,
                        top: 0,
                        bottom: 0,
                        width: itemWidth,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: pillColor,
                            borderRadius: const BorderRadius.all(
                              Radius.circular((kFloatingNavBarHeight - 2 * _kInnerPadding) / 2),
                            ),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          for (final (index, item) in items.indexed)
                            Expanded(
                              child: _NavItem(
                                item: item,
                                selected: index == currentIndex,
                                index: index,
                                count: items.length,
                                onTap: () => onTap(index),
                              ),
                            ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class const _NavItem({
  required final FloatingNavBarItem item,
  required final bool selected,
  required final int index,
  required final int count,
  required final VoidCallback onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final color = selected ? colorScheme.onSurface : colorScheme.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      hint: MaterialLocalizations.of(context).tabLabel(tabIndex: index + 1, tabCount: count),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedScale(
              scale: selected ? 1.08 : 1.0,
              duration: _kPillAnimationDuration,
              curve: Curves.easeOutBack,
              child: Icon(item.icon, color: color, size: 26, fill: selected ? 1 : 0),
            ),
            const SizedBox(height: 2),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
              child: Text(item.label, maxLines: 1, overflow: TextOverflow.fade, softWrap: false),
            ),
          ],
        ),
      ),
    );
  }
}
