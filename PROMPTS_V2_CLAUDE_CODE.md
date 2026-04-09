# 🎯 PROMPTS PARA CLAUDE CODE v2.0
## Con separación TV / Series / Películas + Búsqueda global
### Cópialos y pégalos tal cual en Claude Code

---

## PROMPT 1️⃣ - SETUP INICIAL

```
Voy a crear una app IPTV en Flutter con soporte para:
- Canales TV en vivo
- Series (con temporadas y episodios)
- Películas
- Búsqueda global

Comienza con:

1. Crea estructura de carpetas:
   lib/models/
   lib/services/
   lib/screens/
   lib/widgets/
   lib/utils/

2. Actualiza pubspec.yaml con estas dependencias EXACTAS:
```yaml
dependencies:
  flutter:
    sdk: flutter
  media_kit: ^1.10.0
  media_kit_video: ^1.10.0
  hive: ^2.2.3
  hive_flutter: ^1.1.0
  http: ^1.1.0
  go_router: ^12.0.0
  provider: ^6.0.0
  fuzzywuzzy: ^3.0.0
  uuid: ^4.0.0
  intl: ^0.19.0
  cached_network_image: ^3.3.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  hive_generator: ^2.0.0
  build_runner: ^2.4.0
```

3. Crea lib/utils/constants.dart con:
   - Colores tema oscuro
   - TextStyles para TV
   - Constantes de spacing
   - Estilos para ContentType (TV, SERIES, MOVIES)

NO ejecutes flutter pub get aún.
```

---

## PROMPT 2️⃣ - ENUM CONTENTTYPE + MODELOS

```
Crea todos los modelos en lib/models/:

1. content_type.dart:
```dart
enum ContentType {
  TV,
  SERIES,
  MOVIES
}

extension ContentTypeExt on ContentType {
  String get label => name[0] + name.substring(1).toLowerCase();
  
  String get plural => switch(this) {
    ContentType.TV => 'Canales',
    ContentType.SERIES => 'Series',
    ContentType.MOVIES => 'Películas',
  };
}
```

2. channel.dart (@immutable):
   - id: String (UUID)
   - name: String
   - logo: String?
   - url: String
   - tvg_id: String?
   - tvg_name: String?
   - group: String (default 'Sin categoría')
   - contentType: ContentType = TV
   
   Constructor Channel.fromM3ULine(String extinf, String url) que parsee línea #EXTINF

3. series.dart (@immutable):
   - id: String
   - name: String
   - poster: String?
   - description: String?
   - category: String
   - year: int?
   - rating: double?
   - seasons: List<Season>
   - contentType: ContentType = SERIES
   
   Crea subclase:
   - class Season { int seasonNumber; List<Episode> episodes; }
   - class Episode { int episodeNumber; String title; String url; Duration? duration; bool watched; }

4. movie.dart (@immutable):
   - id: String
   - title: String
   - poster: String?
   - description: String?
   - category: String
   - year: int?
   - duration: Duration?
   - rating: double?
   - url: String
   - watched: bool
   - contentType: ContentType = MOVIES

5. playlist.dart (@immutable):
   - id: String
   - name: String
   - url: String
   - channels: List<Channel>
   - series: List<Series>
   - movies: List<Movie>
   - lastUpdated: DateTime
   - isActive: bool

Todos @immutable, sin imports faltantes. Incluye copyWith() en todos.
```

---

## PROMPT 3️⃣ - PARSER M3U MEJORADO

