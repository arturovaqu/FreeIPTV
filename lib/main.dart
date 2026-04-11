import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:media_kit/media_kit.dart';

import 'models/models.dart';
import 'screens/favorites_screen.dart';
import 'screens/history_screen.dart';
import 'screens/home_screen.dart';
import 'screens/movies_list_screen.dart';
import 'screens/player_screen.dart';
import 'screens/search_screen.dart';
import 'screens/series_list_screen.dart';
import 'screens/tv_list_screen.dart';
import 'services/media_service.dart';
import 'services/progress_service.dart';
import 'services/search_service.dart';
import 'services/storage_service.dart';
import 'utils/constants.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Entry point
// ─────────────────────────────────────────────────────────────────────────────

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // Track any boot-time error so the UI can show it
  String? bootError;

  try {
    await StorageService.instance.initializeHive();
    dev.log('[main] Hive ready', name: 'main');
  } catch (e) {
    bootError = 'Error al inicializar almacenamiento:\n$e';
    dev.log('[main] Hive init failed: $e', name: 'main');
  }

  if (bootError == null) {
    try {
      await ProgressService.instance.initialize();
      dev.log('[main] ProgressService ready', name: 'main');
    } catch (e) {
      dev.log('[main] ProgressService init warning: $e', name: 'main');
    }
  }

  if (bootError == null) {
    try {
      await SearchService.instance.init();
      dev.log('[main] SearchService ready', name: 'main');
    } catch (e) {
      // Non-fatal — search still works without Hive
      dev.log('[main] SearchService init warning: $e', name: 'main');
    }
  }

  if (bootError == null) {
    try {
      await MediaService.instance.initialize();
      dev.log('[main] MediaService ready', name: 'main');
    } catch (e) {
      bootError = 'Error al inicializar reproductor:\n$e';
      dev.log('[main] MediaService init failed: $e', name: 'main');
    }
  }

  runApp(MyApp(bootError: bootError));
}

// ─────────────────────────────────────────────────────────────────────────────
// Router
// ─────────────────────────────────────────────────────────────────────────────

/// Builds a [PlayerScreen] from GoRouter query parameters.
///
/// Expected query params:
///   type         — 'TV' | 'SERIES' | 'MOVIES'
///   channelId    — (TV) channel.id
///   seriesId     — (SERIES) series.id
///   seasonNum    — (SERIES) season number as int string
///   episodeNum   — (SERIES) episode number as int string
///   movieId      — (MOVIES) movie.id
Widget _buildPlayerScreen(GoRouterState state) {
  final params = state.uri.queryParameters;
  final type   = params['type'] ?? 'TV';
  final storage = StorageService.instance;
  final playlist = storage.getActivePlaylist();

  if (playlist == null) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Text('Sin playlist activa',
            style: TextStyle(color: Colors.white70)),
      ),
    );
  }

  if (type == 'TV') {
    final id      = params['channelId'];
    final channel = playlist.channels.cast<Channel?>().firstWhere(
          (c) => c?.id == id,
          orElse: () => null,
        );
    if (channel == null) return _notFound('Canal no encontrado');
    return PlayerScreen.channel(
        channel: channel, channels: playlist.channels);
  }

  if (type == 'SERIES') {
    final seriesId  = params['seriesId'];
    final seasonNum = int.tryParse(params['seasonNum'] ?? '');
    final episodeNum = int.tryParse(params['episodeNum'] ?? '');

    final series = playlist.series.cast<Series?>().firstWhere(
          (s) => s?.id == seriesId,
          orElse: () => null,
        );
    if (series == null || seasonNum == null || episodeNum == null) {
      return _notFound('Episodio no encontrado');
    }

    final season = series.seasons.cast<Season?>().firstWhere(
          (s) => s?.seasonNumber == seasonNum,
          orElse: () => null,
        );
    final episode = season?.episodes.cast<Episode?>().firstWhere(
          (e) => e?.episodeNumber == episodeNum,
          orElse: () => null,
        );

    if (season == null || episode == null) {
      return _notFound('Temporada/episodio no encontrado');
    }
    return PlayerScreen.series(
        series: series, season: season, episode: episode);
  }

  // MOVIES
  final id    = params['movieId'];
  final movie = playlist.movies.cast<Movie?>().firstWhere(
        (m) => m?.id == id,
        orElse: () => null,
      );
  if (movie == null) return _notFound('Película no encontrada');
  return PlayerScreen.movie(movie: movie);
}

Widget _notFound(String msg) => Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Text(msg,
            style: const TextStyle(color: Colors.white70, fontSize: 18)),
      ),
    );

// ── GoRouter instance ─────────────────────────────────────────────────────────

