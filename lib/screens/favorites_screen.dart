import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import 'movies_list_screen.dart';
import 'player_screen.dart';
import 'series_list_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FavoritesScreen
// ─────────────────────────────────────────────────────────────────────────────

class FavoritesScreen extends StatelessWidget {
  final ContentType type;
  const FavoritesScreen({super.key, required this.type});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text('Favoritos — ${type.plural}',
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
      ),
      body: Consumer<StorageService>(
        builder: (context, storage, _) {
          final ids     = storage.getFavorites(type);
          final playlist = storage.getActivePlaylist();

          if (ids.isEmpty) {
            return _EmptyFavorites(type: type);
          }

          return switch (type) {
            ContentType.TV => _FavChannelList(
                ids: ids,
                playlist: playlist,
              ),
            ContentType.SERIES => _FavPosterGrid<Series>(
                ids: ids,
                items: playlist?.series ?? [],
                getId: (s) => s.id,
                getPoster: (s) => s.poster,
                getTitle: (s) => s.name,
                onTap: (s) => _openSeries(context, s),
                onRemove: (id) =>
                    storage.removeFavorite(id, ContentType.SERIES),
              ),
            ContentType.MOVIES => _FavPosterGrid<Movie>(
                ids: ids,
                items: playlist?.movies ?? [],
                getId: (m) => m.id,
                getPoster: (m) => m.poster,
                getTitle: (m) => m.title,
                onTap: (m) => _openMovie(context, m),
                onRemove: (id) =>
                    storage.removeFavorite(id, ContentType.MOVIES),
              ),
          };
        },
      ),
    );
  }

  // ── Navigation ──────────────────────────────────────────────────────────────

  void _openSeries(BuildContext context, Series s) =>
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => SeriesDetailSheet(series: s),
      );

  void _openMovie(BuildContext context, Movie m) =>
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => MovieDetailSheet(movie: m),
      );

  // ── Clear all ───────────────────────────────────────────────────────────────

  Future<void> _confirmClearAll(BuildContext context) async {
    final storage = context.read<StorageService>();
    final count   = storage.getFavorites(type).length;
    if (count == 0) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Limpiar favoritos',
            style: AppTextStyles.headlineSmall),
        content: Text(
          '¿Quitar los $count favoritos de ${type.plural.toLowerCase()}?',
          style: AppTextStyles.bodyMedium,
        ),
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
    if (ok == true) await storage.clearFavorites(type);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyFavorites extends StatelessWidget {
  final ContentType type;
  const _EmptyFavorites({required this.type});

  IconData get _icon => switch (type) {
        ContentType.TV     => Icons.live_tv,
        ContentType.SERIES => Icons.video_library,
        ContentType.MOVIES => Icons.movie,
      };

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, size: 72, color: AppColors.textDisabled),
          const SizedBox(height: AppSpacing.base),
          const Icon(Icons.favorite_border,
              size: 32, color: AppColors.textDisabled),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Sin favoritos',
            style: AppTextStyles.headlineSmall
                .copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Marca ${type.plural.toLowerCase()} como favoritos\n'
            'para verlos aquí',
            style: AppTextStyles.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Channel list  (ContentType.TV)
// ─────────────────────────────────────────────────────────────────────────────

class _FavChannelList extends StatelessWidget {
  final List<String> ids;
  final Playlist? playlist;

  const _FavChannelList({required this.ids, required this.playlist});