```
Crea lib/services/m3u_parser.dart con clase M3UParser:

El M3U soporta 3 tipos:
- TV: grupo normal (ej "Deportes", "Películas")
- SERIES: línea M3U contiene "S##E##" (ej "Breaking Bad (S05E14)")
- MOVIES: línea M3U normal pero en grupo movie

Métodos:

1. static Future<Map<String, List>> parseM3U(String content):
   Retorna: {
     'TV': List<Channel>,
     'SERIES': List<Series> (agrupadas por nombre serie),
     'MOVIES': List<Movie>
   }

   Lógica:
   - Lee línea #EXTINF
   - Si contiene (S##E##): es SERIES
     * Parsea nombre serie y episodio: "Breaking Bad (S01E03)" → Serie "Breaking Bad", Season 1, Episode 3
     * Agrupa episodios por serie y temporada
   - Si grupo = "Movies" o "Películas": es MOVIE
   - Sino: es TV (Channel)
   
   Extrae de #EXTINF: tvg-name, tvg-logo, tvg-id, group-title, y nombre del contenido

2. static (String, int, int) _parseSeriesEpisode(String line):
   Extrae regex: (\w[\w\s]*?)\s*\(S(\d+)E(\d+)\)
   Retorna (seriesName, seasonNum, episodeNum)

3. static Future<String> fetchM3UContent(String url):
   HTTP GET
   Maneja excepciones

4. static Future<Map<String, List>> loadPlaylistFromURL(String url):
   Llama fetchM3UContent()
   Llama parseM3U()
   Retorna mapa con TV/SERIES/MOVIES

Incluye logging para debugging.
```

---

## PROMPT 4️⃣ - STORAGE SERVICE MEJORADO

```
Crea lib/services/storage_service.dart con clase StorageService (Singleton + ChangeNotifier):

Métodos:

1. Future<void> initializeHive():
   - await Hive.initFlutter()
   - Registra adapters para: Channel, Series, Movie, Playlist, Season, Episode
   - Abre boxes: 'playlists', 'favorites', 'history', 'settings'

2. Playlist management:
   - savePlaylist(Playlist p)
   - getPlaylists() -> List<Playlist>
   - deletePlaylist(String id)
   - getActivePlaylist() -> Playlist?
   - setActivePlaylist(String id)

3. Favoritos (por ContentType):
   - saveFavorite(String contentId, ContentType type)
   - removeFavorite(String contentId, ContentType type)
   - getFavorites(ContentType type) -> List<String> (IDs)
   - isFavorite(String contentId, ContentType type) -> bool
   - notifyListeners() cuando cambien

4. Historial (últimas reproducidas):
   - addToHistory(String contentId, ContentType type, Duration? position, DateTime timestamp)
   - getHistory(ContentType? type) -> List<{id, type, timestamp, position}>
   - clearHistory(ContentType? type)
   - getLastPosition(String contentId, ContentType type) -> Duration?

5. Preferencias:
   - setTheme(String theme)
   - getTheme() -> String
   - setLanguage(String lang)
   - getLanguage() -> String

Usa Hive boxes para separar datos.
Extends ChangeNotifier para notificar cambios en favoritos e historial.
```

---

## PROMPT 5️⃣ - SEARCH SERVICE

```
Crea lib/services/search_service.dart con clase SearchService:

Métodos:

1. Map<String, List> searchGlobal(String query, Playlist playlist):
   - Busca query en channels.name, series.name, movies.title
   - Usa fuzzywuzzy para búsqueda difusa (match > 60%)
   - Retorna {
       'TV': List<Channel>,
       'SERIES': List<Series>,
       'MOVIES': List<Movie>
     }
   - Si query vacío: retorna empty

2. List<dynamic> searchByType(String query, Playlist playlist, ContentType type):
   - Busca solo en un tipo
   - Retorna list de ese tipo

3. List<String> getCategories(ContentType type, Playlist playlist):
   - Extrae categorías únicas:
     * TV: de channel.group
     * SERIES: de series.category
     * MOVIES: de movie.category
   - Retorna ordenado alfabéticamente

4. List<dynamic> filterByCategory(List content, String category):
   - Filtra content por category

5. List<dynamic> filterByYear(List content, int year):
   - Para Series y Movies

6. List<dynamic> sortContent(List content, String sortBy):
   - Opciones: 'name', 'rating', 'year', 'recent'
   - Retorna ordenado

7. List<String> getRecentSearches() -> List<String>:
   - Lee últimas 10 búsquedas de Hive

8. void addRecentSearch(String query):
   - Agrega búsqueda a historial
   - Mantiene máximo 10

9. void clearRecentSearches():
   - Borra historial búsquedas

Importa fuzzywuzzy.
Almacena búsquedas recientes en Hive.
```

