# 🛠️ IPTV App - Tips, Troubleshooting y Mejores Prácticas

---

## 📌 Tips para Claude Code

### 1. Cómo pasar un prompt efectivo
```
BUENO:
"Crea lib/models/channel.dart con clase Channel @immutable:
- Propiedades: id, name, logo, url, group
- Constructor Channel.fromM3ULine(extinf, url)
- copyWith() method"

MEJOR:
[Copia el prompt del documento PROMPTS_V2_CLAUDE_CODE.md directo]

MAL:
"Crea los modelos"
→ Demasiado vago, resultado impredecible
```

### 2. Después de cada prompt
```
"Compila y verifica que no haya errores"

Si hay errores:
"¿Qué error da? Muéstrame el mensaje completo"
"Corrige ese error y compila de nuevo"

Repite hasta que compile sin warnings.
```

### 3. Si el código no funciona como esperado
```
1. Pide a Claude Code que agregue logging:
   "Añade print() statements para debug en [método/widget]"

2. Pasa la salida de debug:
   "Aquí está la salida del debug: [output]
    ¿Por qué hace esto en lugar de aquello?"

3. Pide que explique la lógica:
   "¿Cómo funciona exactamente [método]? Explícame paso a paso"
```

### 4. Reutiliza el contexto
```
Si necesitas cambios después, pasa el archivo completo:
"Aquí está lib/models/channel.dart [PEGA CÓDIGO]

Necesito cambiar X por Y. Hazlo en el archivo y compila."

Esto es más efectivo que describir el cambio.
```

---

## 🔍 Troubleshooting común

### Error: "No channel named 'TV' found"
**Causa:** ContentType no existe en el enum  
**Solución:**
```dart
// Asegúrate que content_type.dart tiene:
enum ContentType {
  TV,
  SERIES,
  MOVIES
}

// Y no algo como:
enum ContentType {
  TV_CHANNEL,  // ❌ Incorrecto
}
```

---

### Error: "Failed to parse M3U"
**Causa:** Regex de parsing no coincide con formato M3U  
**Solución:**
```dart
// Prueba el regex en https://regex101.com con un M3U real
// Asegúrate que captura estos grupos:
#EXTINF:-1 tvg-id="ID" tvg-name="NAME" tvg-logo="LOGO" group-title="GROUP",TITLE
         ^----1----^ ^---2---^ ^---3---^ ^---4---^ ^----5----^         ^--6--^

// El código debe hacer:
final match = pattern.firstMatch(line);
final tvgId = match?.group(1);      // ID
final tvgName = match?.group(2);    // NAME
final logo = match?.group(3);       // LOGO
final group = match?.group(4);      // GROUP
final title = match?.group(6);      // TITLE
```

---

### Error: "Stream not playing" en reproductor
**Causa:** URL inválida o sin permiso INTERNET  
**Solución:**
```yaml
# 1. Verifica que AndroidManifest.xml tiene:
<uses-permission android:name="android.permission.INTERNET" />

# 2. Prueba la URL en un reproductor externo (VLC) primero
# 3. Añade logging al planar:
await player.open(Media(channel.url));
print('Playing: ${channel.url}');

# 4. Si falla, captura error:
try {
  await player.open(Media(channel.url));
} catch (e) {
  print('Error: $e');
}
```

---

### Error: "GridView overflow" en TV
**Causa:** Demasiadas columnas o items muy grandes  
**Solución:**
```dart
GridView.builder(
  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: isTV(context) ? 3 : 2,  // Reduce a 3 si es TV
    childAspectRatio: 0.7,                   // Ajusta ratio
    crossAxisSpacing: 16,
    mainAxisSpacing: 16,
  ),
)

// O usa adaptive:
crossAxisCount: MediaQuery.of(context).size.width ~/ 200,
```

---

### Error: "Hive not initialized"
**Causa:** initializeHive() no se ejecutó en main()  
**Solución:**
```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized()
  
  // ⭐ IMPORTANTE: antes de runApp
  await StorageService.instance.initializeHive()
  await MediaService.instance.initialize()
  
  runApp(const MyApp())
}
```

---

### Error: "fuzzywuzzy not found"
**Causa:** Dependencia no instalada  
**Solución:**
```bash
flutter pub add fuzzywuzzy
flutter pub get
```

---

### Error: "VideoProgressIndicator not found"
**Causa:** No importaste media_kit_video  
**Solución:**
```dart
import 'package:media_kit_video/media_kit_video.dart';  // ⭐ Agregar

// Luego puedes usar:
VideoProgressIndicator(
  player: mediaService.player,
  allowScrubbing: true,
)
```

---

