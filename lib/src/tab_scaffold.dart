import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/tab_navigation.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/view/home/home_tab_screen.dart';
import 'package:lichess_mobile/src/view/learn/learn_tab_screen.dart';
import 'package:lichess_mobile/src/view/more/more_tab_screen.dart';
import 'package:lichess_mobile/src/view/puzzle/puzzle_tab_screen.dart';
import 'package:lichess_mobile/src/view/watch/watch_tab_screen.dart';
import 'package:lichess_mobile/src/widgets/background.dart';
import 'package:lichess_mobile/src/widgets/floating_nav_bar.dart';
import 'package:material_ui/material_ui.dart';

/// Main scaffold that provides the bottom navigation bar and tab switching view.
class const MainTabScaffold({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTab = ref.watch(currentBottomTabProvider);

    // The content scrolls behind the floating bar, so the tab screens add its height to their
    // bottom padding (see PlatformScaffold).
    return FullScreenBackground(
      child: MainTabScaffoldProperties(
        extendBody: true,
        child: Scaffold(
          body: _TabSwitchingView(currentTab: currentTab, tabBuilder: _tabBuilder),
          extendBody: true,
          bottomNavigationBar: FloatingNavBar(
            currentIndex: currentTab.index,
            items: [
              for (final tab in BottomTab.values) (icon: tab.icon, label: tab.label(context.l10n)),
            ],
            onTap: (i) => _onItemTapped(ref, i),
          ),
        ),
      ),
    );
  }

  /// If tapped tab is the same as the current tab, pop to the first route in
  /// the tab's stack.
  /// If the route is already at the first route, scroll the tab's root
  /// scrollable to the top.
  /// Otherwise, switch to the tapped tab.
  void _onItemTapped(WidgetRef ref, int index) {
    final curTab = ref.read(currentBottomTabProvider);
    final tappedTab = BottomTab.values[index];

    if (tappedTab == curTab) {
      final navState = ref.read(currentNavigatorKeyProvider).currentState;
      final scrollController = ref.read(currentRootScrollControllerProvider);
      if (navState?.canPop() == true) {
        navState?.popUntil((route) => route.isFirst);
      } else if (scrollController.hasClients && scrollController.offset > 0) {
        scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else {
        switch (tappedTab) {
          case BottomTab.home:
            homeTabInteraction.notifyItemTapped();
          case BottomTab.puzzles:
            puzzlesTabInteraction.notifyItemTapped();
          case BottomTab.learn:
            learnTabInteraction.notifyItemTapped();
          case BottomTab.watch:
            watchTabInteraction.notifyItemTapped();
          case BottomTab.more:
            moreTabInteraction.notifyItemTapped();
        }
      }
    } else {
      HapticFeedback.lightImpact();
      ref.read(currentBottomTabProvider.notifier).state = tappedTab;
    }
  }

  Widget _tabBuilder(BuildContext context, int index) {
    switch (index) {
      case 0:
        return _MaterialTabView(
          navigatorKey: homeNavigatorKey,
          tab: BottomTab.home,
          builder: (context) => const HomeTabScreen(),
        );
      case 1:
        return _MaterialTabView(
          navigatorKey: puzzlesNavigatorKey,
          tab: BottomTab.puzzles,
          builder: (context) => const PuzzleTabScreen(),
        );
      case 2:
        return _MaterialTabView(
          navigatorKey: learnNavigatorKey,
          tab: BottomTab.learn,
          builder: (context) => const LearnTabScreen(),
        );
      case 3:
        return _MaterialTabView(
          navigatorKey: watchNavigatorKey,
          tab: BottomTab.watch,
          builder: (context) => const WatchTabScreen(),
        );
      case 4:
        return _MaterialTabView(
          navigatorKey: moreNavigatorKey,
          tab: BottomTab.more,
          builder: (context) => const MoreTabScreen(),
        );
      default:
        assert(false, 'Unexpected tab');
        return const SizedBox.shrink();
    }
  }
}

// --

// Below code taken and adapted from https://github.com/flutter/flutter/blob/135454af32477f815a7525073027a3ff9eff1bfd/packages/flutter/lib/src/cupertino/tab_scaffold.dart#L403

/// A widget laying out multiple tabs with only one active tab being built
/// at a time and on stage. Off stage tabs' animations are stopped.
class const _TabSwitchingView({
  required final BottomTab currentTab,
  required final IndexedWidgetBuilder tabBuilder,
}) extends StatefulWidget {
  @override
  _TabSwitchingViewState createState() => _TabSwitchingViewState();
}

/// Duration of the fade in of a tab when switching to it.
const _kTabFadeDuration = Duration(milliseconds: 220);

class _TabSwitchingViewState() extends State<_TabSwitchingView>
    with SingleTickerProviderStateMixin {
  final List<bool> shouldBuildTab = <bool>[];
  final List<FocusScopeNode> tabFocusNodes = <FocusScopeNode>[];

  // When focus nodes are no longer needed, we need to dispose of them, but we
  // can't be sure that nothing else is listening to them until this widget is
  // disposed of, so when they are no longer needed, we move them to this list,
  // and dispose of them when we dispose of this widget.
  final List<FocusScopeNode> discardedNodes = <FocusScopeNode>[];

  /// Fades the newly selected tab in, rather than switching abruptly.
  late final AnimationController _fadeController = AnimationController(
    vsync: this,
    duration: _kTabFadeDuration,
    value: 1.0,
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _fadeController,
    curve: Curves.easeOut,
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.015),
    end: Offset.zero,
  ).animate(_fade);

  @override
  void initState() {
    super.initState();
    shouldBuildTab.addAll(List<bool>.filled(BottomTab.values.length, false));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _focusActiveTab();
  }

  @override
  void didUpdateWidget(_TabSwitchingView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentTab != widget.currentTab) {
      _fadeController.forward(from: 0.0);
    }
    _focusActiveTab();
  }

  // Will focus the active tab if the FocusScope above it has focus already.  If
  // not, then it will just mark it as the preferred focus for that scope.
  void _focusActiveTab() {
    if (tabFocusNodes.length != BottomTab.values.length) {
      if (tabFocusNodes.length > BottomTab.values.length) {
        discardedNodes.addAll(tabFocusNodes.sublist(BottomTab.values.length));
        tabFocusNodes.removeRange(BottomTab.values.length, tabFocusNodes.length);
      } else {
        tabFocusNodes.addAll(
          List<FocusScopeNode>.generate(
            BottomTab.values.length - tabFocusNodes.length,
            (int index) =>
                FocusScopeNode(debugLabel: '$MainTabScaffold Tab ${index + tabFocusNodes.length}'),
          ),
        );
      }
    }
    FocusScope.of(context).setFirstFocus(tabFocusNodes[widget.currentTab.index]);
  }

  @override
  void dispose() {
    for (final FocusScopeNode focusScopeNode in tabFocusNodes) {
      focusScopeNode.dispose();
    }
    for (final FocusScopeNode focusScopeNode in discardedNodes) {
      focusScopeNode.dispose();
    }
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: List<Widget>.generate(BottomTab.values.length, (int index) {
        final bool active = index == widget.currentTab.index;
        shouldBuildTab[index] = active || shouldBuildTab[index];

        return HeroMode(
          enabled: active,
          child: Offstage(
            offstage: !active,
            child: TickerMode(
              enabled: active,
              // Every tab keeps its transitions, so that switching tabs does not rebuild them:
              // only the active one is driven by the fade.
              child: FadeTransition(
                opacity: active ? _fade : kAlwaysCompleteAnimation,
                child: SlideTransition(
                  position: active ? _slide : const AlwaysStoppedAnimation(Offset.zero),
                  child: FocusScope(
                    node: tabFocusNodes[index],
                    child: Builder(
                      builder: (BuildContext context) {
                        return shouldBuildTab[index]
                            ? widget.tabBuilder(context, index)
                            : Container();
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

// Following code copied and adapted from
// https://github.com/flutter/flutter/blob/2ad6cd72c040113b47ee9055e722606a490ef0da/packages/flutter/lib/src/cupertino/tab_view.dart#L41

class const _MaterialTabView({
  // ignore: unused_element_parameter
  super.key,
  required final BottomTab tab,
  final WidgetBuilder? builder,
  final GlobalKey<NavigatorState>? navigatorKey,
  // ignore: unused_element_parameter
  final Map<String, WidgetBuilder>? routes,
  // ignore: unused_element_parameter
  final RouteFactory? onGenerateRoute,
  // ignore: unused_element_parameter
  final RouteFactory? onUnknownRoute,
  // ignore: unused_element_parameter
  final List<NavigatorObserver> navigatorObservers = const <NavigatorObserver>[],
  // ignore: unused_element_parameter
  final String? restorationScopeId,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<_MaterialTabView> createState() => _MaterialTabViewState();
}

class _MaterialTabViewState() extends ConsumerState<_MaterialTabView> {
  late HeroController _heroController;
  late List<NavigatorObserver> _navigatorObservers;

  @override
  void initState() {
    super.initState();
    _heroController = MaterialApp.createMaterialHeroController();
    _updateObservers();
  }

  @override
  void didUpdateWidget(_MaterialTabView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.navigatorKey != oldWidget.navigatorKey ||
        widget.navigatorObservers != oldWidget.navigatorObservers) {
      _updateObservers();
    }
  }

  void _updateObservers() {
    _navigatorObservers = List<NavigatorObserver>.of(widget.navigatorObservers)
      ..add(_heroController);
  }

  @override
  Widget build(BuildContext context) {
    final currentTab = ref.watch(currentBottomTabProvider);
    final enablePopHandler = currentTab == widget.tab;
    return NavigatorPopHandler(
      onPopWithResult: enablePopHandler
          ? (_) {
              widget.navigatorKey?.currentState?.maybePop();
            }
          : null,
      enabled: enablePopHandler,
      child: Navigator(
        key: widget.navigatorKey,
        onGenerateRoute: _onGenerateRoute,
        onUnknownRoute: _onUnknownRoute,
        observers: _navigatorObservers,
        restorationScopeId: widget.restorationScopeId,
      ),
    );
  }

  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    final String? name = settings.name;
    WidgetBuilder? routeBuilder;
    if (name == Navigator.defaultRouteName && widget.builder != null) {
      routeBuilder = widget.builder;
    } else if (widget.routes != null) {
      routeBuilder = widget.routes![name];
    }
    if (routeBuilder != null) {
      return MaterialPageRoute<dynamic>(builder: routeBuilder, settings: settings);
    }
    if (widget.onGenerateRoute != null) {
      return widget.onGenerateRoute!(settings);
    }
    return null;
  }

  Route<dynamic>? _onUnknownRoute(RouteSettings settings) {
    assert(() {
      if (widget.onUnknownRoute == null) {
        throw FlutterError(
          'Could not find a generator for route $settings in the $runtimeType.\n'
          'Generators for routes are searched for in the following order:\n'
          ' 1. For the "/" route, the "builder" property, if non-null, is used.\n'
          ' 2. Otherwise, the "routes" table is used, if it has an entry for '
          'the route.\n'
          ' 3. Otherwise, onGenerateRoute is called. It should return a '
          'non-null value for any valid route not handled by "builder" and "routes".\n'
          ' 4. Finally if all else fails onUnknownRoute is called.\n'
          'Unfortunately, onUnknownRoute was not set.',
        );
      }
      return true;
    }());
    final Route<dynamic>? result = widget.onUnknownRoute!(settings);
    assert(() {
      if (result == null) {
        throw FlutterError(
          'The onUnknownRoute callback returned null.\n'
          'When the $runtimeType requested the route $settings from its '
          'onUnknownRoute callback, the callback returned null. Such callbacks '
          'must never return null.',
        );
      }
      return true;
    }());
    return result;
  }
}