---

## PROMPT 6️⃣ - MEDIA SERVICE MEJORADO

```
Crea lib/services/media_service.dart (Singleton + ChangeNotifier):

Propiedades privadas:
- _player: Player
- _currentContentType: ContentType?
- _currentChannel: Channel?
- _currentSeries: Series?
- _currentSeason: Season?
- _currentEpisode: Episode?
- _currentMovie: Movie?
- _isPlaying: bool
- _duration: Duration
- _position: Duration
- _volume: double

ValueNotifiers para escuchar cambios:
- isPlayingNotifier
- currentContentTypeNotifier
- currentChannelNotifier
- currentSeriesNotifier
- currentEpisodeNotifier
- currentMovieNotifier
- durationNotifier
- positionNotifier
- volumeNotifier

Métodos principales:

1. Future<void> initialize():
   - MediaKit.ensureInitialized()
   - setupPlayerListeners()

2. Future<void> playChannel(Channel ch):
   - _currentContentType = TV
   - _currentChannel = ch
   - await _player.open(Media(ch.url))
   - notifyListeners()

3. Future<void> playSeries(Series s, Season season, Episode ep):
   - _currentContentType = SERIES
   - _currentSeries = s
   - _currentSeason = season
   - _currentEpisode = ep
   - await _player.open(Media(ep.url))
   - Marca episodio como watched (en StorageService)
   - notifyListeners()

4. Future<void> playMovie(Movie m):
   - _currentContentType = MOVIES
   - _currentMovie = m
   - await _player.open(Media(m.url))
   - Marca como watched
   - notifyListeners()

5. Future<bool> playNextEpisode():
   - Si hay siguiente episodio en season: playSeries(serie, season, nextEpisode)
   - Sino si hay siguiente season: playSeries(serie, nextSeason, ep1)
   - Retorna true si pudo, false sino

6. Future<bool> playPreviousEpisode():
   - Similar pero hacia atrás

7. Future<void> playNextChannel(List<Channel> channels):
   - Si _currentChannel existe, busca siguiente en lista
   - playSeries ese

8. Future<void> playPreviousChannel(List<Channel> channels)

9. play(), pause(), stop(), seek(Duration), setVolume(double)

10. void dispose():
    - _player.dispose()
    - super.dispose()

Getters:
- isPlaying, currentContentType, currentChannel, currentSeries, currentEpisode, currentMovie, etc.

Maneja errores de stream.
```

---

## PROMPT 7️⃣ - HOME SCREEN CON TABS

```
Crea lib/screens/home_screen.dart con StatefulWidget:
Layout:

1. AppBar:
   - Título "IPTV Player"
   - Botón dropdown para seleccionar playlist activa
   - Si no hay playlist: botón "Agregar Playlist"

2. DefaultTabController + TabBar + TabBarView con 4 tabs:

   TAB 0 - "Canales" (icon: Tv):
   - Navega a TVListScreen(playlistActiva)

   TAB 1 - "Series" (icon: PlayCircle):
   - Navega a SeriesListScreen(playlistActiva)

   TAB 2 - "Películas" (icon: Film):
   - Navega a MoviesListScreen(playlistActiva)

   TAB 3 - "Buscar" (icon: Search):
   - Navega a SearchScreen(playlistActiva)

3. Drawer opcional (menu lateral):
   - Mi Playlist
     * Nueva playlist (dialog)
     * Editar (cambiar nombre)
     * Eliminar (confirm)
   - Favoritos
     * Canales favoritos
     * Series favoritas
     * Películas favoritas
   - Historial
   - Configuración

4. Dialog para agregar playlist:
   - TextField URL M3U
   - TextField nombre (optional)
   - Botón "Cargar"
   - CircularProgressIndicator mientras carga
   - Si éxito: snackbar verde, ir a tab Canales
   - Si error: snackbar rojo

5. Estado:
   - Consumer<StorageService> para listar playlists
   - Usa M3UParser.loadPlaylistFromURL() para cargar
   - Crea Playlist y guarda con StorageService.savePlaylist()
   - setActivePlaylist() automáticamente

6. TV optimized:
   - Botones grandes
   - Padding generoso
   - Sin hover, D-Pad navigation
```

