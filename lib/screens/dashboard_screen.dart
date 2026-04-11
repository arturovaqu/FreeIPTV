import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../services/storage_service.dart';
import '../services/media_service.dart';
import '../utils/constants.dart';
import '../utils/responsive.dart';
import 'player_screen.dart';

class DashboardScreen extends StatelessWidget {
  final Playlist? playlist;

  const DashboardScreen({super.key, this.playlist});

  @override
  Widget build(BuildContext context) {
    if (playlist == null) {
      return const Center(child: Text('Selecciona una playlist para comenzar', style: AppTextStyles.bodyLarge));
    }

    final device = getDeviceInfo(context);
    final padding = ResponsiveSpacing.getContentPadding(device);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        slivers: [
          // 1. Hero / Featured
          SliverToBoxAdapter(
            child: _DashboardHero(playlist: playlist!),
          ),

          // 2. Sections
          SliverPadding(
            padding: padding,
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const SizedBox(height: AppSpacing.md),
                
                // Continuar viendo
                _DashboardRow<HistoryEntry>(
                  title: 'Continuar Viendo',
                  items: context.watch<StorageService>().getHistory().take(10).toList(),
                  builder: (ctx, item) => _HistoryCard(entry: item),
                ),

                const SizedBox(height: AppSpacing.lg),

                // Canales Top
                _DashboardRow<Channel>(
                  title: 'Canales en Vivo',
                  items: playlist!.channels.take(12).toList(),
                  builder: (ctx, item) => _ContentCard(
                    title: item.name,
                    image: item.logo,
                    onTap: () => _playChannel(context, item),
                    isLive: true,
                  ),
                ),

                const SizedBox(height: AppSpacing.lg),

                // Películas
                _DashboardRow<Movie>(
                  title: 'Cine',
                  items: playlist!.movies.take(12).toList(),
                  builder: (ctx, item) => _ContentCard(
                    title: item.title,
                    image: item.poster,
                    onTap: () => _playMovie(context, item),
                  ),
                ),

                const SizedBox(height: AppSpacing.lg),

                // Series
                _DashboardRow<Series>(
                  title: 'Series',
                  items: playlist!.series.take(12).toList(),
                  builder: (ctx, item) => _ContentCard(
                    title: item.name,
                    image: item.poster,
                    onTap: () {}, // Navigate to series detail
                  ),
                ),
                
                const SizedBox(height: AppSpacing.xl),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  void _playChannel(BuildContext context, Channel channel) {
    MediaService.instance.playChannel(channel);
    Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerScreen()));
  }

  void _playMovie(BuildContext context, Movie movie) {
    MediaService.instance.playMovie(movie);
    Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerScreen()));
  }
}

// ── Dashboard Components ─────────────────────────────────────────────────────

class _DashboardHero extends StatelessWidget {
  final Playlist playlist;

  const _DashboardHero({required this.playlist});

  @override
  Widget build(BuildContext context) {
    final featured = playlist.channels.isNotEmpty ? playlist.channels.first : null;
    if (featured == null) return const SizedBox.shrink();

    return Container(
      height: 300,
      width: double.infinity,
      decoration: BoxDecoration(
        image: featured.logo != null && featured.logo!.isNotEmpty
            ? DecorationImage(
                image: NetworkImage(featured.logo!),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(
                  Colors.black.withOpacity(0.6),
                  BlendMode.darken,
                ),
              )
            : null,
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              AppColors.background.withOpacity(0.8),
              AppColors.background,
            ],
          ),
        ),
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.accentLive,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('EN VIVO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10)),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(featured.name, style: AppTextStyles.displayMedium),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () => MediaService.instance.playChannel(featured),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Ver Ahora'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.info_outline),
                  label: const Text('Más Info'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardRow<T> extends StatelessWidget {
  final String title;
  final List<T> items;
  final Widget Function(BuildContext, T) builder;

  const _DashboardRow({
    required this.title,
    required this.items,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTextStyles.headlineSmall),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: 180,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.md),
            itemBuilder: (ctx, i) => builder(ctx, items[i]),
          ),
        ),
      ],
    );
  }
}

class _ContentCard extends StatelessWidget {
  final String title;
  final String? image;
  final VoidCallback onTap;
  final bool isLive;

  const _ContentCard({
    required this.title,
    this.image,
    required this.onTap,
    this.isLive = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 120,
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (image != null && image!.isNotEmpty)
                Image.network(image!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _FallbackIcon())
              else
                _FallbackIcon(),
              
              // Bottom Title Overlay
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
                    ),
                  ),
                  child: Text(
                    title,
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _FallbackIcon() {
    return const Center(child: Icon(Icons.movie_filter, color: AppColors.textSecondary));
  }
}

class _HistoryCard extends StatelessWidget {
  final HistoryEntry entry;

  const _HistoryCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    // We need to find the actual content name from storage indices
    final storage = context.read<StorageService>();
    String name = 'Contenido';
    String? logo;
    
    if (entry.type == ContentType.TV) {
      final ch = storage.getChannelById(entry.id);
      name = ch?.name ?? name;
      logo = ch?.logo;
    } else if (entry.type == ContentType.MOVIES) {
      final mv = storage.getMovieById(entry.id);
      name = mv?.title ?? name;
      logo = mv?.poster;
    }

    return _ContentCard(
      title: name,
      image: logo,
      onTap: () {
        // Resume logic...
      },
    );
  }
}
