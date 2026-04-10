import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
              _SwitchSettingsTile(
                title: 'Subtítulos por defecto',
                subtitle: 'Activar subtítulos automáticamente al reproducir',
                value: defaultSubs,
                onChanged: (v) => storage.setDefaultSubtitles(v),
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
// _SectionHeader
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

// ─────────────────────────────────────────────────────────────────────────────
// _SettingsTile — accionable (tap + D-Pad Enter)
// ─────────────────────────────────────────────────────────────────────────────

class _SettingsTile extends StatefulWidget {
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
  State<_SettingsTile> createState() => _SettingsTileState();
}

class _SettingsTileState extends State<_SettingsTile> {
  final _focusNode = FocusNode();
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!mounted) return;
    setState(() => _hasFocus = _focusNode.hasFocus);
    if (_focusNode.hasFocus) {
      // Hace scroll hasta este ítem para que siempre sea visible.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.select) &&
            widget.onTap != null) {
          widget.onTap!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: AppDurations.fast,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: AppRadius.cardRadius,
          border: Border.all(
            color: _hasFocus ? AppColors.focusBorder : Colors.transparent,
            width: 2,
          ),
          boxShadow: _hasFocus
              ? [
                  BoxShadow(
                    color: AppColors.focusGlow,
                    blurRadius: 12,
                    spreadRadius: 1,
                  )
                ]
              : [],
        ),
        child: ListTile(
          leading: Icon(
            widget.icon,
            color: _hasFocus ? AppColors.accent : AppColors.textSecondary,
            size: 22,
          ),
          title: Text(widget.title, style: AppTextStyles.bodyLarge),
          subtitle: Text(widget.subtitle, style: AppTextStyles.bodySmall),
          trailing: widget.onTap != null
              ? Icon(
                  Icons.chevron_right,
                  color: _hasFocus
                      ? AppColors.accent
                      : AppColors.textSecondary,
                  size: 20,
                )
              : null,
          onTap: widget.onTap,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SwitchSettingsTile — toggle con D-Pad Enter + foco visual
// ─────────────────────────────────────────────────────────────────────────────

class _SwitchSettingsTile extends StatefulWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchSettingsTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  State<_SwitchSettingsTile> createState() => _SwitchSettingsTileState();
}

class _SwitchSettingsTileState extends State<_SwitchSettingsTile> {
  final _focusNode = FocusNode();
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!mounted) return;
    setState(() => _hasFocus = _focusNode.hasFocus);
    if (_focusNode.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      // D-Pad Enter/Select activa el toggle
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.select)) {
          widget.onChanged(!widget.value);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: AppDurations.fast,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: AppRadius.cardRadius,
          border: Border.all(
            color: _hasFocus ? AppColors.focusBorder : Colors.transparent,
            width: 2,
          ),
          boxShadow: _hasFocus
              ? [
                  BoxShadow(
                    color: AppColors.focusGlow,
                    blurRadius: 12,
                    spreadRadius: 1,
                  )
                ]
              : [],
        ),
        child: SwitchListTile(
          title: Text(widget.title, style: AppTextStyles.bodyLarge),
          subtitle: Text(widget.subtitle, style: AppTextStyles.bodyMedium),
          value: widget.value,
          activeColor: AppColors.accent,
          onChanged: widget.onChanged,
        ),
      ),
    );
  }
}