---

## PROMPT 8️⃣ - TV LIST SCREEN

```
Crea lib/screens/tv_list_screen.dart:

Constructor parámetro: Playlist playlistActiva

Layout:

1. SearchBar superior para buscar canales

2. Filtro por categoría:
   - Dropdown/Chips con grupos únicos (extraídos de channels)
   - Opción "Todos" default
   - Filtra lista al seleccionar

3. ListView de Channels:
   - Cada item: pequeño logo/ícono + nombre + grupo + ❤️ favorito
   - Tap → PlayerScreen(channel)
   - Highlight si está reproduciéndose
   - Tap ❤️ → agregar/quitar de favoritos

4. Indicadores:
   - Loading si carga
   - "Sin canales" si vacío o sin resultados

5. Estado:
   - Mantén channels filtrados (combina búsqueda + categoría)
   - Escucha MediaService para highlight del actual
   - Escucha StorageService para cambios en favoritos

6. TV optimized:
   - Focus navegable
   - Botones grandes
   - ListTile con padding generoso

Usa SearchService.searchByType() para búsqueda.
```

---

## PROMPT 9️⃣ - SERIES LIST SCREEN

```
Crea lib/screens/series_list_screen.dart:

Constructor: Playlist playlistActiva

Layout:

1. Filtros superiores (fila):
   - Dropdown categoría (Drama, Suspenso, etc)
   - SearchBar
   - Dropdown año (2024, 2023, etc)

2. GridView de Series (responsive: 2 cols móvil, 3 TV):
   - Cada card: poster + nombre + año + rating
   - Tap → abre Serie Detail Bottom Sheet
   - ❤️ en esquina para favoritos

3. Serie Detail Bottom Sheet:
   - DraggableScrollableSheet (draggable desde bottom)
   - Header: poster grande + close button
   - Nombre, descripción, year, rating, categoría
   - Listado de temporadas:
     * ExpansionTile por cada season
     * Lista de episodios dentro
     * Cada episodio: número + título + duración + ✓ watched
     * Botón play grande en episodio
   - Botón favoritos
   - Scroll si contenido es largo

4. Reproducción:
   - Tap play en episodio → PlayerScreen(series, season, episode)
   - MediaService.playSeries()
   - Si está en historial: continúa desde posición guardada

5. Estado:
   - Filtra por categoría + año + búsqueda (combina)
   - Marks episodios como watched automáticamente al reproducir
   - Escucha StorageService para cambios en favoritos

6. TV optimized:
   - Grid con spacing generoso
   - Bottom sheet adaptado para TV

Usa SearchService para búsqueda.
```

---

## PROMPT 1️⃣0️⃣ - MOVIES LIST SCREEN

```
Crea lib/screens/movies_list_screen.dart:

Constructor: Playlist playlistActiva

Layout:

1. Filtros (fila):
   - Dropdown categoría
   - SearchBar
   - Dropdown año

2. GridView de Películas (2 cols móvil, 3+ TV):
   - Poster + título + año + rating
   - Tap → Movie Detail Bottom Sheet
   - ❤️ favoritos en esquina

3. Movie Detail Bottom Sheet:
   - Poster grande
   - Título, descripción, year, rating, duración, categoría
   - Barra de progreso si fue visto (muestra tiempo actual / total)
   - Botón play grande (rojo/amarillo)
   - Botón favoritos
   - Botón "Continuar" si fue parcialmente visto (con opción "Desde el inicio")

4. Reproducción:
   - Tap play → PlayerScreen(movie)
   - MediaService.playMovie()
   - Restaura posición si existe en historial

5. Estado:
   - Filtra por categoría + año + búsqueda
   - Marks como watched automáticamente
   - Escucha cambios en favoritos

6. TV optimized:
   - Grid responsive
   - Bottom sheet adaptable

Usa SearchService.
```

