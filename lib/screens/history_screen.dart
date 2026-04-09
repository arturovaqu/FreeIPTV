import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import 'movies_list_screen.dart';
import 'player_screen.dart';
import 'series_list_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// HistoryScreen
// ─────────────────────────────────────────────────────────────────────────────

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  static const _tabs = [
    (label: 'Todos',      type: null as ContentType?),
    (label: 'Canales',    type: ContentType.TV as ContentType?),
    (label: 'Series',     type: ContentType.SERIES as ContentType?),
    (label: 'Películas',  type: ContentType.MOVIES as ContentType?),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: const Text('Historial',
            style: AppTextStyles.headlineMedium),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.delete_sweep,
                size: 18, color: AppColors.error),
            label: const Text('Limpiar',
                style: TextStyle(color: AppColors.error)),
            onPressed: () => _confirmClearAll(context),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.accent,
          labelColor: AppColors.accent,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle: AppTextStyles.labelLarge,
          unselectedLabelStyle: AppTextStyles.labelMedium,
          tabs: _tabs
              .map((t) => Tab(text: t.label))
              .toList(),
        ),
      ),
      body: Consumer<StorageService>(
        builder: (context, storage, _) {
          final playlist = storage.getActivePlaylist();

          return TabBarView(
            controller: _tabController,
            children: _tabs.map((t) {
              final entries = storage
                  .getHistory(t.type)
                  .take(50)
                  .toList();
              return _HistoryList(
                entries: entries,
                playlist: playlist,
                filterType: t.type,
                onRemove: (entry) => storage.removeHistoryEntry(
                    entry.id, entry.type),
                onPlay: (entry) =>
                    _play(context, entry, storage, playlist),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  // ── Playback ───────────────────────────────────────────────────────────────

  void _play(
    BuildContext context,
    HistoryEntry entry,
    StorageService storage,
    Playlist? playlist,
  ) {
    if (playlist == null) {
      _showUnavailable(context);
      return;
    }

    switch (entry.type) {
      // Live TV ─────────────────────────────────────────────────────────────
      case ContentType.TV:
        final ch = playlist.channels
            .where((c) => c.id == entry.id)
            .firstOrNull;
        if (ch == null) { _showUnavailable(context); return; }
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PlayerScreen.channel(
              channel: ch,
              channels: playlist.channels,
            ),
          ),
        );

      // Movies ──────────────────────────────────────────────────────────────
      case ContentType.MOVIES:
        final movie = playlist.movies
            .where((m) => m.id == entry.id)
            .firstOrNull;
        if (movie == null) { _showUnavailable(context); return; }
        // Open player directly so position is restored
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PlayerScreen.movie(movie: movie),
          ),
        );

      // Series episode ──────────────────────────────────────────────────────
      case ContentType.SERIES:
        // ID format: "${seriesId}_S${seasonNum}E${episodeNum}"
        final match =
            RegExp(r'^(.+)_S(\d+)E(\d+)$').firstMatch(entry.id);
        if (match == null) {
          // Fallback: open the series detail sheet
          final s = playlist.series
              .where((s) => s.id == entry.id)
              .firstOrNull;
          if (s != null) _openSeriesSheet(context, s);
          else _showUnavailable(context);
          return;
        }
        final seriesId   = match.group(1)!;
        final seasonNum  = int.parse(match.group(2)!);
        final episodeNum = int.parse(match.group(3)!);

        final series = playlist.series
            .where((s) => s.id == seriesId)
            .firstOrNull;
        if (series == null) { _showUnavailable(context); return; }

        final season = series.seasons
            .where((s) => s.seasonNumber == seasonNum)
            .firstOrNull;
        if (season == null) { _showUnavailable(context); return; }

        final episode = season.episodes
            .where((e) => e.episodeNumber == episodeNum)
            .firstOrNull;
        if (episode == null) { _showUnavailable(context); return; }

        // Open player directly — position auto-restored from StorageService
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PlayerScreen.series(
              series: series,
              season: season,
              episode: episode,
            ),
          ),
        );
    }
  }

  void _openSeriesSheet(BuildContext context, Series series) =>
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => SeriesDetailSheet(series: series),
      );

  void _showUnavailable(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Contenido no disponible en la playlist activa'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── Clear all ──────────────────────────────────────────────────────────────

  Future<void> _confirmClearAll(BuildContext context) async {
    final storage = context.read<StorageService>();
    // Clear only the currently active tab's type
    final tabType = _tabs[_tabController.index].type;
    final count   = storage.getHistory(tabType).length;
    if (count == 0) return;

    final label = tabType == null
        ? 'todo el historial'
        : 'el historial de ${tabType.plural.toLowerCase()}';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Limpiar historial',
            style: AppTextStyles.headlineSmall),
        content: Text('¿Eliminar $label ($count entradas)?',
            style: AppTextStyles.bodyMedium),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Limpiar',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok == true) await storage.clearHistory(tabType);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _HistoryList — one tab's content
// ─────────────────────────────────────────────────────────────────────────────

class _HistoryList extends StatelessWidget {
  final List<HistoryEntry> entries;
  final Playlist? playlist;
  final ContentType? filterType;
  final void Function(HistoryEntry) onRemove;
  final void Function(HistoryEntry) onPlay;

  const _HistoryList({
    required this.entries,
    required this.playlist,
    required this.filterType,
    required this.onRemove,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const _EmptyHistory();
    }

    return ListView.builder(
      padding: AppSpacing.paddingMD,
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final entry = entries[i];
        return Dismissible(
          key: ValueKey('${entry.type.name}_${entry.id}'),
          direction: DismissDirection.endToStart,
          onDismissed: (_) => onRemove(entry),
          background: const _SwipeDeleteBackground(),
          child: _HistoryTile(
            entry: entry,
            playlist: playlist,
            onTap: () => onPlay(entry),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _HistoryTile
// ─────────────────────────────────────────────────────────────────────────────

class _HistoryTile extends StatelessWidget {
  final HistoryEntry entry;
  final Playlist? playlist;
  final VoidCallback onTap;

  const _HistoryTile({
    required this.entry,
    required this.playlist,
    required this.onTap,
  });

  // ── Resolved content lookup ────────────────────────────────────────────────

  /// Returns (title, thumbUrl, totalDuration?) for this entry.
  ({String title, String? thumb, Duration? total}) get _resolved {
    if (playlist == null) {
      return (title: entry.id, thumb: null, total: null);
    }
    switch (entry.type) {
      case ContentType.TV:
        final ch = playlist!.channels
            .where((c) => c.id == entry.id)
            .firstOrNull;
        return (
          title: ch?.name ?? entry.id,
          thumb: ch?.logo,
          total: null,
        );

      case ContentType.MOVIES:
        final m = playlist!.movies
            .where((m) => m.id == entry.id)
            .firstOrNull;
        return (
          title: m?.title ?? entry.id,
          thumb: m?.poster,
          total: m?.duration,
        );

      case ContentType.SERIES:
        final match =
            RegExp(r'^(.+)_S(\d+)E(\d+)$').firstMatch(entry.id);
        if (match == null) {
          return (title: entry.id, thumb: null, total: null);
        }
        final seriesId   = match.group(1)!;
        final seasonNum  = int.parse(match.group(2)!);
        final episodeNum = int.parse(match.group(3)!);
        final s = playlist!.series
            .where((s) => s.id == seriesId)
            .firstOrNull;
        final ep = s?.seasons
            .where((sn) => sn.seasonNumber == seasonNum)
            .firstOrNull
            ?.episodes
            .where((e) => e.episodeNumber == episodeNum)
            .firstOrNull;
        final label = s != null
            ? '${s.name} — T${seasonNum}E$episodeNum'
            : entry.id;
        return (
          title: label,
          thumb: s?.poster,
          total: ep?.duration,
        );
    }
  }

  // ── Visual helpers ─────────────────────────────────────────────────────────

  Color get _typeColor => switch (entry.type) {
        ContentType.TV     => AppColors.accentLive,
        ContentType.SERIES => AppColors.accentSeries,
        ContentType.MOVIES => AppColors.accentMovies,
      };

  String get _typeLabel => switch (entry.type) {
        ContentType.TV     => 'CANAL',
        ContentType.SERIES => 'SERIE',
        ContentType.MOVIES => 'PELI',
      };

  IconData get _typeIcon => switch (entry.type) {
        ContentType.TV     => Icons.live_tv,
        ContentType.SERIES => Icons.video_library,
        ContentType.MOVIES => Icons.movie,
      };

  /// "Visto hace X minutos/horas/días"
  String _relativeTime() {
    final diff = DateTime.now().difference(entry.timestamp);
    if (diff.inMinutes < 1)  return 'Ahora mismo';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours   < 24) return 'Hace ${diff.inHours} h';
    if (diff.inDays    < 7)  return 'Hace ${diff.inDays} días';
    final d = entry.timestamp;
    return '${d.day}/${d.month}/${d.year}';
  }

  /// "Minuto 24 de 120" or "X min vistos" when total is unknown.
  String? _positionLabel(Duration? total) {
    final pos = entry.position;
    if (pos == null || pos.inSeconds < 5) return null;
    if (entry.type == ContentType.TV)     return null; // live TV

    final posMins = pos.inMinutes;
    if (total != null && total.inMinutes > 0) {
      return 'Minuto $posMins de ${total.inMinutes}';
    }
    return '$posMins min vistos';
  }

  @override
  Widget build(BuildContext context) {
    final r     = _resolved;
    final posLbl = _positionLabel(r.total);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      leading: _HistoryThumb(
        url: r.thumb,
        typeIcon: _typeIcon,
        typeColor: _typeColor,
        isChannel: entry.type == ContentType.TV,
      ),
      title: Text(
        r.title,
        style: AppTextStyles.bodyLarge,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _TypeBadge(label: _typeLabel, color: _typeColor),
              const SizedBox(width: AppSpacing.sm),
              Text(_relativeTime(), style: AppTextStyles.bodySmall),
            ],
          ),
          if (posLbl != null) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                const Icon(Icons.play_circle_outline,
                    size: 12, color: AppColors.accent),
                const SizedBox(width: 3),
                Text(posLbl,
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.accent)),
              ],
            ),
          ],
        ],
      ),
      trailing: const Icon(Icons.chevron_right,
          color: AppColors.textSecondary, size: 20),
      shape: RoundedRectangleBorder(
          borderRadius: AppRadius.thumbnailRadius),
      onTap: onTap,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small shared widgets
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history, size: 72, color: AppColors.textDisabled),
          SizedBox(height: AppSpacing.base),
          Text('Sin historial', style: AppTextStyles.bodyMedium),
          SizedBox(height: AppSpacing.xs),
          Text('Reproduce algo para verlo aquí',
              style: AppTextStyles.bodySmall),
        ],
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _TypeBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: AppRadius.chipRadius,
      ),
      child: Text(label,
          style: AppTextStyles.badge.copyWith(color: color)),
    );
  }
}

class _HistoryThumb extends StatelessWidget {
  final String? url;
  final IconData typeIcon;
  final Color typeColor;
  final bool isChannel;

  const _HistoryThumb({
    required this.url,
    required this.typeIcon,
    required this.typeColor,
    required this.isChannel,
  });

  @override
  Widget build(BuildContext context) {
    if (url != null && url!.isNotEmpty) {
      return ClipRRect(
        borderRadius: AppRadius.thumbnailRadius,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Image.network(
            url!,
            fit: isChannel ? BoxFit.contain : BoxFit.cover,
            errorBuilder: (_, __, ___) => _fallback(),
          ),
        ),
      );
    }
    return _fallback();
  }

  Widget _fallback() => Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: typeColor.withValues(alpha: 0.15),
          borderRadius: AppRadius.thumbnailRadius,
        ),
        child: Icon(typeIcon, color: typeColor, size: 24),
      );
}

/// Red swipe-to-delete background.
class _SwipeDeleteBackground extends StatelessWidget {
  const _SwipeDeleteBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.error,
      alignment: Alignment.centerRight,
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.base),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.delete_outline, color: Colors.white, size: 26),
          SizedBox(height: 2),
          Text('Eliminar',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
