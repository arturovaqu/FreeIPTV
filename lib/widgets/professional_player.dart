import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';

import '../services/media_service.dart';
import '../utils/constants.dart';

/// A professional video player widget based on Media Kit.
/// It displays the video content and provides hooks for advanced controls
/// like audio/subtitle track switching.
class ProfessionalPlayer extends StatelessWidget {
  final VideoController controller;

  const ProfessionalPlayer({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 1. The Video Renderer itself
        Center(
          child: Video(
            controller: controller,
            fill: Colors.black,
          ),
        ),

        // 2. We could add specific Media Kit overlays here if needed, 
        // but for Phase 3 we'll let PlayerScreen handle the primary overlays
        // while this widget provides the video foundation with HW acceleration.
      ],
    );
  }
}

/// A specialized modal for selecting audio/subtitle tracks in the Pro Engine.
class TrackSelectorModal extends StatelessWidget {
  const TrackSelectorModal({super.key});

  @override
  Widget build(BuildContext context) {
    final media = MediaService.instance;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: AppSpacing.sm),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textDisabled,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Row(
              children: [
                const Icon(Icons.settings_input_component, color: AppColors.accent, size: 24),
                const SizedBox(width: AppSpacing.md),
                Text('Configuración de Pistas', style: AppTextStyles.headlineSmall),
              ],
            ),
          ),
          const Divider(height: AppSpacing.xl, color: AppColors.border),
          
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: AppSpacing.xl),
              child: Column(
                children: [
                  _TrackSection(
                    title: 'Audio',
                    icon: Icons.audiotrack,
                    tracks: media.audioTracksNotifier.value,
                    activeTrack: media.activeAudioTrackNotifier.value,
                    onSelect: (t) => media.setAudioTrack(t as AudioTrack),
                  ),
                  const Divider(height: AppSpacing.lg, color: AppColors.border, indent: AppSpacing.lg, endIndent: AppSpacing.lg),
                  _TrackSection(
                    title: 'Subtítulos',
                    icon: Icons.subtitles,
                    tracks: media.subtitleTracksNotifier.value,
                    activeTrack: media.activeSubtitleTrackNotifier.value,
                    onSelect: (t) => media.setSubtitleTrack(t as SubtitleTrack),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackSection<T> extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<T> tracks;
  final T? activeTrack;
  final Function(T) onSelect;

  const _TrackSection({
    required this.title,
    required this.icon,
    required this.tracks,
    required this.activeTrack,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text('No hay pistas de $title disponibles', 
            style: AppTextStyles.bodyMedium.copyWith(fontStyle: FontStyle.italic)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: AppSpacing.sm),
              Text(title.toUpperCase(), 
                  style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary, letterSpacing: 1.2)),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        ...tracks.map((t) {
          final isSelected = t == activeTrack;
          String label = 'Pista ${tracks.indexOf(t) + 1}';
          
          if (t is AudioTrack) {
            label = t.title ?? t.language ?? label;
          } else if (t is SubtitleTrack) {
            label = t.title ?? t.language ?? label;
          }

          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            leading: Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? AppColors.accent : AppColors.textDisabled,
            ),
            title: Text(label, 
              style: AppTextStyles.bodyLarge.copyWith(
                color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            onTap: () {
              onSelect(t);
              Navigator.pop(context);
            },
          );
        }),
      ],
    );
  }
}
