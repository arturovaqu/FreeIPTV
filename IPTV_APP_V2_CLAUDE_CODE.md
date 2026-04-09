# 🎬 IPTV Player App - Guión para Claude Code v2.0
## Con separación TV / Series / Películas + Búsqueda global

---

## 📋 Estructura del Proyecto

```
iptv_player/
├── lib/
│   ├── main.dart                 # Entry point
│   ├── models/
│   │   ├── channel.dart          # Modelo de canal TV
│   │   ├── series.dart           # Modelo de serie
│   │   ├── movie.dart            # Modelo de película
│   │   ├── playlist.dart         # Modelo de playlist maestro
│   │   └── content_type.dart     # Enum: TV, SERIES, MOVIES
│   ├── services/
│   │   ├── m3u_parser.dart       # Parser M3U (TV, series, movies)
│   │   ├── storage_service.dart  # Hive para persistencia
│   │   ├── media_service.dart    # Integración media_kit
│   │   └── search_service.dart   # Búsqueda global unificada
│   ├── screens/
│   │   ├── home_screen.dart      # Pantalla principal con tabs
│   │   ├── tv_list_screen.dart   # Lista de canales TV
│   │   ├── series_list_screen.dart # Lista de series
│   │   ├── movies_list_screen.dart # Lista de películas
│   │   ├── player_screen.dart    # Pantalla reproductor
│   │   ├── search_screen.dart    # Búsqueda global
│   │   └── settings_screen.dart  # Configuración
│   ├── widgets/
│   │   ├── content_grid.dart     # Grid para series/películas
│   │   ├── tv_list.dart          # Lista específica para TV
│   │   ├── player_controls.dart  # Controles reproductor
│   │   ├── category_filter.dart  # Filtro por categoría
│   │   └── tv_navigation.dart    # Navegación Android TV
│   └── utils/
│       ├── constants.dart        # Constantes
│       └── extensions.dart       # Métodos de extensión
├── pubspec.yaml                  # Dependencias
└── android/                       # Nativo Android
```

---

## 📦 Dependencias (pubspec.yaml)

```yaml
dependencies:
  flutter:
    sdk: flutter
  # Reproductor
  media_kit: ^1.10.0
  media_kit_video: ^1.10.0
  # Almacenamiento local
  hive: ^2.2.3
  hive_flutter: ^1.1.0
  # Parser M3U y URLs
  http: ^1.1.0
  # UI y navegación
  go_router: ^12.0.0
  provider: ^6.0.0
  # Búsqueda
  fuzzywuzzy: ^3.0.0  # Para búsqueda difusa
  # Utilidades
  uuid: ^4.0.0
  intl: ^0.19.0
  cached_network_image: ^3.3.0  # Cachear imágenes

dev_dependencies:
  flutter_test:
    sdk: flutter
  hive_generator: ^2.0.0
  build_runner: ^2.4.0
```

---

## 📊 Modelos de Datos

### **Channel.dart (TV en vivo)**
```
Properties:
- id: String (UUID)
- name: String (ej: "España 1")
- logo: String? (URL logo)
- url: String (URL del stream)
- tvg_id, tvg_name: String?
- group: String (ej: "Deportes", "Entretenimiento")
- contentType: ContentType = TV
- epg: List<EPG>? (Opcional, para programación)
```

### **Series.dart**
```
Properties:
- id: String (UUID)
- name: String (ej: "Breaking Bad")
- poster: String? (URL imagen)
- description: String?
- category: String (ej: "Drama", "Suspenso")
- year: int?
- rating: double? (0-10)
- seasons: List<Season>
  - seasonNumber: int
  - episodes: List<Episode>
    - episodeNumber: int
    - title: String
    - url: String (stream)
    - duration: Duration?
    - watched: bool
- contentType: ContentType = SERIES
```

### **Movie.dart**
```
Properties:
- id: String (UUID)
- title: String
- poster: String? (URL imagen)
- description: String?
- category: String (ej: "Acción", "Comedia")
- year: int?
- duration: Duration?
- rating: double? (0-10)
- url: String (stream)
- watched: bool
- contentType: ContentType = MOVIES
```

### **Playlist.dart (Maestro)**
```
Properties:
- id: String (UUID)
- name: String (ej: "Mi Playlist IPTV")
- url: String (URL del M3U)
- channels: List<Channel>
- series: List<Series>
- movies: List<Movie>
- lastUpdated: DateTime
- isActive: bool
```

### **ContentType.dart (Enum)**
```
enum ContentType {
  TV,
  SERIES,
  MOVIES
}
```