---

## PROMPT 1️⃣1️⃣ - SEARCH SCREEN GLOBAL

```
Crea lib/screens/search_screen.dart:

Constructor: Playlist playlistActiva

Layout:

1. SearchBar grande en top:
   - Placeholder: "Buscar canales, series, películas..."
   - onChanged → busca en tiempo real
   - onSubmitted → limpia query y resetea

2. Si no hay búsqueda:
   - Mostrar "Búsquedas recientes"
   - Lista de últimas 10 búsquedas
   - Tap en búsqueda reciente → repite búsqueda
   - Botón "Borrar historial"

3. Si hay búsqueda - Resultados por tipo:
   
   Sección "Canales" (si hay):
   - Horizontal ListView de Channels
   - Cada item: logo + nombre + grupo
   - Tap → PlayerScreen

   Sección "Series" (si hay):
   - Horizontal GridView de Series
   - Cada item: poster + nombre + año
   - Tap → abre Serie Detail

   Sección "Películas" (si hay):
   - Horizontal GridView de Movies
   - Cada item: poster + título + año
   - Tap → abre Movie Detail

4. Sin resultados:
   - Mensaje "No se encontró nada para '[query]'"
   - Sugerencias: "Top series", "Top películas" (populares)

5. Filtro avanzado (collapsible ExpansionTile):
   - Filtrar por tipo: Todos / TV / Series / Películas
   - Filtrar por categoría (dropdown dinámico)
   - Filtrar por año (range slider o dropdown)
   - Ordenar por: Relevancia / Nombre / Rating / Año

6. TV optimized:
   - Sin teclado (D-Pad navigation)
   - Botones grandes
   - Tap en search button abre teclado virtual

Usa SearchService.searchGlobal(), getCategories(), getRecentSearches().
```



Verifica flutter analyze



---

## PROMPT 1️⃣2️⃣ - PLAYER SCREEN MEJORADO

```
Crea lib/screens/player_screen.dart:

Constructor parámetros dinámicos:
- Channel? channel
- Series? series
- Season? season
- Episode? episode
- Movie? movie

(Solo uno de los anteriores no-null)

Layout:

1. Fullscreen video player (media_kit_video):
   - Llena pantalla completa
   - GestureDetector para tap/swipe

2. Overlay de controles (auto-hide 5s):
   Top part:
   - Texto: nombre canal / "S##E## - Nombre Episodio" / "Película Título"
   - Botón ícono info (muestra detalles)

   Middle part:
   - VideoProgressIndicator (progreso)

   Bottom part:
   - Fila de controles:
     * IconButton play/pause
     * IconButton volumen (tap abre slider popup)
     * Texto tiempo actual / duración
     * IconButton siguiente canal/episodio
     * IconButton anterior canal/episodio
     * IconButton lista de canales (volver)

3. Indicador de buffering (circular) mientras carga

4. Error handling:
   - Si stream no disponible: dialog rojo "Error reproduciendo"
   - Botón "Reintentar"

5. Gestos:
   - Tap → show/hide controles (o toggle play)
   - Swipe right → siguiente
   - Swipe left → anterior
   - Doble tap → fullscreen toggle
   - Long press (series) → opciones (saltar intro, próximo episodio)

6. Series specific:
   - Si hay episodio siguiente: botón "Siguiente episodio" con temporizador
   - Opción "Saltar intro" (adelanta 30s)
   - Mostrar: "Temporada X, Episodio Y - Título Episodio"
   - Auto-play siguiente episodio si termina (opcional)

7. TV optimized:
   - Botones más grandes
   - D-Pad navigation (left/right siguientes, up/down volumen)
   - Sin teclado
   - Texto visible desde lejos

8. Historial:
   - Al salir: guarda posición actual + timestamp con StorageService.addToHistory()
   - Al entrar: restaura posición con StorageService.getLastPosition()
   - Restaura posición automáticamente después 2 segundos

9. Favoritos:
   - Botón ❤️ para agregar/quitar de favoritos

Usa MediaService para:
- playChannel(), playSeries(), playMovie()
- playNextEpisode(), playNextChannel()
- playPreviousEpisode(), playPreviousChannel()
- pause(), play(), seek(), setVolume()

Maneja excepciones y errores de stream.
```