## ✅ Checklist antes de publicar

### Funcionalidad
- [ ] Cargar M3U desde URL funciona
- [ ] Parse correctamente TV, Series, Películas
- [ ] Reproduce canales sin lag
- [ ] Reproduce series (episodios, cambio siguiente/anterior)
- [ ] Reproduce películas
- [ ] Busca global funciona (todos los tipos)
- [ ] Filtros por categoría funcionan
- [ ] Favoritos guardan/cargan correctamente
- [ ] Historial guarda posición y time
- [ ] Continuar desde donde se quedó funciona

### UI/UX
- [ ] Home con 4 tabs visible
- [ ] TVListScreen: lista scrolleable, filtros
- [ ] SeriesListScreen: grid con detalles, episodios
- [ ] MoviesListScreen: grid con detalles
- [ ] SearchScreen: búsqueda en tiempo real, sugerencias
- [ ] PlayerScreen: fullscreen, controles, auto-hide
- [ ] Botones favoritos funcionan visualmente
- [ ] Tema oscuro optimizado para TV
- [ ] No hay overflow/truncado en textos

### Android TV
- [ ] Detecta que es TV correctamente
- [ ] D-Pad navigation funciona (left/right/up/down)
- [ ] Botones son grandes y focusables
- [ ] Sin hover (solo focus)
- [ ] Texto legible desde lejos

### Technical
- [ ] `flutter analyze` sin warnings
- [ ] Compilar APK sin errores: `flutter build apk --release`
- [ ] Compilar Bundle sin errores: `flutter build appbundle --release`
- [ ] Probado en emulador móvil
- [ ] Probado en emulador Android TV (si es posible)
- [ ] Probado en dispositivo físico real

### Google Play
- [ ] version en pubspec.yaml correcta (1.0.0+1)
- [ ] minSdkVersion: 21
- [ ] targetSdkVersion: 34
- [ ] AndroidManifest.xml: permisos INTERNET
- [ ] AndroidManifest.xml: features TV optional
- [ ] App Bundle (.aab) generado
- [ ] Metadata completa (descripción, screenshots, privacidad)
- [ ] Cuenta Google Play Developer creada

---

## 🚀 Optimizaciones post-MVP

### 1. Caché de imágenes
```dart
dependencies:
  cached_network_image: ^3.3.0

// Usar en posters:
CachedNetworkImage(
  imageUrl: series.poster ?? '',
  placeholder: (context, url) => Container(color: Colors.grey[800]),
  errorWidget: (context, url, error) => Icon(Icons.broken_image),
)
```

### 2. Debounce en búsqueda
```dart
Timer? _searchTimer;

void _onSearchChanged(String query) {
  _searchTimer?.cancel();
  _searchTimer = Timer(Duration(milliseconds: 500), () {
    setState(() => _filteredResults = SearchService.instance.searchGlobal(query, _playlist));
  });
}
```

### 3. Precargar siguiente episodio
```dart
// En MediaService, cuando termina un episodio:
_player.stream.completed.listen((_) {
  if (playNextEpisode()) {
    // Automáticamente carga siguiente
  }
});
```

### 4. Sync en la nube (Firebase)
```dart
// Guardar favoritos en Firestore
await FirebaseFirestore.instance
  .collection('users')
  .doc(userId)
  .collection('favorites')
  .doc(contentId)
  .set({'type': type.name, 'timestamp': DateTime.now()});
```

### 5. Notificaciones de nuevos episodios
```dart
// Usar firebase_messaging o local_notifications
void _notifyNewEpisode(Series series) {
  flutterLocalNotificationsPlugin.show(
    series.id.hashCode,
    'Nuevo episodio de ${series.name}',
    'Temporada ${season.seasonNumber}',
  );
}
```

---

## 📊 Estructura M3U de ejemplo

```m3u
#EXTM3U

# CANALES TV
#EXTINF:-1 tvg-id="es.spain1" tvg-name="España 1" tvg-logo="https://logo1.png" group-title="Generalistas",España 1
http://stream1.es.m3u8
#EXTINF:-1 tvg-id="es.spain2" tvg-name="España 2" tvg-logo="https://logo2.png" group-title="Generalistas",España 2
http://stream2.es.m3u8

# SERIES
#EXTINF:-1 tvg-name="Breaking Bad" tvg-logo="https://breaking-bad.jpg" group-title="Series",Breaking Bad (S01E01)
http://series-stream-s01e01.m3u8
#EXTINF:-1 tvg-name="Breaking Bad" tvg-logo="https://breaking-bad.jpg" group-title="Series",Breaking Bad (S01E02)
http://series-stream-s01e02.m3u8
#EXTINF:-1 tvg-name="Breaking Bad" tvg-logo="https://breaking-bad.jpg" group-title="Series",Breaking Bad (S02E01)
http://series-stream-s02e01.m3u8

# PELÍCULAS
#EXTINF:-1 tvg-name="Inception" tvg-logo="https://inception.jpg" group-title="Movies",Inception
http://movie-stream-inception.m3u8
#EXTINF:-1 tvg-name="Avatar" tvg-logo="https://avatar.jpg" group-title="Movies",Avatar
http://movie-stream-avatar.m3u8
```