---

## 🎯 Prompts para Claude Code (Orden de ejecución)

### **PROMPT 1: Setup inicial + Configuración**
```
Necesito crear una app IPTV en Flutter mejorada.

Comienza por:
1. Crear estructura de carpetas:
   lib/models/
   lib/services/
   lib/screens/
   lib/widgets/
   lib/utils/

2. Actualizar pubspec.yaml con dependencias exactas:
   - media_kit: ^1.10.0
   - media_kit_video: ^1.10.0
   - hive: ^2.2.3
   - hive_flutter: ^1.1.0
   - http: ^1.1.0
   - go_router: ^12.0.0
   - provider: ^6.0.0
   - fuzzywuzzy: ^3.0.0
   - uuid: ^4.0.0
   - intl: ^0.19.0
   - cached_network_image: ^3.3.0

3. Crear lib/utils/constants.dart con:
   - Colores tema oscuro (optimizado TV)
   - TextStyles para TV
   - Padding y spacing constants
   - Estilos para diferentes ContentTypes (TV, SERIES, MOVIES)

NO ejecutes flutter pub get aún.
```

### **PROMPT 2: Enum ContentType + Modelos básicos**
```
Crea los modelos en lib/models/:

1. content_type.dart:
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

2. channel.dart (@immutable):
   - id, name, logo, url, tvg_id, tvg_name, group
   - contentType = ContentType.TV
   - fromM3ULine() constructor para parsear M3U
   - copyWith() method

3. series.dart (@immutable):
   - id, name, poster, description, category, year, rating
   - seasons: List<Season>
     * Season: seasonNumber, episodes
     * Episode: episodeNumber, title, url, duration, watched
   - contentType = ContentType.SERIES
   - copyWith() method

4. movie.dart (@immutable):
   - id, title, poster, description, category, year, duration, rating, url, watched
   - contentType = ContentType.MOVIES
   - copyWith() method

5. playlist.dart (@immutable):
   - id, name, url, channels, series, movies, lastUpdated, isActive
   - copyWith() method

Todos @immutable, bien estructurados, sin imports faltantes.
```

### **PROMPT 3: Parser M3U mejorado**
```
Crea lib/services/m3u_parser.dart con clase M3UParser:

El M3U ahora soporta 3 tipos de contenido (grupos especiales):

1. TV: grupo normal (ej. "Deportes", "Películas")
2. SERIES: grupo que empieza con "#SERIES-" 
   Formato: #EXTINF:...,Serie Name (S01E01)
   URL siguiente es el stream
3. MOVIES: grupo que empieza con "#MOVIES-"
   Formato: #EXTINF:...,Movie Title
   URL siguiente es el stream

Métodos:

1. parseM3U(String content) -> Map<ContentType, List>:
   - Retorna {TV: [...], SERIES: [...], MOVIES: [...]}
   - Identifica tipo por grupo
   - Para SERIES: parsea formato (S01E01) y agrupa por serie
   - Para MOVIES: crea Movie object
   - Para TV: crea Channel object

2. parseSeriesEpisode(String line) -> (seriesName, seasonNum, episodeNum):
   - Parsea "Serie Name (S01E01)" 
   - Retorna tupla con números

3. loadPlaylistFromURL(String url) -> Playlist:
   - HTTP GET a URL
   - parseM3U() 
   - Crea Playlist object con canales, series, películas
   - Maneja errores de red

4. searchContent(List<dynamic> allContent, String query) -> List:
   - Búsqueda fuzzy por nombre
   - Funciona con Channel, Series, Movie

Asegúrate parseo robusto de diferentes formatos M3U.
```

### **PROMPT 4: Storage Service (Hive mejorado)**
```
Crea lib/services/storage_service.dart con clase StorageService:

Métodos:

1. initializeHive():
   - await Hive.initFlutter()
   - Registra adapters para Channel, Series, Movie, Playlist, Season, Episode
   - Abre boxes: 'playlists', 'favorites', 'history', 'settings'

2. savePlaylist(Playlist p):
   - Guarda en box 'playlists' con key: playlist.id

3. getPlaylists() -> List<Playlist>

4. deletePlaylist(String id)

5. getActivePlaylist() -> Playlist?

6. setActivePlaylist(String id)

7. Métodos para Favoritos (TV, Series, Movies):
   saveFavorite(String contentId, ContentType type)
   removeFavorite(String contentId, ContentType type)
   getFavorites(ContentType type) -> List<String> (ids)
   isFavorite(String contentId, ContentType type) -> bool

8. Métodos para Historial (últimas reproducidas):
   addToHistory(String contentId, ContentType type, Duration position?)
   getHistory(ContentType? type) -> List<{id, timestamp, position}>
   clearHistory(ContentType? type)

9. Métodos para preferencias:
   setTheme(String theme)
   getTheme() -> String
   setLanguage(String lang)
   getLanguage() -> String

Usa Hive boxes para separar datos: 'playlists', 'favorites', 'history', 'settings'
```

