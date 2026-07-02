import 'dart:async';

import 'package:finamp/components/global_snackbar.dart';
import 'package:finamp/screens/lyrics_screen.dart';
import 'package:finamp/services/finamp_settings_helper.dart';
import 'package:finamp/services/keep_screen_on_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get_it/get_it.dart';
import 'package:split_view/split_view.dart';

import '../../models/finamp_models.dart';
import '../../screens/player_screen.dart';
import '../../services/queue_service.dart';

const double _kMinScreenWidth = 800;
const double _kMinScreenHeight = 500;
const double _kMinPlayerWidth = 275;
const double _kMinMenuWidth = 400;
const double _kResizingAreaSize = 20;

class SplitScreenHelper {
  static bool screenSizeAllowsSplitScreen(Size size) {
    return size.width >= _kMinScreenWidth && size.height >= _kMinScreenHeight;
  }

  static bool constraintsAllowsSplitScreen(BoxConstraints constraints) {
    return screenSizeAllowsSplitScreen(Size(constraints.maxWidth, constraints.maxHeight));
  }

  static bool get usingPlayerSplitScreen => _inSplitScreen;

  /// Min weighted size of the main screen (ie, not the player)
  static double get mainScreenMinWeight => _splitScreenController.limits[0]!.min!;

  /// Max weighted size of the main screen (ie, not the player)
  static double get mainScreenMaxWeight => _splitScreenController.limits[0]!.max!;
}

/// Takes the actual width in double and converts into a weighted size by width
double _getWeightedValue({required double pixelSize, required BoxConstraints constraints}) {
  return pixelSize / constraints.maxWidth;
}

bool _inSplitScreen = false;
double _weight = 0.0;
Timer? _timer;
double? _playerWidth;
SplitViewController _splitScreenController = SplitViewController();

Widget buildPlayerSplitScreenScaffold(BuildContext context, Widget? widget) {
  return LayoutBuilder(
    builder: (context, constraints) {
      // Only use split screen if wide enough to easily show both views and tall enough
      // that a landscape full-screen player is not preferred instead
      if (!SplitScreenHelper.constraintsAllowsSplitScreen(constraints)) {
        _inSplitScreen = false;
        return widget!;
      }
      final queueService = GetIt.instance<QueueService>();

      _splitScreenController = SplitViewController(
        limits: [
          WeightLimit(
            min: _getWeightedValue(pixelSize: _kMinMenuWidth, constraints: constraints),
            max: 1.0 - (_getWeightedValue(pixelSize: _kMinPlayerWidth, constraints: constraints)),
          ),
        ],
      );

      return Consumer(
        builder: (context, ref, child) {
          bool allowSplitScreen = ref.watch(finampSettingsProvider.allowSplitScreen);

          return StreamBuilder<FinampQueueInfo?>(
            stream: queueService.getQueueStream(),
            initialData: queueService.getQueue(),
            builder: (context, snapshot) {
              final shouldShowSplitScreen =
                  (snapshot.hasData &&
                  (snapshot.data!.saveState == SavedQueueState.loading ||
                      snapshot.data!.saveState == SavedQueueState.failed ||
                      snapshot.data!.currentTrack != null) &&
                  allowSplitScreen);

              if (!shouldShowSplitScreen) {
                _inSplitScreen = false;
                return widget!;
              }

              _inSplitScreen = true;
              SplitScreenNavigatorObserver.queuePop();

              // When resizing window, update weights to keep player width consistent
              final currentPlayerWidth = _playerWidth ?? FinampSettingsHelper.finampSettings.splitScreenPlayerWidth;
              _weight = (1.0 - currentPlayerWidth / constraints.maxWidth).clamp(
                SplitScreenHelper.mainScreenMinWeight,
                SplitScreenHelper.mainScreenMaxWeight,
              );
              _splitScreenController.weights = [_weight];

              return _SplitScreen(constraints: constraints, widget: widget);
            },
          );
        },
      );
    },
  );
}

class _SplitScreen extends StatelessWidget {
  const _SplitScreen({super.key, required this.constraints, required this.widget});

  final BoxConstraints constraints;
  final Widget? widget;

  @override
  Widget build(BuildContext context) {
    var size = MediaQuery.sizeOf(context);

    return SplitView(
      key: const ValueKey("PlayerSplitView"),
      resizingAreaSize: _kResizingAreaSize,
      gripSize: 0,
      viewMode: SplitViewMode.Horizontal,
      controller: _splitScreenController,
      onWeightChanged: (weights) {
        final weight = weights[0]!;
        if (weight == _weight) {
          // Weight is changing due to window resize, not drag action.
          // Do not update setting.
          return;
        }
        _playerWidth = (1.0 - weight) * constraints.maxWidth;
        _timer?.cancel();
        // Do not spam settings updates while resizing
        _timer = Timer(const Duration(seconds: 1), () {
          FinampSetters.setSplitScreenPlayerWidth(_playerWidth!);
        });
      },
      children: [
        _SplitMainPanel(size: size, widget: widget),
        _SplitPlayerPanel(size: size),
      ],
    );
  }
}

class _SplitMainPanel extends StatelessWidget {
  const _SplitMainPanel({super.key, required this.size, required this.widget});

  final Size size;
  final Widget? widget;

  @override
  Widget build(BuildContext context) {
    var padding = MediaQuery.paddingOf(context);

    return ListenableBuilder(
      listenable: _splitScreenController,
      builder: (context, child) {
        final weight = (_splitScreenController.weights[0] ?? 1.0);

        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            size: Size((size.width * weight).clamp(0.0, double.infinity), size.height),
            padding: padding.copyWith(right: padding.right + 10),
          ),
          child: child!,
        );
      },
      child: widget,
    );
  }
}

class _SplitPlayerPanel extends StatelessWidget {
  const _SplitPlayerPanel({super.key, required this.size});

  final Size size;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _splitScreenController,
      builder: (context, child) {
        final weight = 1.0 - (_splitScreenController.weights[0] ?? 1.0);

        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(size: Size((size.width * weight).clamp(0.0, double.infinity), size.height)),
          child: child!,
        );
      },
      child: HeroControllerScope(
        controller: HeroController(),
        child: ScaffoldMessenger(
          child: Navigator(
            pages: const [MaterialPage(child: PlayerScreen())],
            onDidRemovePage: (page) {},
            onGenerateRoute: (x) {
              GlobalSnackbar.navigatorState!.pushNamed(x.name!, arguments: x.arguments);
              return EmptyRoute();
            },
            observers: [KeepScreenOnObserver()],
          ),
        ),
      ),
    );
  }
}

class EmptyRoute extends Route<dynamic> {
  @override
  List<OverlayEntry> get overlayEntries => [OverlayEntry(builder: (_) => const SizedBox.shrink())];
  @override
  void didAdd() {
    super.didAdd();
    navigator?.pop();
  }
}

class SplitScreenNavigatorObserver extends NavigatorObserver {
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_inSplitScreen && previousRoute != null && !shouldNotPop(previousRoute)) {
      queuePop();
    }
  }

  static final _playerCheck = ModalRoute.withName(PlayerScreen.routeName);
  static final _lyricsCheck = ModalRoute.withName(LyricsScreen.routeName);

  static void queuePop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      GlobalSnackbar.navigatorState?.popUntil(SplitScreenNavigatorObserver.shouldNotPop);
    });
  }

  static bool shouldNotPop(Route<dynamic> route) {
    return !_playerCheck(route) && !_lyricsCheck(route);
  }
}
