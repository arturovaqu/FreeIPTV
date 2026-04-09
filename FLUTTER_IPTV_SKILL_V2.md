# Flutter IPTV Development Skill v2.0

## Descripción
Skill especializada para desarrollo rápido de app IPTV en Flutter con soporte para:
- Canales TV en vivo
- Series (temporadas, episodios)
- Películas
- Búsqueda global unificada
- Android TV

---

## Comandos Flutter

```bash
# Setup
flutter create iptv_player
cd iptv_player
flutter pub get

# Compilar
flutter run                          # emulador
flutter build apk --release          # APK release
flutter build appbundle --release    # App Bundle (Play Store)

# Análisis
flutter analyze                      # verificar warnings
flutter format lib/                  # formatear código

# Testing
flutter test

# Dispositivos
flutter devices
emulator -list-avds
flutter run -d <device_id>
```

---

## Estructura M3U mejorada

```
#EXTM3U

# CANALES TV (grupos normales)
#EXTINF:-1 tvg-id="es.spain1" tvg-name="España 1" tvg-logo="http://logo.png" group-title="Generalistas",España 1
http://stream.m3u8

# SERIES (contienen S##E## en el nombre)
#EXTINF:-1 tvg-name="Breaking Bad" group-title="Series",Breaking Bad (S01E01)
http://stream1.m3u8
#EXTINF:-1 tvg-name="Breaking Bad" group-title="Series",Breaking Bad (S01E02)
http://stream2.m3u8

# PELÍCULAS (grupo = Movies o categoría película)
#EXTINF:-1 tvg-name="Inception" tvg-logo="http://poster.jpg" group-title="Movies",Inception
http://stream_movie.m3u8
```

---

## Modelos de datos - Relaciones

```
Playlist (maestro)
├── channels: List<Channel>    (TV en vivo)
├── series: List<Series>
│   └── seasons: List<Season>
│       └── episodes: List<Episode>  (cada episode tiene URL para reproducir)
└── movies: List<Movie>

ContentType enum:
- TV       (Channel)
- SERIES   (Series + Season + Episode)
- MOVIES   (Movie)
```

---

## Patterns Dart/Flutter

### Enums con métodos de extensión
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
  
  IconData get icon => switch(this) {
    ContentType.TV => Icons.tv,
    ContentType.SERIES => Icons.play_circle,
    ContentType.MOVIES => Icons.movie,
  };
}
```

### Map vs List retorno
```dart
// Retornar mapa de tipos
Map<String, List> parseM3U(String content) {
  return {
    'TV': channels,
    'SERIES': series,
    'MOVIES': movies,
  };
}

// Acceder a cada tipo
final map = parseM3U(content);
final channels = map['TV'] as List<Channel>;
final series = map['SERIES'] as List<Series>;
```

### Búsqueda fuzzy con fuzzywuzzy
```dart
import 'package:fuzzywuzzy/fuzzywuzzy.dart';

List<Channel> searchChannels(String query, List<Channel> channels) {
  return channels
    .where((ch) => extractOne(query, [ch.name], cutoff: 60).score > 60)
    .toList();
}
```

### GridView responsive
```dart
GridView.builder(
  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: isTV(context) ? 4 : 2,
    childAspectRatio: 0.7,
    spacing: 16,
  ),
  itemBuilder: (context, i) => ContentCard(items[i]),
)
```

### DraggableScrollableSheet (Bottom Sheet)
```dart
DraggableScrollableSheet(
  initialChildSize: 0.5,
  minChildSize: 0.3,
  maxChildSize: 0.9,
  builder: (context, controller) => SingleChildScrollView(
    controller: controller,
    child: Column(
      children: [...],
    ),
  ),
)
```

### ValueNotifier + ValueListenableBuilder
```dart
final favoriteNotifier = ValueNotifier<bool>(false);

ValueListenableBuilder<bool>(
  valueListenable: favoriteNotifier,
  builder: (context, isFavorite, child) {
    return IconButton(
      icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border),
      onPressed: () => favoriteNotifier.value = !favoriteNotifier.value,
    );
  },
)
```

### Provider + ChangeNotifier
```dart
class StorageService extends ChangeNotifier {
  List<String> _favorites = [];
  
  void addFavorite(String id) {
    _favorites.add(id);
    notifyListeners();
  }
}

// En widget
Consumer<StorageService>(
  builder: (context, storage, _) {
    return Text('Favoritos: ${storage.favorites.length}');
  },
)
```

### Regex para parsear M3U
```dart
// Extraer atributos #EXTINF
final pattern = RegExp(
  r'tvg-name="([^"]*)".*?tvg-logo="([^"]*)".*?group-title="([^"]*)".*?tvg-id="([^"]*)".*?,(.+)',
  dotAll: true,
);

final match = pattern.firstMatch(extinf);
final name = match?.group(5);
final logo = match?.group(2);
final group = match?.group(3);
```

### GoRouter navigation con parámetros
```dart
// Definir ruta
GoRoute(
  path: '/player',
  builder: (context, state) {
    final type = state.uri.queryParameters['type']; // TV|SERIES|MOVIES
    final id = state.uri.queryParameters['id'];
    return PlayerScreen(type: type, id: id);
  },
)

// Navegar
context.go('/player?type=TV&id=123');
```

### Media Kit básico
```dart
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