### **PROMPT 5: Media Service (media_kit)**
```
Crea lib/services/media_service.dart con clase MediaService (Singleton + ChangeNotifier):

Properties:
- _player: Player
- _currentContent: Channel | Series | Movie (dinámica)
- _currentEpisode: Episode? (si es serie)
- _isPlaying, _duration, _position, _volume

ValueNotifiers:
- isPlayingNotifier
- currentContentNotifier  
- currentEpisodeNotifier
- durationNotifier
- positionNotifier
- volumeNotifier

Métodos:

1. initialize()
2. playChannel(Channel ch)
3. playSeries(Series s, Season season, Episode ep)
4. playMovie(Movie m)
5. playNextEpisode() -> bool (retorna true si hay siguiente)
6. playPreviousEpisode() -> bool
7. play(), pause(), stop(), seek(), setVolume()
8. dispose()

Getters:
- isPlaying, currentContent, currentEpisode, duration, position, volume

Maneja cambios rápidos y errores de stream.
```

### **PROMPT 6: Search Service (Búsqueda global)**
```
Crea lib/services/search_service.dart con clase SearchService:

Métodos:

1. searchGlobal(String query, Playlist playlist) -> Map<ContentType, List>:
   - Busca en channels, series, movies
   - Usa fuzzywuzzy para búsqueda difusa
   - Retorna {TV: [...], SERIES: [...], MOVIES: [...]}

2. searchByType(String query, Playlist playlist, ContentType type) -> List:
   - Busca solo en un tipo específico

3. searchByCategory(String query, ContentType type) -> List:
   - Filtra por categoría
   - Útil para "Acción", "Drama", etc

4. getCategories(ContentType type, Playlist playlist) -> List<String>:
   - Extrae categorías únicas de un tipo

5. filterByCategory(List content, String category) -> List:
   - Filtra contenido por categoría

6. sortContent(List content, String sortBy):
   - Opciones: 'name', 'rating', 'year', 'recent'
   - Retorna lista ordenada

Importa fuzzywuzzy para búsqueda difusa.
```

### **PROMPT 7: Home Screen (Principal con Tabs)**
```
Crea lib/screens/home_screen.dart:

UI con 4 TABs:

TAB 1 - "Canales TV":
- Icono: TV
- Navega a TVListScreen()

TAB 2 - "Series":
- Icono: Play
- Navega a SeriesListScreen()

TAB 3 - "Películas":
- Icono: Film
- Navega a MoviesListScreen()

TAB 4 - "Búsqueda":
- Icono: Search
- Navega a SearchScreen()

AppBar:
- Título: "IPTV Player"
- Botón selector de playlist (dropdown con playlists guardadas)
- Si no hay playlist: mostrar botón "Agregar Playlist"

Drawer (opcional):
- Mis Playlists (nueva/editar/eliminar)
- Favoritos (acceso rápido)
- Historial
- Configuración

Dialog para agregar nueva playlist:
- TextField URL
- TextField nombre
- Botón "Cargar"
- Indicador de carga

Responsive: TV optimized (botones grandes, sin hover).
```

### **PROMPT 8: TV List Screen**
```
Crea lib/screens/tv_list_screen.dart:

Recibe: Playlist playlistActiva

UI:
1. Filtros superiores:
   - Dropdown/Chip con categorías (grupos TV)
   - SearchBar para buscar por nombre

2. ListView de Channels:
   - Thumbnail + nombre + grupo
   - Tap → PlayerScreen(channel)
   - Highlight si está reproduciéndose
   - Icono ❤️ para favoritos (tap para agregar/quitar)

3. Estado reactivo:
   - Filtra por categoría
   - Filtra por búsqueda
   - Combina ambos filtros

4. Indicadores:
   - Loading si carga
   - "Sin canales" si está vacía

5. TV optimized:
   - Focus navegable
   - Botones grandes
   - Sin hover

Usa SearchService para búsqueda.
```