  @override
  Widget build(BuildContext context) {
    final storage  = context.read<StorageService>();
    final all      = playlist?.channels ?? [];
    final channels = ids
        .map<Channel?>((id) => all.where((c) => c.id == id).firstOrNull)
        .whereType<Channel>()
        .toList();

    if (channels.isEmpty) {
      return const Center(
        child: Padding(
          padding: AppSpacing.paddingBase,
          child: Text(
            'Los canales favoritos no están en la playlist activa.',
            style: AppTextStyles.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: AppSpacing.paddingMD,
      itemCount: channels.length,
      itemBuilder: (context, i) {
        final ch = channels[i];
        return Dismissible(
          key: ValueKey(ch.id),
          direction: DismissDirection.endToStart,
          onDismissed: (_) =>
              storage.removeFavorite(ch.id, ContentType.TV),
          background: const _SwipeDeleteBackground(),
          child: _ChannelFavTile(
            channel: ch,
            allChannels: channels,
          ),
        );
      },
    );
  }
}

class _ChannelFavTile extends StatelessWidget {
  final Channel channel;
  final List<Channel> allChannels;
  const _ChannelFavTile(
      {required this.channel, required this.allChannels});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      leading: _Thumb.channel(url: channel.logo),
      title: Text(channel.name,
          style: AppTextStyles.bodyLarge,
          overflow: TextOverflow.ellipsis),
      subtitle: Text(channel.group,
          style: AppTextStyles.bodySmall,
          overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right,
          color: AppColors.textSecondary, size: 20),
      shape: RoundedRectangleBorder(
          borderRadius: AppRadius.thumbnailRadius),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlayerScreen.channel(
            channel: channel,
            channels: allChannels,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Poster grid  (ContentType.SERIES / MOVIES)
// ─────────────────────────────────────────────────────────────────────────────

class _FavPosterGrid<T> extends StatelessWidget {
  final List<String> ids;
  final List<T> items;
  final String Function(T) getId;
  final String? Function(T) getPoster;
  final String Function(T) getTitle;
  final void Function(T) onTap;
  final void Function(String) onRemove;

  const _FavPosterGrid({
    required this.ids,
    required this.items,
    required this.getId,
    required this.getPoster,
    required this.getTitle,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final ordered = ids
        .map<T?>((id) =>
            items.where((x) => getId(x) == id).firstOrNull)
        .whereType<T>()
        .toList();

    if (ordered.isEmpty) {
      return const Center(
        child: Padding(
          padding: AppSpacing.paddingBase,
          child: Text(
            'Los elementos favoritos no están en la playlist activa.',
            style: AppTextStyles.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return GridView.builder(
      padding: AppSpacing.paddingMD,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 2 / 3,
        crossAxisSpacing: AppSpacing.sm,
        mainAxisSpacing: AppSpacing.sm,
      ),
      itemCount: ordered.length,
      itemBuilder: (context, i) {
        final item  = ordered[i];
        final id    = getId(item);
        final poster = getPoster(item);
        final title = getTitle(item);

        return Dismissible(
          key: ValueKey(id),
          direction: DismissDirection.endToStart,
          onDismissed: (_) => onRemove(id),
          background: ClipRRect(
            borderRadius: AppRadius.thumbnailRadius,
            child: const _SwipeDeleteBackground(),
          ),
          child: _PosterFavCard(
            poster: poster,
            title: title,
            onTap: () => onTap(item),
          ),
        );
      },
    );
  }
}

class _PosterFavCard extends StatelessWidget {
  final String? poster;
  final String title;
  final VoidCallback onTap;

  const _PosterFavCard({
    required this.poster,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: AppRadius.thumbnailRadius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _Thumb.poster(url: poster),
            // Gradient + title
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xs, AppSpacing.xl,
                    AppSpacing.xs, AppSpacing.xs),
                child: Text(
                  title,
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.textPrimary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            // Swipe hint label
            Positioned(
              top: AppSpacing.xs,
              right: AppSpacing.xs,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.favorite,
                    color: AppColors.error, size: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared small widgets
// ─────────────────────────────────────────────────────────────────────────────

/// Red swipe-to-delete background shown behind a Dismissible.
class _SwipeDeleteBackground extends StatelessWidget {
  const _SwipeDeleteBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.error,
      alignment: Alignment.centerRight,
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.base),
      child: const Icon(Icons.delete_outline,
          color: Colors.white, size: 28),
    );
  }
}

/// Unified thumbnail widget for channels and posters.
class _Thumb extends StatelessWidget {
  final String? url;
  final double width;
  final double height;
  final bool isChannel;

  const _Thumb.channel({this.url})
      : width = 48,
        height = 48,
        isChannel = true;

  const _Thumb.poster({this.url})
      : width = double.infinity,
        height = double.infinity,
        isChannel = false;

  @override
  Widget build(BuildContext context) {
    Widget image() {
      if (url == null || url!.isEmpty) return _placeholder();
      return Image.network(
        url!,
        fit: isChannel ? BoxFit.contain : BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }

    if (!isChannel) return image();

    return ClipRRect(
      borderRadius: AppRadius.thumbnailRadius,
      child: SizedBox(width: width, height: height, child: image()),
    );
  }

  Widget _placeholder() => Container(
        color: AppColors.surfaceVariant,
        child: Center(
          child: Icon(
            isChannel ? Icons.live_tv : Icons.image,
            color: AppColors.textDisabled,
            size: isChannel ? 22 : 36,
          ),
        ),
      );
}