final GoRouter _router = GoRouter(
  initialLocation: '/',
  debugLogDiagnostics: true,
  routes: [
    // Home (tabs: Canales / Series / Películas / Buscar)
    GoRoute(
      path: '/',
      name: 'home',
      builder: (_, __) => const HomeScreen(),
    ),

    // Standalone list screens (deep-link friendly)
    GoRoute(
      path: '/tv',
      name: 'tv',
      builder: (context, __) => TVListScreen(
          playlist: StorageService.instance.getActivePlaylist()),
    ),
    GoRoute(
      path: '/series',
      name: 'series',
      builder: (context, __) => SeriesListScreen(
          playlist: StorageService.instance.getActivePlaylist()),
    ),
    GoRoute(
      path: '/movies',
      name: 'movies',
      builder: (context, __) => MoviesListScreen(
          playlist: StorageService.instance.getActivePlaylist()),
    ),
    GoRoute(
      path: '/search',
      name: 'search',
      builder: (context, __) => SearchScreen(
          playlist: StorageService.instance.getActivePlaylist()),
    ),

    // Player — query params drive content selection
    // e.g. /player?type=TV&channelId=abc123
    //      /player?type=SERIES&seriesId=s1&seasonNum=1&episodeNum=3
    //      /player?type=MOVIES&movieId=m99
    GoRoute(
      path: '/player',
      name: 'player',
      builder: (_, state) => _buildPlayerScreen(state),
    ),

    // Favorites per content type
    GoRoute(
      path: '/favorites/:type',
      name: 'favorites',
      builder: (_, state) {
        final raw  = state.pathParameters['type'] ?? 'TV';
        final type = ContentType.values.byName(raw);
        return FavoritesScreen(type: type);
      },
    ),

    // History
    GoRoute(
      path: '/history',
      name: 'history',
      builder: (_, __) => const HistoryScreen(),
    ),
  ],

  // Global error page
  errorBuilder: (_, state) => Scaffold(
    backgroundColor: AppColors.background,
    body: Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline,
            color: AppColors.error, size: 56),
        const SizedBox(height: AppSpacing.md),
        Text('Ruta no encontrada: ${state.uri}',
            style: AppTextStyles.bodyMedium),
      ]),
    ),
  ),
);

// ─────────────────────────────────────────────────────────────────────────────
// MyApp
// ─────────────────────────────────────────────────────────────────────────────

class MyApp extends StatelessWidget {
  /// Non-null when a fatal boot error occurred (Hive / MediaKit failed).
  final String? bootError;

  const MyApp({super.key, this.bootError});

