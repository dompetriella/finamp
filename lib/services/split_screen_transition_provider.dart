import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'split_screen_transition_provider.g.dart';

@riverpod
class SplitScreenTransition extends _$SplitScreenTransition {
  @override
  bool build() {
    return false;
  }

  void setTransitioning(bool isTransitioning) {
    state = isTransitioning;
  }

  Future<void> runTransitionActions(Future<void> Function() transitionActions) async {
    setTransitioning(true);
    await transitionActions();
    setTransitioning(false);
  }
}