---

## 🎨 Tema Dark optimizado para TV

```dart
ThemeData buildDarkTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: Brightness.dark,
    ),
    textTheme: TextTheme(
      displayLarge: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
      displayMedium: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
      headlineLarge: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      titleLarge: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
      bodyLarge: const TextStyle(fontSize: 18),    // Más grande para TV
      bodyMedium: const TextStyle(fontSize: 16),
    ),
    appBarTheme: const AppBarTheme(
      elevation: 4,
      backgroundColor: Color(0xFF1E1E1E),
    ),
    scaffoldBackgroundColor: const Color(0xFF121212),
    inputDecorationTheme: InputDecorationTheme(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );
}
```

---

## 🔐 Seguridad

### 1. Validar URLs antes de reproducir
```dart
bool _isValidStreamUrl(String url) {
  try {
    Uri.parse(url);
    return url.startsWith('http://') || url.startsWith('https://');
  } catch (e) {
    return false;
  }
}

// Usar:
if (_isValidStreamUrl(channel.url)) {
  await mediaService.playChannel(channel);
} else {
  // Mostrar error
}
```

### 2. Sanitizar entrada M3U
```dart
String _sanitizeName(String name) {
  return name
    .replaceAll(RegExp(r'<[^>]*>'), '')  // Quitar HTML
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ');    // Espacios múltiples
}
```

### 3. No guardar URLs sensibles en texto plano
```dart
// ❌ MAL:
prefs.setString('apiKey', apiKey);

// ✅ BIEN (usar flutter_secure_storage):
final secureStorage = FlutterSecureStorage();
await secureStorage.write(key: 'apiKey', value: apiKey);
```

---

## 📝 Logging para debugging

```dart
// Crear logger simple
class Logger {
  static void log(String tag, String message) {
    print('[$tag] $message');
  }
}

// Usar en servicios:
Logger.log('M3UParser', 'Parsing M3U from: $url');
Logger.log('MediaService', 'Playing: ${channel.name}');
Logger.log('SearchService', 'Found ${results.length} results');
```

---

## 🎯 Próximos features (roadmap)

**Versión 1.1:**
- Subtítulos (hardcoded, SRT)
- Favoritos sincronizados en nube (Firebase)
- Watchlist para películas pendientes

**Versión 1.2:**
- Chromecast support
- EPG (guía de programación)
- Recomendaciones basadas en historial

**Versión 2.0:**
- Usuarios múltiples (perfiles)
- Sincronización de dispositivos
- Dark/Light theme dinámico
- Soporte para subtítulos online
- Interfaz gestures avanzados

---

## 📞 Recursos útiles

### Documentación
- [Flutter Docs](https://flutter.dev/docs)
- [Dart Docs](https://dart.dev/guides)
- [media_kit Docs](https://pub.dev/packages/media_kit)
- [Hive Docs](https://pub.dev/packages/hive)

### Debugging
- [Android Studio](https://developer.android.com/studio)
- [DevTools](https://flutter.dev/docs/development/tools/devtools)
- [Logcat](https://developer.android.com/studio/command-line/logcat)

### Publicación
- [Google Play Console](https://play.google.com/console)
- [Play Developer Help](https://support.google.com/googleplay/android-developer)
- [App Signing](https://developer.android.com/studio/publish/app-signing)

### Comunidad
- [Stack Overflow (flutter tag)](https://stackoverflow.com/questions/tagged/flutter)
- [Reddit r/flutter](https://reddit.com/r/FlutterDev)
- [Flutter Discord](https://discord.gg/flutter)

---

## ✨ Notas finales

1. **Compila frecuentemente:** No esperes a terminar todo
2. **Prueba con URLs reales:** M3U de ejemplo vs URLs verdaderas
3. **Testing en dispositivo físico:** Los emuladores pueden ser engañosos
4. **Sé paciente con media_kit:** A veces necesita tiempo para inicializar streams
5. **Documentación es clave:** Comenta tu código, será más fácil mantenerlo
6. **Feedback del usuario:** Publica betas, recibe feedback, itera

---

¡Éxito con tu app IPTV! 🚀
