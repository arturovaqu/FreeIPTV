import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/models.dart';
import '../utils/constants.dart';
import 'favorite_button.dart';

/// TV-optimised list row for a single [Channel].
///
/// Highlights when [isActive] (currently playing) with an accent border and
/// "EN VIVO" badge. Supports D-Pad Enter key for activation.
class ChannelListItem extends StatelessWidget {
  final Channel  channel;

  /// Whether this channel is currently playing.
  final bool     isActive;

  final bool     isFavorite;

  /// Position in the visible list (1-based), shown as channel number.
  final int?     channelIndex;

  final VoidCallback onTap;
  final VoidCallback onFavoriteTap;

  const ChannelListItem({
    super.key,
    required this.channel,
    required this.isActive,
    required this.isFavorite,
    required this.onTap,
    required this.onFavoriteTap,
    this.channelIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.enter) {
          onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(builder: (ctx) {
        final hasFocus = Focus.of(ctx).hasFocus;
        return AnimatedContainer(
          duration: AppDurations.fast,
          margin: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm, vertical: 2),
          decoration: BoxDecoration(
            color: isActive
                ? AppColors.accentDim
                : hasFocus
                    ? AppColors.cardHover
                    : AppColors.card,
            borderRadius: AppRadius.thumbnailRadius,
            border: Border.all(
              color: isActive
                  ? AppColors.accentLive
                  : hasFocus
                      ? AppColors.focusBorder
                      : Colors.transparent,
              width: isActive || hasFocus ? 1.5 : 0,
            ),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.base, vertical: AppSpacing.sm),
            minVerticalPadding: AppSpacing.sm,

            // ── Leading: channel logo ──────────────────────────────────
            leading: _ChannelLogo(
              url: channel.logo,
              name: channel.name,
              isActive: isActive,
            ),

            // ── Title ─────────────────────────────────────────────────
            title: Text(
              channel.name,
              style: AppTextStyles.bodyLarge.copyWith(
                fontWeight:
                    isActive ? FontWeight.w600 : FontWeight.w400,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),

            // ── Subtitle: group + EN VIVO badge ───────────────────────
            subtitle: Row(
              children: [
                if (isActive) ...[
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

            // ── Trailing: channel number + favourite ──────────────────
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (channelIndex != null)
                  SizedBox(
                    width: 38,
                    child: Text(
                      channelIndex.toString(),
                      style: AppTextStyles.channelNumber,
                      textAlign: TextAlign.center,
                    ),
                  ),
                FavoriteButton(
                  isFavorite: isFavorite,
                  onPressed: onFavoriteTap,
                  contentType: ContentType.TV,
                  size: FavoriteButtonSize.small,
                ),
              ],
            ),

            onTap: onTap,
          ),
        );
      }),
    );
  }
}

// ─── Channel logo ─────────────────────────────────────────────────────────────

class _ChannelLogo extends StatelessWidget {
  final String? url;
  final String  name;
  final bool    isActive;

  const _ChannelLogo({this.url, required this.name, required this.isActive});

  @override
  Widget build(BuildContext context) {
    final initial =
        name.isNotEmpty ? name[0].toUpperCase() : '?';

    return SizedBox(
      width: 48, height: 48,
      child: ClipRRect(
        borderRadius: AppRadius.thumbnailRadius,
        child: url != null && url!.isNotEmpty
            ? Image.network(
                url!,
                width: 48, height: 48,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) =>
                    _Initial(initial: initial, isActive: isActive),
              )
            : _Initial(initial: initial, isActive: isActive),
      ),
    );
  }
}

class _Initial extends StatelessWidget {
  final String initial;
  final bool   isActive;
  const _Initial({required this.initial, required this.isActive});

  @override
  Widget build(BuildContext context) => Container(
        color: isActive
            ? AppColors.accentLive
            : AppColors.surfaceVariant,
        alignment: Alignment.center,
        child: Text(
          initial,
          style: AppTextStyles.headlineSmall.copyWith(
            color: isActive ? Colors.white : AppColors.textSecondary,
          ),
        ),
      );
}