---

## PROMPT 1️⃣3️⃣ - WIDGETS AUXILIARES

```
Crea en lib/widgets/:

1. category_filter.dart:
   Widget CategoryFilter(
     categories: List<String>,
     selected: String?,
     onChanged: (String) {}
   )
   - Dropdown o Chips selector
   - TV optimized

2. content_grid.dart:
   Widget ContentGrid<T>(
     items: List<T>,
     onTap: (T) {},
     itemBuilder: (T) -> Widget,
     crossAxisCount: int = 3,
   )
   - GridView genérico para Series/Movies
   - Responsive

3. content_item_card.dart:
   Widget ContentItemCard(
     poster: String?,
     title: String,
     year: int?,
     rating: double?,
     isFavorite: bool,
     onTap: () {},
     onFavoriteTap: () {},
   )
   - Card con poster + overlay
   - ❤️ favorito en esquina

4. channel_list_item.dart:
   Widget ChannelListItem(
     channel: Channel,
     isActive: bool,
     isFavorite: bool,
     onTap: () {},
     onFavoriteTap: () {},
   )
   - ListTile para canales
   - Logo + nombre + grupo

5. search_result_section.dart:
   Widget SearchResultSection(
     title: String,
     items: List,
     type: ContentType,
     onItemTap: (item) {},
     itemBuilder: (item) -> Widget,
   )
   - Sección de resultados (Canales/Series/Películas)
   - Header + horizontal scroll

6. tv_navigation.dart:
   - helper: bool isTV(BuildContext)
   - widget: TVOptimizedButton(label, onPressed, icon)
   - widget: TVFocusable(child, onLeft, onRight, onUp, onDown, onEnter)
   - constant: TVTheme (ThemeData customizado)

7. favorite_button.dart:
   Widget FavoriteButton(
     isFavorite: bool,
     onPressed: () {},
     contentType: ContentType,
   )
   - ❤️ button bonito
   - Animación al presionar

Todos bien comentados y con tipos genéricos donde aplique.
```

---

## PROMPT 1️⃣4️⃣ - MAIN.DART + ROUTING

```
Crea lib/main.dart:

1. void main() async {
     WidgetsFlutterBinding.ensureInitialized()
     await StorageService.instance.initializeHive()
     await MediaService.instance.initialize()
     runApp(const MyApp())
   }

2. MyApp (StatelessWidget):
   - MultiProvider([
       ChangeNotifierProvider(create: (_) => StorageService.instance),
       ChangeNotifierProvider(create: (_) => MediaService.instance),
       ChangeNotifierProvider(create: (_) => SearchService()),
     ])
   - MaterialApp.router

3. Configurar GoRouter:
   Routes:
   - '/': HomeScreen()
   - '/tv': TVListScreen(playlist)
   - '/series': SeriesListScreen(playlist)
   - '/movies': MoviesListScreen(playlist)
   - '/search': SearchScreen(playlist)
   - '/player':
     * Parámetros query: type (TV|SERIES|MOVIES), channelId?, seriesId?, seasonNum?, episodeNum?, movieId?
     * Builder busca objetos y abre PlayerScreen con los parámetros correspondientes
   - '/favorites/:type': FavoritesScreen(type)
   - '/history': HistoryScreen()

4. ThemeData:
   - brightness: dark
   - useMaterial3: true
   - colorScheme: ColorsScheme.fromSeed(
       seedColor: Colors.blue,
       brightness: Brightness.dark,
     )
   - textTheme: buildTextTheme()
   - Component themes: botones grandes, inputs visibles

5. supportedLocales: [Locale('es')]

6. Error handling:
   - Si initializeHive() falla: mostrar error
   - Si MediaService.initialize() falla: mostrar error

Estructura completa, compilable, sin imports faltantes.
```