final player = Player();

// Reproducir
await player.open(Media('http://stream.m3u8'));

// Escuchar eventos
player.stream.playing.listen((isPlaying) {
  print('Playing: $isPlaying');
});

player.stream.duration.listen((duration) {
  print('Duration: $duration');
});

// Controles
await player.play();
await player.pause();
await player.seek(Duration(seconds: 30));
player.setVolume(50);
```

### Hive - Persistencia local
```dart
// Inicializar
await Hive.initFlutter();
await Hive.openBox('playlists');

// Guardar
final box = Hive.box('playlists');
box.put('key1', playlist);

// Leer
final playlist = box.get('key1');

// Listar todos
final all = box.values.toList();

// Borrar
box.delete('key1');
```

---

## Android TV Optimización

### Detectar TV
```dart
bool isTV(BuildContext context) {
  final diagonal = MediaQuery.of(context).size.diagonal;
  return diagonal > 6.5;  // pulgadas
}
```

### D-Pad Navigation (Focus + KeyEvent)
```dart
Focus(
  onKey: (node, event) {
    if (event.isKeyPressed(LogicalKeyboardKey.arrowRight)) {
      // Siguiente
      return KeyEventResult.handled;
    }
    if (event.isKeyPressed(LogicalKeyboardKey.arrowLeft)) {
      // Anterior
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  },
  child: YourWidget(),
)
```

### Botones grandes para TV
```dart
SizedBox(
  width: isTV(context) ? 200 : 100,
  height: isTV(context) ? 70 : 50,
  child: ElevatedButton(
    onPressed: () {},
    child: Text('Botón', style: TextStyle(
      fontSize: isTV(context) ? 20 : 16,
    )),
  ),
)
```

### Tema oscuro con alto contraste
```dart
ThemeData.dark(useMaterial3: true).copyWith(
  primaryColor: Colors.blue[700],
  textTheme: TextTheme(
    bodyLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
  ),
  buttonTheme: ButtonThemeData(
    height: 60,
    minWidth: 200,
  ),
)
```

---

## Errores comunes y soluciones

| Error | Causa | Solución |
|-------|-------|----------|
| `No devices found` | Emulador no iniciado | `emulator -list-avds` y `emulator -avd <name>` |
| `Gradle sync failed` | Dependencias no sincronizadas | `flutter clean` + `flutter pub get` |
| `media_kit not found` | Falta ejecutar pub get | `flutter pub get` |
| `Hive adapter not generated` | No ejecutó build_runner | `flutter pub run build_runner build` |
| `GoRoute not matching` | Parámetros mal definidos | Verificar QueryParameters vs pathParameters |
| `FuzzyWuzzy not found` | Dependencia no instalada | `flutter pub add fuzzywuzzy` |
| `Video no se reproduce` | URL inválida o permiso INTERNET | Verificar URL, revisar AndroidManifest INTERNET |
| `Overflow en GridView TV` | Demasiadas columnas | Reducir crossAxisCount o aumentar spacing |

---

## Testing

```bash
# Test unitarios
flutter test

# Test con emulador específico
flutter run -d emulator-5554

# Build APK debug para testing
flutter build apk --debug

# Instalar y ejecutar APK
adb install build/app/outputs/flutter-apk/app-debug.apk
```

---

## Google Play Release

### 1. Crear keystore (una sola vez)
```bash
keytool -genkey -v -keystore ~/key.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias key
```

### 2. Configurar signing (android/app/build.gradle)
```gradle
signingConfigs {
  release {
    keyAlias 'key'
    keyPassword 'tu_password'
    storeFile file('/path/to/key.jks')
    storePassword 'tu_password'
  }
}

buildTypes {
  release {
    signingConfig signingConfigs.release
  }
}
```

### 3. Build App Bundle
```bash
flutter build appbundle --release
# Output: build/app/outputs/bundle/release/app-release.aab
```

### 4. Subir a Play Console
1. Crear app en Google Play Console
2. Subir .aab file
3. Completar metadata (descripción, screenshots, privacidad)
4. Enviar para review

---

## Performance Tips

1. **Caché de imágenes:**
```dart
cached_network_image: ^3.3.0

CachedNetworkImage(
  imageUrl: 'http://poster.jpg',
  placeholder: (context, url) => Shimmer.fromColors(...),
)
```

2. **Lazy loading:**
```dart
ListView.builder(
  itemCount: items.length,
  itemBuilder: (context, i) => ItemWidget(items[i]),
)
```

3. **Debounce búsqueda:**
```dart
Timer? _searchTimer;

void _onSearchChanged(String query) {
  _searchTimer?.cancel();
  _searchTimer = Timer(Duration(milliseconds: 500), () {
    // Realizar búsqueda
  });
}
```

4. **Dispose de Player:**
```dart
@override
void dispose() {
  _player.dispose();
  super.dispose();
}
```

---

## Recursos

- [Flutter Docs](https://flutter.dev/docs)
- [media_kit](https://pub.dev/packages/media_kit)
- [Hive](https://pub.dev/packages/hive)
- [GoRouter](https://pub.dev/packages/go_router)
- [Provider](https://pub.dev/packages/provider)
- [Android TV Dev](https://developer.android.com/training/tv)
- [Google Play Console](https://play.google.com/console)