### **PROMPT 9: Series List Screen**
```
Crea lib/screens/series_list_screen.dart:

Recibe: Playlist playlistActiva

UI:
1. Filtros superiores:
   - Dropdown categorías (Drama, Suspenso, etc)
   - SearchBar para buscar
   - Dropdown año (2024, 2023, etc)

2. GridView de Series:
   - Poster + nombre + año + rating
   - Tap → abre Serie detail
   - Icono ❤️ para favoritos

3. Serie Detail Bottom Sheet:
   - Poster grande
   - Nombre, descripción, año, rating
   - Listado de temporadas:
     * Cada temporada es expandible
     * Lista de episodios dentro
     * Episodio tiene botón play + marcado como visto
   - Cerrar para volver a grid

4. Reproducción:
   - Tap play en episodio → PlayerScreen(series, season, episode)
   - Continuar desde donde se quedó (si está en historial)

5. Estado:
   - Filtra por categoría, año, búsqueda
   - Combina filtros

6. TV optimized:
   - Grid con spacing generoso
   - Navegación focus-based

Usa SearchService para búsqueda.
```

### **PROMPT 10: Movies List Screen**
```
Crea lib/screens/movies_list_screen.dart:

Recibe: Playlist playlistActiva

UI:
1. Filtros superiores:
   - Dropdown categorías (Acción, Comedia, etc)
   - SearchBar
   - Dropdown año

2. GridView de Películas:
   - Poster + título + año + rating
   - Tap → abre detalle rápido
   - Icono ❤️ para favoritos

3. Película Detail Bottom Sheet:
   - Poster grande
   - Título, descripción, año, rating, duración
   - Botón play grande (amarillo/rojo)
   - Botón agregar a favoritos
   - Progreso de reproducción si fue visto

4. Reproducción:
   - Tap play → PlayerScreen(movie)
   - Continúa desde posición guardada si existe

5. Estado:
   - Filtra por categoría, año, búsqueda
   - Combina filtros

6. TV optimized:
   - Grid responsive
   - Focus-based navigation

Usa SearchService.
```

### **PROMPT 11: Search Screen (Búsqueda global)**
```
Crea lib/screens/search_screen.dart:

Recibe: Playlist playlistActiva

UI:
1. SearchBar grande en top:
   - Busca en tiempo real
   - Placeholder: "Buscar canales, series, películas..."

2. Resultados organizados por TYPE:
   Sección 1: Canales TV (si hay resultados)
   - Horizontal ListView de Channel items
   - Tap → PlayerScreen

   Sección 2: Series (si hay resultados)
   - Horizontal GridView de Series
   - Tap → abre Serie Detail

   Sección 3: Películas (si hay resultados)
   - Horizontal GridView de Movies
   - Tap → abre Movie Detail

3. Sin resultados:
   - Mensaje "No se encontró nada"
   - Sugerencias populares (top 10 de cada tipo)

4. Búsqueda reciente:
   - Lista de últimas 10 búsquedas
   - Botón para borrar
   - Tap en búsqueda reciente → repite búsqueda

5. Filtro avanzado (collapsible):
   - Filtrar por tipo: TV / SERIES / MOVIES
   - Filtrar por categoría
   - Filtrar por año
   - Ordenar por: Relevancia, Nombre, Rating, Año

6. TV optimized:
   - Botones grandes
   - Sin teclado (D-Pad navigation)

Usa SearchService.searchGlobal() y SearchService.getCategories().
```

### **PROMPT 12: Player Screen mejorado**
```
Crea lib/screens/player_screen.dart:

Parámetros:
- Channel? channel
- Series? series
- Movie? movie
- Season? season (si series)
- Episode? episode (si series)

UI:
1. Fullscreen video player (media_kit_video)

2. Overlay de controles (auto-hide 5s):
   - Titulo/Episodio actual
   - Progreso bar
   - Controles:
     * play/pause
     * volumen
     * tiempo actual / duración
     * siguiente/anterior canal o episodio
     * lista/volver

3. Indicador buffering

4. Error handling

5. Gestos:
   - Tap: show/hide controls
   - Swipe right: siguiente
   - Swipe left: anterior
   - Doble tap: fullscreen
   - Long press (series): opciones episodio

6. Series specific:
   - Si hay episodio siguiente: botón "Siguiente episodio"
   - Mostrar temporizador: "Siguiente en 10s"
   - Opción "Saltar intro"
   - Mostrar título episodio

7. TV optimized:
   - Botones grandes
   - D-Pad navigation
   - Texto visible

8. Historial:
   - Guarda posición actual cuando sale
   - Restaura posición al volver (for series/movies)

Usa MediaService para reproducción.
```