responsive



---

## PROMPT 1️⃣5️⃣ - PANTALLAS ADICIONALES (FAVORITOS + HISTORIAL)

```
Crea:

1. lib/screens/favorites_screen.dart:
   Constructor parámetro: ContentType type
   
   Layout:
   - AppBar con nombre del tipo (Canales / Series / Películas)
   - Si tipo = TV: ListView de canales favoritos
   - Si tipo = SERIES: GridView de series favoritas
   - Si tipo = MOVIES: GridView de películas favoritas
   - Tap → reproduce/abre detalle
   - Swipe para quitar de favoritos
   - Mensaje "Sin favoritos" si vacío

2. lib/screens/history_screen.dart:
   Layout:
   - Tabs: Todos / Canales / Series / Películas
   - ListView de historial:
     * Thumbnail/logo + nombre + "Visto hace X minutos"
     * Si series/movies: muestra posición ("Minuto 24 de 120")
   - Tap → continúa desde donde se quedó
   - Botón eliminar item (swipe)
   - Botón "Limpiar historial"

Ambas bien integradas con StorageService.
```

---

## PROMPT 1️⃣6️⃣ - CONFIGURACIÓN ANDROID + BUILD RELEASE

```
Configura para Google Play:

1. android/app/build.gradle:
   - minSdkVersion: 21
   - targetSdkVersion: 34
   - compileSdkVersion: 34
   - versionCode: 1
   - versionName: "1.0.0"

2. android/app/src/main/AndroidManifest.xml:
   Permisos:
   <uses-permission android:name="android.permission.INTERNET" />
   <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
   <uses-permission android:name="android.permission.CHANGE_NETWORK_STATE" />

   Features (Android TV):
   <uses-feature android:name="android.hardware.touchscreen" android:required="false" />
   <uses-feature android:name="android.software.leanback" android:required="false" />

3. pubspec.yaml:
   version: 1.0.0+1

4. Build:
   flutter build apk --release
   o mejor:
   flutter build appbundle --release

5. Build output:
   - APK: build/app/outputs/flutter-apk/app-release.apk
   - Bundle: build/app/outputs/bundle/release/app-release.aab

6. Google Play:
   - Crear app en Play Console
   - Subir App Bundle
   - Metadata: descripción, screenshots, privacidad, categoría
   - Publicar en beta → producción

7. Testing:
   flutter analyze
   flutter test

Verifica compilación sin warnings/errors.
```

---

## 📌 FLUJO RECOMENDADO:

**Semana 1:**
- Prompts 1-6: Setup, modelos, parsers, services

**Semana 2:**
- Prompts 7-12: Screens principales + player

**Semana 3:**
- Prompts 13-15: Widgets, routing, pantallas adicionales

**Semana 4:**
- Prompt 16: Build + Google Play
- Testing y pulido

---

## ✅ CHECKLIST:

Antes de publicar:
- [ ] Home con 4 tabs funciona
- [ ] TV: carga, busca, reproduce canales
- [ ] Series: muestra temporadas, episodios, marca vistos
- [ ] Películas: muestra detalles, reproduce, marca vistos
- [ ] Búsqueda global funciona (combina resultados)
- [ ] Favoritos funciona en los 3 tipos
- [ ] Historial guarda posición y tiempo
- [ ] Cambio rápido entre contenidos sin lag
- [ ] Parsing M3U correcto (TV, Series, Movies)
- [ ] Android TV navigation (D-Pad)
- [ ] Probar con URL M3U real
- [ ] flutter analyze sin warnings
- [ ] APK/Bundle compila sin errores
- [ ] Probado en dispositivo físico
- [ ] Metadata Google Play completa

¡Éxito! Ahora tienes todo para que Claude Code genere tu app IPTV completa.
```
