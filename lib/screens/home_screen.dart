import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../services/m3u_parser.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../utils/responsive.dart';
import 'favorites_screen.dart';
import 'history_screen.dart';
import 'movies_list_screen.dart';
import 'qr_scanner_screen.dart';
import 'search_screen.dart';
import 'series_list_screen.dart';
import 'settings_screen.dart';
import 'tv_list_screen.dart';

const _uuid = Uuid();

// ─────────────────────────────────────────────────────────────────────────────
// HomeScreen
// ─────────────────────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  static const _tabs = [
    (icon: Icons.live_tv,        label: 'Canales'),
    (icon: Icons.video_library,  label: 'Series'),
    (icon: Icons.movie,          label: 'Películas'),
    (icon: Icons.search,         label: 'Buscar'),
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

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Consumer<StorageService>(
      builder: (context, storage, _) {
        final playlists   = storage.getPlaylists();
        final active      = storage.getActivePlaylist();
        final hasPlaylist = playlists.isNotEmpty;

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: _buildAppBar(context, storage, playlists, active, hasPlaylist),
          drawer: _buildDrawer(context, storage, playlists, active),
          body: Column(
            children: [
              _buildTabBar(),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    TVListScreen(playlist: active),
                    SeriesListScreen(playlist: active),
                    MoviesListScreen(playlist: active),
                    SearchScreen(playlist: active),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── AppBar ─────────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    StorageService storage,
    List<Playlist> playlists,
    Playlist? active,
    bool hasPlaylist,
  ) {
    final device = getDeviceInfo(context);
    return AppBar(
      backgroundColor: AppColors.surface,
      elevation: 0,
      centerTitle: false,
      toolbarHeight: ResponsiveSpacing.getAppBarHeight(device),
      title: Text(
        'IPTV Player',
        style: AppTextStyles.headlineMedium.copyWith(
          fontSize: ResponsiveSpacing.getTitleFontSize(device),
        ),
      ),
      actions: [
        if (!hasPlaylist)
          _AppBarButton(
            icon: Icons.add,
            label: 'Agregar Playlist',
            onPressed: () => _showAddPlaylistDialog(context, storage),
          )
        else
          _PlaylistDropdown(
            playlists: playlists,
            active: active,
            onSelect: (p) => storage.setActivePlaylist(p.id),
            onAdd: () => _showAddPlaylistDialog(context, storage),
          ),
        const SizedBox(width: AppSpacing.sm),
      ],
    );
  }

  // ── TabBar ─────────────────────────────────────────────────────────────────

  Widget _buildTabBar() {
    final device  = getDeviceInfo(context);
    final iconSz  = ResponsiveSpacing.getIconSize(device);
    final bodyFs  = ResponsiveSpacing.getBodyFontSize(device);
    return Container(
      color: AppColors.surface,
      child: TabBar(
        controller: _tabController,
        indicatorColor: AppColors.accent,
        indicatorWeight: 3,
        labelColor: AppColors.accent,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle: AppTextStyles.labelLarge.copyWith(fontSize: bodyFs - 1),
        unselectedLabelStyle: AppTextStyles.labelMedium.copyWith(fontSize: bodyFs - 2),
        tabs: _tabs
            .map((t) => Tab(
                  icon: Icon(t.icon, size: iconSz),
                  text: t.label,
                  iconMargin: const EdgeInsets.only(bottom: 2),
                ))
            .toList(),
      ),
    );
  }

  // ── Drawer ────────────────────────────────────────────────────────────────

  Widget _buildDrawer(
    BuildContext context,
    StorageService storage,
    List<Playlist> playlists,
    Playlist? active,
  ) {
    return Drawer(
      backgroundColor: AppColors.surface,
      child: SafeArea(
        child: ListView(
          padding: AppSpacing.paddingMD,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.lg, horizontal: AppSpacing.sm),
              child: Row(
                children: [
                  const Icon(Icons.tv, color: AppColors.accent, size: 28),
                  const SizedBox(width: AppSpacing.sm),
                  Text('IPTV Player', style: AppTextStyles.headlineSmall),
                ],
              ),
            ),
            const Divider(color: AppColors.border),

            // ── Mis Playlists ────────────────────────────────────────────
            _DrawerSectionHeader(label: 'Mis Playlists'),
            _DrawerItem(
              icon: Icons.add_circle_outline,
              label: 'Nueva Playlist',
              onTap: () {
                Navigator.pop(context);
                _showAddPlaylistDialog(context, storage);
              },
            ),
            ...playlists.map((p) => _PlaylistTile(
                  playlist: p,
                  isActive: active?.id == p.id,
                  onSelect: () {
                    storage.setActivePlaylist(p.id);
                    Navigator.pop(context);
                  },
                  onEdit: () {
                    Navigator.pop(context);
                    _showEditPlaylistDialog(context, storage, p);
                  },
                  onDelete: () {
                    Navigator.pop(context);
                    _showDeleteConfirm(context, storage, p);
                  },
                )),

            const Divider(color: AppColors.border),

            // ── Favoritos ────────────────────────────────────────────────
            _DrawerSectionHeader(label: 'Favoritos'),
            _DrawerItem(
              icon: Icons.live_tv,
              label: 'Canales favoritos',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const FavoritesScreen(type: ContentType.TV),
                  ),
                );
              },
            ),
            _DrawerItem(
              icon: Icons.video_library,
              label: 'Series favoritas',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const FavoritesScreen(type: ContentType.SERIES),
                  ),
                );
              },
            ),
            _DrawerItem(
              icon: Icons.movie,
              label: 'Películas favoritas',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const FavoritesScreen(type: ContentType.MOVIES),
                  ),
                );
              },
            ),

            const Divider(color: AppColors.border),

            // ── Historial / Config ───────────────────────────────────────
            _DrawerItem(
              icon: Icons.history,
              label: 'Historial',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const HistoryScreen(),
                  ),
                );
              },
            ),
            _DrawerItem(
              icon: Icons.settings,
              label: 'Configuración',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SettingsScreen(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Dialogs ───────────────────────────────────────────────────────────────

  Future<void> _showAddPlaylistDialog(
      BuildContext context, StorageService storage,
      {String prefillUrl = '', String prefillName = ''}) async {
    Future<String?> loadPlaylist(String url, String name) async {
      try {
        final parsed = await M3UParser.loadPlaylistFromURL(url);
        final playlist = Playlist(
          id: _uuid.v4(),
          name: name.isNotEmpty ? name : _nameFromUrl(url),
          url: url,
          channels: List<Channel>.from(parsed['TV']  ?? []),
          series:   List<Series>.from(parsed['SERIES'] ?? []),
          movies:   List<Movie>.from(parsed['MOVIES']  ?? []),
          lastUpdated: DateTime.now(),
          isActive: true,
        );
        await storage.savePlaylist(playlist);
        await storage.setActivePlaylist(playlist.id);
        return null;
      } catch (e) {
        return e.toString();
      }
    }

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AddPlaylistDialog(
        prefillUrl: prefillUrl,
        prefillName: prefillName,
        onLoad: loadPlaylist,
        onSuccess: () => _tabController.animateTo(0),
      ),
    );

    // User tapped "Abrir cámara" — open scanner then re-show dialog with data.
    if (result == '__scan__' && context.mounted) {
      final scanned =
          await Navigator.push<({String url, String name})?>(
        context,
        MaterialPageRoute(builder: (_) => const QrScannerScreen()),
      );
      if (scanned != null && context.mounted) {
        // Re-open dialog pre-filled — auto-loads immediately via _submit.
        await _showAddPlaylistDialog(
          context, storage,
          prefillUrl: scanned.url,
          prefillName: scanned.name,
        );
      }
    }
  }

  Future<void> _showEditPlaylistDialog(
      BuildContext context, StorageService storage, Playlist playlist) async {
    final controller =
        TextEditingController(text: playlist.name);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title:
            const Text('Editar nombre', style: AppTextStyles.headlineSmall),
        content: _StyledTextField(
          controller: controller,
          hint: 'Nombre de la playlist',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          _PrimaryButton(
            label: 'Guardar',
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirmed == true && controller.text.trim().isNotEmpty) {
      await storage.savePlaylist(
          playlist.copyWith(name: controller.text.trim()));
    }
    controller.dispose();
  }

  Future<void> _showDeleteConfirm(
      BuildContext context, StorageService storage, Playlist playlist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Eliminar playlist',
            style: AppTextStyles.headlineSmall),
        content: Text(
          '¿Eliminar "${playlist.name}"? Esta acción no se puede deshacer.',
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
            child: const Text('Eliminar',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await storage.deletePlaylist(playlist.id);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String _nameFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host;
      return host.isNotEmpty ? host : 'Mi Playlist';
    } catch (_) {
      return 'Mi Playlist';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _AddPlaylistDialog
// ─────────────────────────────────────────────────────────────────────────────

/// How the user wants to add a playlist.
enum _InputMode { manual, qr }

class _AddPlaylistDialog extends StatefulWidget {
  /// [onLoad] receives (url, name) and returns an error string or null on success.
  final Future<String?> Function(String url, String name) onLoad;
  final VoidCallback onSuccess;
  final String prefillUrl;
  final String prefillName;

  const _AddPlaylistDialog({
    required this.onLoad,
    required this.onSuccess,
    this.prefillUrl  = '',
    this.prefillName = '',
  });

  @override
  State<_AddPlaylistDialog> createState() => _AddPlaylistDialogState();
}

class _AddPlaylistDialogState extends State<_AddPlaylistDialog> {
  late final TextEditingController _urlCtrl;
  late final TextEditingController _nameCtrl;
  late final FocusNode _urlFocus;
  late final FocusNode _nameFocus;
  _InputMode _mode = _InputMode.manual;
  bool        _loading = false;
  String?     _error;

  @override
  void initState() {
    super.initState();
    _urlCtrl  = TextEditingController(text: widget.prefillUrl);
    _nameCtrl = TextEditingController(text: widget.prefillName);
    _urlFocus  = FocusNode();
    _nameFocus = FocusNode();

    // Invoke the TV soft keyboard whenever a field gains focus.
    _urlFocus.addListener(_showImeOnFocus(_urlFocus));
    _nameFocus.addListener(_showImeOnFocus(_nameFocus));

    // Auto-submit when the dialog is opened with a pre-filled URL from QR scan.
    if (widget.prefillUrl.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _submit();
      });
    }
  }

  /// Returns a listener that calls TextInput.show when [node] gains focus.
  VoidCallback _showImeOnFocus(FocusNode node) => () {
    if (node.hasFocus) {
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    }
  };

  @override
  void dispose() {
    _urlCtrl.dispose();
    _nameCtrl.dispose();
    _urlFocus.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  // ── Scan QR ───────────────────────────────────────────────────────────────

  Future<void> _openScanner() async {
    // Pop dialog first so the camera screen is full-screen.
    Navigator.pop(context, '__scan__');
  }

  // ── Submit ────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) {
      setState(() => _error = 'Ingresa una URL válida');
      return;
    }

    setState(() { _loading = true; _error = null; });

    final error = await widget.onLoad(url, _nameCtrl.text.trim());

    if (!mounted) return;

    if (error != null) {
      setState(() { _loading = false; _error = error; });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      widget.onSuccess();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Playlist cargada correctamente'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.card,
      title: const Text('Agregar Playlist',
          style: AppTextStyles.headlineSmall),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Mode selector ──────────────────────────────────────────────
            _ModeToggle(
              selected: _mode,
              onChanged: (m) => setState(() { _mode = m; _error = null; }),
            ),
            const SizedBox(height: AppSpacing.lg),

            // ── Manual form ────────────────────────────────────────────────
            if (_mode == _InputMode.manual) ...[
              _StyledTextField(
                controller: _urlCtrl,
                hint: 'URL M3U (http://...)',
                enabled: !_loading,
                keyboardType: TextInputType.url,
                focusNode: _urlFocus,
                autofocus: true,
              ),
              const SizedBox(height: AppSpacing.md),
              _StyledTextField(
                controller: _nameCtrl,
                hint: 'Nombre (opcional)',
                enabled: !_loading,
                focusNode: _nameFocus,
              ),
            ],

            // ── QR option ──────────────────────────────────────────────────
            if (_mode == _InputMode.qr)
              _QrModeHint(onScan: _openScanner),

            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: const TextStyle(color: AppColors.error)),
            ],
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(
          AppSpacing.base, 0, AppSpacing.base, AppSpacing.base),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('Cancelar',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
        if (_mode == _InputMode.manual)
          _PrimaryButton(
            label: 'Cargar',
            loading: _loading,
            onPressed: _loading ? null : _submit,
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ModeToggle — Manual / QR segmented switch
// ─────────────────────────────────────────────────────────────────────────────

class _ModeToggle extends StatelessWidget {
  final _InputMode selected;
  final ValueChanged<_InputMode> onChanged;

  const _ModeToggle({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _ModeButton(
          icon: Icons.keyboard,
          label: 'Escribir URL',
          active: selected == _InputMode.manual,
          onTap: () => onChanged(_InputMode.manual),
        )),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: _ModeButton(
          icon: Icons.qr_code_scanner,
          label: 'Escanear QR',
          active: selected == _InputMode.qr,
          onTap: () => onChanged(_InputMode.qr),
        )),
      ],
    );
  }
}

class _ModeButton extends StatefulWidget {
  final IconData icon;
  final String   label;
  final bool     active;
  final VoidCallback onTap;

  const _ModeButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  State<_ModeButton> createState() => _ModeButtonState();
}

class _ModeButtonState extends State<_ModeButton> {
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
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.select)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppDurations.fast,
          padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.md, horizontal: AppSpacing.sm),
          decoration: BoxDecoration(
            color: widget.active ? AppColors.accent : AppColors.surfaceVariant,
            borderRadius: AppRadius.buttonRadius,
            border: Border.all(
              color: _hasFocus
                  ? AppColors.focusBorder
                  : widget.active
                      ? AppColors.accent
                      : AppColors.border,
              width: _hasFocus ? 2 : 1,
            ),
            boxShadow: _hasFocus
                ? [BoxShadow(color: AppColors.focusGlow, blurRadius: 10, spreadRadius: 1)]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon,
                  size: 18,
                  color: widget.active ? AppColors.textInverse : AppColors.textSecondary),
              const SizedBox(width: AppSpacing.xs),
              Text(
                widget.label,
                style: AppTextStyles.labelLarge.copyWith(
                  color: widget.active ? AppColors.textInverse : AppColors.textSecondary,
                  fontWeight: widget.active ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _QrModeHint — instructions + open-camera CTA shown in QR mode
// ─────────────────────────────────────────────────────────────────────────────

class _QrModeHint extends StatelessWidget {
  final VoidCallback onScan;
  const _QrModeHint({required this.onScan});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: AppRadius.cardRadius,
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              const Icon(Icons.qr_code_2,
                  size: 56, color: AppColors.accent),
              const SizedBox(height: AppSpacing.md),
              const Text(
                'Genera el QR desde tu PC',
                style: AppTextStyles.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Abre qr_generator.html en tu navegador, '
                'ingresa la URL M3U y el nombre, '
                'luego escanea el QR con esta pantalla.',
                style: AppTextStyles.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: onScan,
            icon: const Icon(Icons.camera_alt),
            label: const Text('Abrir cámara'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.buttonRadius),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PlaylistDropdown
// ─────────────────────────────────────────────────────────────────────────────

class _PlaylistDropdown extends StatelessWidget {
  final List<Playlist> playlists;
  final Playlist? active;
  final ValueChanged<Playlist> onSelect;
  final VoidCallback onAdd;

  const _PlaylistDropdown({
    required this.playlists,
    required this.active,
    required this.onSelect,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      color: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.cardRadius),
      tooltip: 'Cambiar playlist',
      offset: const Offset(0, 48),
      itemBuilder: (_) => [
        ...playlists.map(
          (p) => PopupMenuItem<String>(
            value: p.id,
            child: Row(
              children: [
                Icon(
                  Icons.check,
                  size: 18,
                  color: active?.id == p.id
                      ? AppColors.accent
                      : Colors.transparent,
                ),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(p.name,
                      style: AppTextStyles.bodyLarge,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: '__add__',
          child: Row(
            children: [
              const Icon(Icons.add, size: 18, color: AppColors.accent),
              const SizedBox(width: AppSpacing.sm),
              Text('Nueva Playlist',
                  style: AppTextStyles.bodyLarge
                      .copyWith(color: AppColors.accent)),
            ],
          ),
        ),
      ],
      onSelected: (id) {
        if (id == '__add__') {
          onAdd();
        } else {
          final p = playlists.firstWhere((x) => x.id == id);
          onSelect(p);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.playlist_play,
                color: AppColors.textPrimary, size: 20),
            const SizedBox(width: AppSpacing.xs),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(
                active?.name ?? 'Seleccionar',
                style: AppTextStyles.bodyLarge,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.arrow_drop_down,
                color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small reusable widgets
// ─────────────────────────────────────────────────────────────────────────────

class _AppBarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _AppBarButton(
      {required this.icon, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18, color: AppColors.accent),
      label: Text(label,
          style: AppTextStyles.labelLarge.copyWith(color: AppColors.accent)),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.base, vertical: AppSpacing.sm),
      ),
    );
  }
}

class _DrawerSectionHeader extends StatelessWidget {
  final String label;
  const _DrawerSectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm, AppSpacing.md, AppSpacing.sm, AppSpacing.xs),
      child: Text(label.toUpperCase(), style: AppTextStyles.labelSmall),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _DrawerItem(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.textSecondary, size: 22),
      title: Text(label, style: AppTextStyles.bodyLarge),
      horizontalTitleGap: AppSpacing.sm,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      shape:
          RoundedRectangleBorder(borderRadius: AppRadius.thumbnailRadius),
      onTap: onTap,
    );
  }
}

class _PlaylistTile extends StatelessWidget {
  final Playlist playlist;
  final bool isActive;
  final VoidCallback onSelect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _PlaylistTile({
    required this.playlist,
    required this.isActive,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        Icons.playlist_play,
        color: isActive ? AppColors.accent : AppColors.textSecondary,
        size: 22,
      ),
      title: Text(
        playlist.name,
        style: AppTextStyles.bodyLarge.copyWith(
          color: isActive ? AppColors.accent : AppColors.textPrimary,
          fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
        ),
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${playlist.channels.length} canales · '
        '${playlist.series.length} series · '
        '${playlist.movies.length} películas',
        style: AppTextStyles.bodySmall,
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      shape:
          RoundedRectangleBorder(borderRadius: AppRadius.thumbnailRadius),
      onTap: onSelect,
      trailing: PopupMenuButton<String>(
        color: AppColors.card,
        icon: const Icon(Icons.more_vert,
            color: AppColors.textSecondary, size: 20),
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'edit',
            child: Row(children: [
              const Icon(Icons.edit, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: AppSpacing.sm),
              Text('Editar', style: AppTextStyles.bodyMedium),
            ]),
          ),
          PopupMenuItem(
            value: 'delete',
            child: Row(children: [
              const Icon(Icons.delete, size: 16, color: AppColors.error),
              const SizedBox(width: AppSpacing.sm),
              const Text('Eliminar',
                  style: TextStyle(color: AppColors.error)),
            ]),
          ),
        ],
        onSelected: (v) {
          if (v == 'edit') onEdit();
          if (v == 'delete') onDelete();
        },
      ),
    );
  }
}

class _StyledTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool enabled;
  final TextInputType? keyboardType;
  final FocusNode? focusNode;
  final bool autofocus;

  const _StyledTextField({
    required this.controller,
    required this.hint,
    this.enabled = true,
    this.keyboardType,
    this.focusNode,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      focusNode: focusNode,
      autofocus: autofocus,
      style: AppTextStyles.bodyLarge,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppTextStyles.bodyMedium,
        filled: true,
        fillColor: AppColors.surfaceVariant,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.base, vertical: AppSpacing.md),
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
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback? onPressed;

  const _PrimaryButton(
      {required this.label, this.loading = false, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.textInverse,
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        shape:
            RoundedRectangleBorder(borderRadius: AppRadius.buttonRadius),
        minimumSize: const Size(100, 44),
      ),
      child: loading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.textInverse),
            )
          : Text(label, style: AppTextStyles.labelLarge),
    );
  }
}