### **PROMPT 13: Player Controls mejorado**
```
Crea lib/widgets/player_controls.dart:

Parámetros:
- MediaService mediaService
- Channel | Series | Movie currentContent
- Episode? currentEpisode (si series)
- VoidCallback onBackPressed
- Function(Channel|Series|Movie) onContentChanged

Features:
1. Auto-hide después 5s
2. Progress bar
3. Controles:
   - play/pause
   - volumen (slider popup)
   - siguiente/anterior
   - tiempo / duración
   - volver atrás
4. Info del contenido:
   - Si TV: nombre canal
   - Si Serie: "Temporada X, Episodio Y - Nombre Episodio"
   - Si Movie: título película
5. Botón siguiente episodio (series solo)
6. Favoritos toggle

Animaciones fade in/out.
```

### **PROMPT 14: Widgets auxiliares**
```
Crea en lib/widgets/:

1. category_filter.dart:
   - Dropdown/Chip selector de categoría
   - Props: categorías, selected, onChanged
   - TV optimized

2. content_grid.dart:
   - GridView genérico para Series/Movies
   - Props: items, onTap, itemBuilder
   - Responsive (2 cols móvil, 3+ TV)

3. content_item_card.dart:
   - Card para Series/Movie
   - Poster + nombre + año + rating
   - Overlay con ❤️ favorito

4. channel_list_item.dart:
   - ListTile para canales
   - Logo + nombre + grupo
   - Highlight si reproduciendo

5. search_result_section.dart:
   - Sección de resultados (Canales / Series / Películas)
   - Header + horizontal scroll
   - Tap callbacks

6. tv_navigation.dart:
   - Soporte D-Pad
   - Helpers isTV(), TVOptimizedButton, TVFocusable

Todos bien comentados y estructurados.
```

### **PROMPT 15: Main.dart + Routing completo**
```
Crea lib/main.dart:

1. main() async {
     WidgetsFlutterBinding.ensureInitialized()
     await StorageService.instance.initializeHive()
     MediaService.instance.initialize()
     runApp(const MyApp())
   }

2. MyApp con MultiProvider:
   - ChangeNotifierProvider(MediaService)
   - ChangeNotifierProvider(StorageService)
   - ChangeNotifierProvider(SearchService)

3. MaterialApp.router con GoRouter:
   Routes:
   - '/': HomeScreen()
   - '/tv': TVListScreen()
   - '/series': SeriesListScreen()
   - '/movies': MoviesListScreen()
   - '/search': SearchScreen()
   - '/player': PlayerScreen(parámetros dinámicos)
   - '/favorites/:type': FavoritesScreen(type)
   - '/history': HistoryScreen()
   - '/settings': SettingsScreen()

4. ThemeData:
   - Tema oscuro optimizado para TV
   - Material 3
   - Altos contrastes

5. Locale: es
```

### **PROMPT 16: Configuración Android + Build**
```
Actualiza configuración Android:

1. android/app/build.gradle:
   - minSdkVersion: 21
   - targetSdkVersion: 34

2. android/app/src/main/AndroidManifest.xml:
   <uses-permission android:name="android.permission.INTERNET" />
   <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
   <uses-feature android:name="android.hardware.touchscreen" android:required="false" />
   <uses-feature android:name="android.software.leanback" android:required="false" />

3. pubspec.yaml:
   version: 1.0.0+1

4. Build:
   flutter build apk --release
   o
   flutter build appbundle --release

Verifica compilación sin warnings.
```

---

## 🔄 Flujo de ejecución:

1-16: Sigue orden recomendado
Después de cada prompt: "Compila y verifica que no hay errores"

---

## 📌 Características MVP v2.0:

✅ Cargar M3U con TV, Series, Películas  
✅ Separación clara TV / Series / Movies  
✅ Reproducir streams (todos los tipos)  
✅ Series: temporadas, episodios, marcados como vistos  
✅ Películas: descripción, rating, año  
✅ Búsqueda global unificada + búsqueda por tipo  
✅ Filtros por categoría, año  
✅ Favoritos  
✅ Historial de reproducción  
✅ Continuar desde donde se quedó  
✅ Soporte Android TV  
✅ Interfaz oscura optimizada para TV  

---

## 🚀 Próximos pasos (post-MVP):

- Chromecast support
- EPG (guía de programación)
- Sincronización en nube
- Subtítulos
- Sincronización entre dispositivos
- Dark/Light theme dinámico
- Notificaciones de nuevos episodios