  @override
  Widget build(BuildContext context) {
    // If boot failed, show a standalone error screen without routing
    if (bootError != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: _BootErrorScreen(message: bootError!),
      );
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<StorageService>.value(
            value: StorageService.instance),
        ChangeNotifierProvider<MediaService>.value(
            value: MediaService.instance),
        ChangeNotifierProvider<ProgressService>.value(
            value: ProgressService.instance),
        // SearchService is a plain singleton (no ChangeNotifier) —
        // expose via Provider so widgets can call SearchService.instance
        // directly; or inject via context if preferred.
        Provider<SearchService>.value(value: SearchService.instance),
      ],
      child: MaterialApp.router(
        title: 'IPTV Player',
        debugShowCheckedModeBanner: false,
        routerConfig: _router,

        // ── Theme ────────────────────────────────────────────────────
        theme: _buildTheme(),

        // ── Localisation ─────────────────────────────────────────────
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('es'), Locale('en')],
        locale: const Locale('es'),
      ),
    );
  }

  // ── Theme builder ─────────────────────────────────────────────────────────

  static ThemeData _buildTheme() {
    final base = ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: Brightness.dark,
    ).copyWith(
      surface:   AppColors.surface,
      primary:   AppColors.accent,
      error:     AppColors.error,
      onSurface: AppColors.textPrimary,
      onPrimary: AppColors.textInverse,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: base,
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: 'Roboto',

      // ── Text ───────────────────────────────────────────────────────
      textTheme: const TextTheme(
        displayLarge:   AppTextStyles.displayLarge,
        displayMedium:  AppTextStyles.displayMedium,
        headlineLarge:  AppTextStyles.headlineLarge,
        headlineMedium: AppTextStyles.headlineMedium,
        headlineSmall:  AppTextStyles.headlineSmall,
        bodyLarge:      AppTextStyles.bodyLarge,
        bodyMedium:     AppTextStyles.bodyMedium,
        bodySmall:      AppTextStyles.bodySmall,
        labelLarge:     AppTextStyles.labelLarge,
        labelMedium:    AppTextStyles.labelMedium,
        labelSmall:     AppTextStyles.labelSmall,
      ),

      // ── AppBar ─────────────────────────────────────────────────────
      appBarTheme: const AppBarTheme(
        backgroundColor:  AppColors.surface,
        foregroundColor:  AppColors.textPrimary,
        elevation:        0,
        centerTitle:      false,
        titleTextStyle:   AppTextStyles.headlineMedium,
        iconTheme:        IconThemeData(color: AppColors.textPrimary),
      ),

      // ── Buttons ────────────────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.textInverse,
          minimumSize:     const Size(80, 48),
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          shape: const RoundedRectangleBorder(
              borderRadius: AppRadius.buttonRadius),
          textStyle: AppTextStyles.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          minimumSize:     const Size(80, 48),
          side: const BorderSide(color: AppColors.border),
          shape: const RoundedRectangleBorder(
              borderRadius: AppRadius.buttonRadius),
          textStyle: AppTextStyles.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accent,
          textStyle: AppTextStyles.labelLarge,
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.base, vertical: AppSpacing.sm),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          minimumSize:     const Size(44, 44),
        ),
      ),

      // ── Input / TextField ──────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled:      true,
        fillColor:   AppColors.surfaceVariant,
        hintStyle:   AppTextStyles.bodyMedium,
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

      // ── ListTile ───────────────────────────────────────────────────
      listTileTheme: const ListTileThemeData(
        tileColor:         Colors.transparent,
        titleTextStyle:    AppTextStyles.bodyLarge,
        subtitleTextStyle: AppTextStyles.bodyMedium,
        iconColor:         AppColors.textSecondary,
        minVerticalPadding: AppSpacing.sm,
      ),

      // ── Dialog ────────────────────────────────────────────────────
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.card,
        titleTextStyle:  AppTextStyles.headlineSmall,
        contentTextStyle: AppTextStyles.bodyMedium,
        shape: RoundedRectangleBorder(
            borderRadius: AppRadius.cardRadius),
      ),

      // ── BottomSheet ────────────────────────────────────────────────
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(20)),
        ),
        showDragHandle: false,
      ),

      // ── Drawer ────────────────────────────────────────────────────
      drawerTheme: const DrawerThemeData(
        backgroundColor: AppColors.surface,
      ),

      // ── Tab ───────────────────────────────────────────────────────
      tabBarTheme: const TabBarThemeData(
        indicatorColor:          AppColors.accent,
        labelColor:              AppColors.accent,
        unselectedLabelColor:    AppColors.textSecondary,
        labelStyle:              AppTextStyles.labelLarge,
        unselectedLabelStyle:    AppTextStyles.labelMedium,
        indicatorSize:           TabBarIndicatorSize.label,
      ),

      // ── Chips ─────────────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor:       AppColors.surfaceVariant,
        selectedColor:         AppColors.accent,
        labelStyle:            AppTextStyles.labelMedium,
        side:                  const BorderSide(color: AppColors.border),
        shape:                 const StadiumBorder(),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      ),

      // ── Divider ───────────────────────────────────────────────────
      dividerTheme: const DividerThemeData(
        color:     AppColors.divider,
        thickness: 1,
        space:     1,
      ),

      // ── Popup menu ────────────────────────────────────────────────
      popupMenuTheme: const PopupMenuThemeData(
        color: AppColors.card,
        textStyle: AppTextStyles.bodyLarge,
        shape: RoundedRectangleBorder(
            borderRadius: AppRadius.cardRadius),
      ),

      // ── Snackbar ──────────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.card,
        contentTextStyle: AppTextStyles.bodyLarge,
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(
            borderRadius: AppRadius.thumbnailRadius),
      ),

      // ── Slider ────────────────────────────────────────────────────
      sliderTheme: const SliderThemeData(
        activeTrackColor:   AppColors.accent,
        inactiveTrackColor: AppColors.border,
        thumbColor:         AppColors.accent,
        overlayColor:       AppColors.focusGlow,
        trackHeight:        3,
      ),

      // ── Expansion tile ─────────────────────────────────────────────
      expansionTileTheme: const ExpansionTileThemeData(
        backgroundColor:         AppColors.card,
        collapsedBackgroundColor: Colors.transparent,
        iconColor:               AppColors.textSecondary,
        collapsedIconColor:      AppColors.textDisabled,
        textColor:               AppColors.textPrimary,
        collapsedTextColor:      AppColors.textPrimary,
      ),

      // ── Progress indicator ─────────────────────────────────────────
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color:            AppColors.accent,
        linearTrackColor: AppColors.border,
      ),

      focusColor: AppColors.focusGlow,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _BootErrorScreen
// ─────────────────────────────────────────────────────────────────────────────

/// Shown when a fatal error occurs during app initialisation.
class _BootErrorScreen extends StatelessWidget {
  final String message;
  const _BootErrorScreen({required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline,
                  color: AppColors.error, size: 72),
              const SizedBox(height: AppSpacing.lg),
              const Text(
                'Error al iniciar la aplicación',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.base),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: AppRadius.cardRadius,
                  border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.4)),
                ),
                child: Text(
                  message,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              ElevatedButton.icon(
                onPressed: () {
                  // Hot restart not possible from code; guide user
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Reiniciar la app manualmente'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                  minimumSize:
                      const Size(double.infinity, 52),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
