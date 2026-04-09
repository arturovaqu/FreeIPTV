import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SettingsScreen
// ─────────────────────────────────────────────────────────────────────────────

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title:
            const Text('Configuración', style: AppTextStyles.headlineMedium),
      ),
      body: Consumer<StorageService>(
        builder: (context, storage, _) {
          final defaultSubs  = storage.getDefaultSubtitles();
          final historyCount = storage.getHistory().length;
          final favCount     = ContentType.values
              .map((t) => storage.getFavorites(t).length)
              .fold<int>(0, (a, b) => a + b);

          return ListView(
            padding: AppSpacing.paddingBase,
            children: [
              // ── Reproducción ─────────────────────────────────────────
              const _SectionHeader(label: 'Reproducción'),
              Card(
                color: AppColors.card,
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                    borderRadius: AppRadius.cardRadius),
                child: SwitchListTile(
                  title: const Text('Subtítulos por defecto',
                      style: AppTextStyles.bodyLarge),
                  subtitle: const Text(
                      'Activar subtítulos automáticamente al reproducir',
                      style: AppTextStyles.bodyMedium),
                  value: defaultSubs,
                  activeColor: AppColors.accent,
                  onChanged: (v) => storage.setDefaultSubtitles(v),
                ),
              ),

              const SizedBox(height: AppSpacing.base),

              // ── Datos ─────────────────────────────────────────────────
              const _SectionHeader(label: 'Datos'),
              _SettingsTile(
                icon: Icons.history,
                title: 'Limpiar historial',
                subtitle: '$historyCount entradas guardadas',
                onTap: historyCount > 0
                    ? () => _clearHistory(context, storage, historyCount)
                    : null,
              ),
              const SizedBox(height: 2),
              _SettingsTile(
                icon: Icons.favorite,
                title: 'Limpiar favoritos',
                subtitle: '$favCount elementos en total',
                onTap: favCount > 0
                    ? () => _clearFavorites(context, storage, favCount)
                    : null,
              ),

              const SizedBox(height: AppSpacing.base),

              // ── Acerca de ─────────────────────────────────────────────
              const _SectionHeader(label: 'Acerca de'),
              const _SettingsTile(
                icon: Icons.tv,
                title: 'IPTV Player',
                subtitle: 'Versión 1.0.0',
                onTap: null,
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Clear helpers ──────────────────────────────────────────────────────────

  Future<void> _clearHistory(
      BuildContext context, StorageService storage, int count) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Limpiar historial',
            style: AppTextStyles.headlineSmall),
        content: Text('¿Eliminar $count entradas del historial?',
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
    if (confirmed == true) {
      await storage.clearHistory();
    }
  }

  Future<void> _clearFavorites(
      BuildContext context, StorageService storage, int count) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Limpiar favoritos',
            style: AppTextStyles.headlineSmall),
        content: Text(
            '¿Eliminar los $count favoritos de todos los tipos?',
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
    if (confirmed == true) {
      await storage.clearFavorites();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.xs, AppSpacing.sm, AppSpacing.xs, AppSpacing.xs),
      child: Text(
        label.toUpperCase(),
        style: AppTextStyles.labelSmall.copyWith(
            color: AppColors.accent, letterSpacing: 1.5),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.card,
      margin: EdgeInsets.zero,
      shape:
          RoundedRectangleBorder(borderRadius: AppRadius.cardRadius),
      child: ListTile(
        leading: Icon(icon, color: AppColors.textSecondary, size: 22),
        title: Text(title, style: AppTextStyles.bodyLarge),
        subtitle: Text(subtitle, style: AppTextStyles.bodySmall),
        trailing: onTap != null
            ? const Icon(Icons.chevron_right,
                color: AppColors.textSecondary, size: 20)
            : null,
        onTap: onTap,
      ),
    );
  }
}
