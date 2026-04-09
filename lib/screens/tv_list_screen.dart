import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/media_service.dart';
import '../services/search_service.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../utils/responsive.dart';
import 'player_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TVListScreen
// ─────────────────────────────────────────────────────────────────────────────

class TVListScreen extends StatefulWidget {
  final Playlist? playlist;
  const TVListScreen({super.key, this.playlist});

  @override
  State<TVListScreen> createState() => _TVListScreenState();
}

class _TVListScreenState extends State<TVListScreen>
    with AutomaticKeepAliveClientMixin {
  // ── State ──────────────────────────────────────────────────────────────────

  final _searchCtrl   = TextEditingController();
  final _searchFocus  = FocusNode();
  String  _query           = '';
  String  _selectedCategory = 'Todos';
  List<Channel> _filtered  = [];

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  bool get wantKeepAlive => true; // keep state when switching tabs

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
    _applyFilter();
  }

  @override
  void didUpdateWidget(TVListScreen old) {
    super.didUpdateWidget(old);
    // Playlist changed → reset and re-filter
    if (old.playlist?.id != widget.playlist?.id) {
      _selectedCategory = 'Todos';
      _query = '';
      _searchCtrl.clear();
      _applyFilter();
    }
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ── Filtering logic ────────────────────────────────────────────────────────

  List<Channel> get _allChannels => widget.playlist?.channels ?? [];

  void _onSearchChanged() {
    if (_searchCtrl.text != _query) {
      setState(() {
        _query = _searchCtrl.text;
        _applyFilter();
      });
    }
  }

  void _applyFilter() {
    final playlist = widget.playlist;
    if (playlist == null) {
      _filtered = [];
      return;
    }

    // 1. Search (fuzzy or full list)
    List<Channel> result;
    if (_query.trim().isEmpty) {
      result = List<Channel>.from(_allChannels);
    } else {
      result = SearchService.instance
          .searchByType(_query, playlist, ContentType.TV)
          .cast<Channel>();
    }

    // 2. Category filter
    if (_selectedCategory != 'Todos') {
      result =
          result.where((c) => c.group == _selectedCategory).toList();
    }

    _filtered = result;
  }

  List<String> get _categories {
    if (widget.playlist == null) return [];
    return [
      'Todos',
      ...SearchService.instance
          .getCategories(ContentType.TV, widget.playlist!),
    ];
  }

  void _selectCategory(String cat) {
    setState(() {
      _selectedCategory = cat;
      _applyFilter();
    });
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  void _openPlayer(Channel channel) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen.channel(channel: channel),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (widget.playlist == null) {
      return _EmptyState(
        icon: Icons.live_tv,
        message: 'Agrega una playlist para ver canales',
      );
    }

    return Column(
      children: [
        _buildSearchBar(),
        _buildCategoryFilter(),
        Expanded(child: _buildChannelList()),
      ],
    );
  }

  // ── Search bar ─────────────────────────────────────────────────────────────

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.base, AppSpacing.md, AppSpacing.base, AppSpacing.sm),
      child: TextField(
        controller: _searchCtrl,
        focusNode: _searchFocus,
        style: AppTextStyles.searchInput,
        decoration: InputDecoration(
          hintText: 'Buscar canal...',
          hintStyle: AppTextStyles.bodyMedium,
          prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
          suffixIcon: _query.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear,
                      color: AppColors.textSecondary),
                  onPressed: () {
                    _searchCtrl.clear();
                    _searchFocus.unfocus();
                  },
                )
              : null,
          filled: true,
          fillColor: AppColors.surfaceVariant,
          contentPadding: const EdgeInsets.symmetric(
              vertical: AppSpacing.md, horizontal: AppSpacing.base),
          border: OutlineInputBorder(
            borderRadius: AppRadius.buttonRadius,
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: AppRadius.buttonRadius,
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: AppRadius.buttonRadius,
            borderSide:
                const BorderSide(color: AppColors.accent, width: 2),
          ),
        ),
        onSubmitted: (_) => _searchFocus.unfocus(),
      ),
    );
  }

  // ── Category chips ─────────────────────────────────────────────────────────

  Widget _buildCategoryFilter() {
    final cats = _categories;
    if (cats.length <= 1) return const SizedBox.shrink();

    return SizedBox(
      height: 42,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
        scrollDirection: Axis.horizontal,
        itemCount: cats.length,
        separatorBuilder: (_, __) =>
            const SizedBox(width: AppSpacing.sm),
        itemBuilder: (_, i) {
          final cat = cats[i];
          final selected = cat == _selectedCategory;
          return _CategoryChip(
            label: cat,
            selected: selected,
            onTap: () => _selectCategory(cat),
          );
        },
      ),
    );
  }

  // ── Channel list ───────────────────────────────────────────────────────────

  Widget _buildChannelList() {
    if (_filtered.isEmpty) {
      return _EmptyState(
        icon: Icons.search_off,
        message: _query.isNotEmpty
            ? 'Sin resultados para "$_query"'
            : 'Sin canales en esta categoría',
      );
    }

    return ValueListenableBuilder<Channel?>(
      valueListenable: MediaService.instance.currentChannelNotifier,
      builder: (_, playingChannel, __) {
        return Consumer<StorageService>(
          builder: (context, storage, __) {
            final device     = getDeviceInfo(context);
            final cols       = ResponsiveGrid.getChannelColumns(device);
            final spacing    = ResponsiveSpacing.getItemSpacing(device);
            final tileHeight = ResponsiveSpacing.getChannelTileHeight(device);

            Widget buildTile(int i) {
              final ch        = _filtered[i];
              final isPlaying = playingChannel?.id == ch.id;
              final isFav     = storage.isFavorite(ch.id, ContentType.TV);
              return _ChannelTile(
                channel: ch,
                isPlaying: isPlaying,
                isFavorite: isFav,
                channelIndex: i + 1,
                onTap: () => _openPlayer(ch),
                onFavoriteToggle: () {
                  if (isFav) {
                    storage.removeFavorite(ch.id, ContentType.TV);
                  } else {
                    storage.saveFavorite(ch.id, ContentType.TV);
                  }
                },
              );
            }

            if (cols == 1) {
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                itemCount: _filtered.length,
                itemBuilder: (_, i) => buildTile(i),
              );
            }

            return GridView.builder(
              padding: EdgeInsets.fromLTRB(spacing, 0, spacing, AppSpacing.xxl),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                mainAxisExtent: tileHeight,
                crossAxisSpacing: spacing,
                mainAxisSpacing: 2,
              ),
              itemCount: _filtered.length,
              itemBuilder: (_, i) => buildTile(i),
            );
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ChannelTile
// ─────────────────────────────────────────────────────────────────────────────

class _ChannelTile extends StatelessWidget {
  final Channel channel;
  final bool    isPlaying;
  final bool    isFavorite;
  final int     channelIndex;
  final VoidCallback onTap;
  final VoidCallback onFavoriteToggle;

  const _ChannelTile({
    required this.channel,
    required this.isPlaying,
    required this.isFavorite,
    required this.channelIndex,
    required this.onTap,
    required this.onFavoriteToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (node, event) {
        // Allow Enter/Select to trigger tap on TV remote
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.enter) {
          onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (ctx) {
          final hasFocus = Focus.of(ctx).hasFocus;
          return AnimatedContainer(
            duration: AppDurations.fast,
            margin: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm, vertical: 2),
            decoration: BoxDecoration(
              color: isPlaying
                  ? AppColors.accentDim
                  : hasFocus
                      ? AppColors.cardHover
                      : AppColors.card,
              borderRadius: AppRadius.thumbnailRadius,
              border: Border.all(
                color: isPlaying
                    ? AppColors.accentLive
                    : hasFocus
                        ? AppColors.focusBorder
                        : Colors.transparent,
                width: isPlaying || hasFocus ? 1.5 : 0,
              ),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.base, vertical: AppSpacing.sm),
              minVerticalPadding: AppSpacing.sm,
              leading: _ChannelLogo(
                logoUrl: channel.logo,
                channelName: channel.name,
                isPlaying: isPlaying,
              ),
              title: Text(
                channel.name,
                style: AppTextStyles.bodyLarge.copyWith(
                  color: isPlaying
                      ? AppColors.textPrimary
                      : AppColors.textPrimary,
                  fontWeight:
                      isPlaying ? FontWeight.w600 : FontWeight.w400,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Row(
                children: [
                  if (isPlaying) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.accentLive,
                        borderRadius: AppRadius.chipRadius,
                      ),
                      child: const Text('EN VIVO',
                          style: AppTextStyles.badge),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  Flexible(
                    child: Text(
                      channel.group,
                      style: AppTextStyles.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Channel number
                  SizedBox(
                    width: 40,
                    child: Text(
                      channelIndex.toString(),
                      style: AppTextStyles.channelNumber,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  // Favorite button
                  IconButton(
                    icon: Icon(
                      isFavorite ? Icons.favorite : Icons.favorite_border,
                      color: isFavorite
                          ? AppColors.error
                          : AppColors.textDisabled,
                      size: 22,
                    ),
                    onPressed: onFavoriteToggle,
                    tooltip: isFavorite ? 'Quitar favorito' : 'Agregar favorito',
                  ),
                ],
              ),
              onTap: onTap,
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ChannelLogo
// ─────────────────────────────────────────────────────────────────────────────

class _ChannelLogo extends StatelessWidget {
  final String?  logoUrl;
  final String   channelName;
  final bool     isPlaying;

  const _ChannelLogo({
    required this.logoUrl,
    required this.channelName,
    required this.isPlaying,
  });

  @override
  Widget build(BuildContext context) {
    final initials =
        channelName.isNotEmpty ? channelName[0].toUpperCase() : '?';

    return SizedBox(
      width: 48,
      height: 48,
      child: ClipRRect(
        borderRadius: AppRadius.thumbnailRadius,
        child: logoUrl != null && logoUrl!.isNotEmpty
            ? Image.network(
                logoUrl!,
                width: 48,
                height: 48,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => _InitialAvatar(
                    initials: initials, isPlaying: isPlaying),
              )
            : _InitialAvatar(initials: initials, isPlaying: isPlaying),
      ),
    );
  }
}

class _InitialAvatar extends StatelessWidget {
  final String initials;
  final bool   isPlaying;

  const _InitialAvatar(
      {required this.initials, required this.isPlaying});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      color: isPlaying ? AppColors.accentLive : AppColors.surfaceVariant,
      alignment: Alignment.center,
      child: Text(
        initials,
        style: AppTextStyles.headlineSmall.copyWith(
          color: isPlaying ? Colors.white : AppColors.textSecondary,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CategoryChip
// ─────────────────────────────────────────────────────────────────────────────

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool   selected;
  final VoidCallback onTap;

  const _CategoryChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppDurations.fast,
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.base, vertical: AppSpacing.xs + 2),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : AppColors.surfaceVariant,
          borderRadius: AppRadius.chipRadius,
          border: Border.all(
            color:
                selected ? AppColors.accent : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.labelMedium.copyWith(
            color: selected
                ? AppColors.textInverse
                : AppColors.textSecondary,
            fontWeight:
                selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _EmptyState
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String   message;

  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: AppColors.textDisabled),
          const SizedBox(height: AppSpacing.base),
          Text(message,
              style: AppTextStyles.bodyMedium,
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
