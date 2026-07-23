import 'package:balanced_text/balanced_text.dart';
import 'package:finamp/components/PlayerScreen/player_split_screen_scaffold.dart';
import 'package:finamp/components/PlayerScreen/queue_source_helper.dart';
import 'package:finamp/components/global_snackbar.dart';
import 'package:finamp/l10n/app_localizations.dart';
import 'package:finamp/models/finamp_models.dart';
import 'package:finamp/screens/player_screen.dart';
import 'package:finamp/services/finamp_settings_helper.dart';
import 'package:finamp/services/queue_service.dart';
import 'package:finamp/services/split_screen_transition_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get_it/get_it.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../extensions/localizations.dart';

class PlayerScreenAppBarTitle extends ConsumerStatefulWidget {
  const PlayerScreenAppBarTitle({super.key, required this.maxLines});

  final int maxLines;

  @override
  ConsumerState<PlayerScreenAppBarTitle> createState() => _PlayerScreenAppBarTitleState();
}

class _PlayerScreenAppBarTitleState extends ConsumerState<PlayerScreenAppBarTitle> {
  final QueueService _queueService = GetIt.instance<QueueService>();

  @override
  Widget build(BuildContext context) {
    final currentTrackStream = _queueService.getCurrentTrackStream();

    final screenWidth = MediaQuery.widthOf(context);
    final view = View.of(context);
    final fullScreenSize = view.physicalSize / view.devicePixelRatio;
    final allowSplitScreen = SplitScreenHelper.screenSizeAllowsSplitScreen(fullScreenSize);

    final splitScreenState = ref.watch(finampSettingsProvider.allowSplitScreen);

    return StreamBuilder<FinampQueueItem?>(
      stream: currentTrackStream,
      initialData: _queueService.getCurrentTrack(),
      builder: (context, snapshot) {
        if (snapshot.data == null) {
          return const SizedBox.shrink();
        }
        final queueItem = snapshot.data!;

        return Stack(
          alignment: Alignment.center,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: screenWidth * 0.62),
              child: GestureDetector(
                onTap: () => navigateToSource(context, queueItem.source),
                child: Column(
                  children: [
                    Text(
                      AppLocalizations.of(context)!.playingFromType(queueItem.source.type.name),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w300,
                        color: Theme.brightnessOf(context) == Brightness.dark
                            ? Colors.white.withValues(alpha: 0.7)
                            : Colors.black.withValues(alpha: 0.8),
                      ),
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    const Padding(padding: EdgeInsets.symmetric(vertical: 1)),
                    BalancedText(
                      queueItem.source.name.getLocalized(context.l10n),
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.brightnessOf(context) == Brightness.dark
                            ? Colors.white
                            : Colors.black.withValues(alpha: 0.9),
                      ),
                      maxLines: widget.maxLines,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            if (allowSplitScreen)
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: () async {
                    final splitScreenTransitionNotifier = ref.read(splitScreenTransitionProvider.notifier);
                    if (splitScreenState) {
                      await splitScreenTransitionNotifier.runTransitionActions(() async {
                        FinampSetters.setAllowSplitScreen(false);
                        await Future.delayed(Duration(milliseconds: 100));
                        await GlobalSnackbar.navigatorState!.pushNamed(PlayerScreen.routeName);
                      });
                    } else {
                      await splitScreenTransitionNotifier.runTransitionActions(() async {
                        GlobalSnackbar.navigatorState?.pop();
                        await Future.delayed(Duration(milliseconds: 100));
                        FinampSetters.setAllowSplitScreen(true);
                      });
                    }
                  },
                  icon: Icon(splitScreenState ? Symbols.right_panel_open : Symbols.left_panel_open),
                ),
              ),
          ],
        );
      },
    );
  }
}
