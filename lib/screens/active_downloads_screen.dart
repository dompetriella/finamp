import 'package:flutter/material.dart';
import 'package:finamp/components/finamp_app_bar_back_button.dart';
import 'package:finamp/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get_it/get_it.dart';
import 'package:rxdart/rxdart.dart';

import '../components/ActiveDownloadsScreen/active_download_list.dart';
import '../components/global_snackbar.dart';
import '../components/padded_custom_scrollview.dart';
import '../models/finamp_models.dart';
import '../services/downloads_service.dart';

class ActiveDownloadsScreen extends ConsumerWidget {
  const ActiveDownloadsScreen({super.key});

  static const routeName = "/downloads/errors";

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadsService = GetIt.instance<DownloadsService>();

    var stream =
        Rx.combineLatest4<
          List<DownloadStub>,
          List<DownloadStub>,
          List<DownloadStub>,
          List<DownloadStub>,
          List<List<DownloadStub>>
        >(
          downloadsService.getDownloadList(DownloadItemState.syncFailed),
          downloadsService.getDownloadList(DownloadItemState.failed),
          downloadsService.getDownloadList(DownloadItemState.downloading),
          downloadsService.getDownloadList(DownloadItemState.enqueued),
          (l1, l2, l3, l4) => [l1, l2, l3, l4],
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.activeDownloadsTitle),
        leading: FinampAppBarBackButton(),
      ),
      body: StreamBuilder(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            if (snapshot.data!.every((element) => element.isEmpty)) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check,
                      size: 64,
                      // Inactive icons have an opacity of 50% with dark theme and 38%
                      // with bright theme
                      // https://material.io/design/iconography/system-icons.html#color
                      color: Theme.of(
                        context,
                      ).iconTheme.color?.withOpacity(Theme.brightnessOf(context) == Brightness.light ? 0.38 : 0.5),
                    ),
                    const Padding(padding: EdgeInsets.all(8.0)),
                    Text(AppLocalizations.of(context)!.noActiveDownloads),
                  ],
                ),
              );
            } else {
              return PaddedCustomScrollview(
                slivers: [
                  _AllDownloadsHeader(downloadsService: downloadsService),
                  if (snapshot.data![0].isNotEmpty)
                    ActiveDownloadList(
                      state: DownloadItemState.syncFailed,
                      downloadsService: downloadsService,
                      children: snapshot.data![0],
                    ),
                  if (snapshot.data![1].isNotEmpty)
                    ActiveDownloadList(
                      state: DownloadItemState.failed,
                      downloadsService: downloadsService,
                      children: snapshot.data![1],
                    ),
                  if (snapshot.data![2].isNotEmpty)
                    ActiveDownloadList(
                      state: DownloadItemState.downloading,
                      downloadsService: downloadsService,
                      children: snapshot.data![2],
                    ),
                  if (snapshot.data![3].isNotEmpty)
                    ActiveDownloadList(
                      state: DownloadItemState.enqueued,
                      downloadsService: downloadsService,
                      children: snapshot.data![3],
                    ),
                ],
              );
            }
          } else if (snapshot.hasError) {
            GlobalSnackbar.error(snapshot.error);
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(AppLocalizations.of(context)!.errorScreenError),
              ),
            );
          } else {
            return const Center(child: CircularProgressIndicator.adaptive());
          }
        },
      ),
    );
  }
}

class _AllDownloadsHeader extends ConsumerStatefulWidget {
  const _AllDownloadsHeader({super.key, required this.downloadsService});

  final DownloadsService downloadsService;

  @override
  ConsumerState<_AllDownloadsHeader> createState() => _AllDownloadsHeaderState();
}

class _AllDownloadsHeaderState extends ConsumerState<_AllDownloadsHeader> {
  // Size of the current batch, captured once and held until the queue drains.
  int? _batchTotal;

  @override
  Widget build(BuildContext context) {
    final downloadStatuses = widget.downloadsService.downloadStatuses;
    final allDownloadsProgress = ref.watch(widget.downloadsService.allProgressProvider);

    final downloading = downloadStatuses[DownloadItemState.downloading] ?? 0;
    final enqueued = downloadStatuses[DownloadItemState.enqueued] ?? 0;
    final remaining = downloading + enqueued;

    final totalDownloadSpeed = allDownloadsProgress.values
        .where((e) => e.hasNetworkSpeed)
        .fold(0.0, (sum, e) => sum + e.networkSpeed);

    final averageDownloadSpeed = allDownloadsProgress.isNotEmpty
        ? totalDownloadSpeed / allDownloadsProgress.length
        : 0.0;

    final avgSpeedAsString = widget.downloadsService.getNetworkSpeedAsString(
      networkSpeed: averageDownloadSpeed,
      decimals: 3,
    );

    if (remaining == 0) {
      _batchTotal = null;
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    // First frame of a batch: lock in its size. If more items get queued
    // mid-batch, grow the total rather than letting progress exceed 100%.
    if (_batchTotal == null || remaining > _batchTotal!) {
      _batchTotal = remaining;
    }

    final completed = _batchTotal! - remaining;
    final overallProgress = completed / _batchTotal!;

    return PinnedHeaderSliver(
      child: Column(
        spacing: 8,
        children: [
          DownloadsProgressLinearIndicator(progressValue: overallProgress, widthFactor: 3 / 4, minHeight: 16),
          Text('${AppLocalizations.of(context)!.averageDownloadSpeed}: $avgSpeedAsString'),
        ],
      ),
    );
  }
}

class DownloadsProgressLinearIndicator extends StatelessWidget {
  const DownloadsProgressLinearIndicator({
    super.key,
    required this.progressValue,
    this.minHeight = 12,
    this.widthFactor = 1,
  });

  final double progressValue;
  final double minHeight;
  final double widthFactor;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: progressValue),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      builder: (context, animatedValue, child) {
        return FractionallySizedBox(
          widthFactor: widthFactor,
          child: LinearProgressIndicator(
            value: animatedValue,
            minHeight: minHeight,
            borderRadius: BorderRadius.circular(minHeight / 2),
            semanticsLabel: 'Download Progress',
            semanticsValue: '${(animatedValue * 100).round()}%',
          ),
        );
      },
    );
  }
}
