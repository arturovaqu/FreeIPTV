import 'dart:async';
import 'dart:convert';
import 'dart:io';

// ─────────────────────────────────────────────────────────────────────────────
// PairingServer
// ─────────────────────────────────────────────────────────────────────────────

/// Servidor HTTP local para el patrón "Remote Pairing".
///
/// La TV inicia el servidor en segundo plano, muestra un QR con la URL
/// `http://<ip_local>:8080`. El usuario escanea con su móvil, rellena el
/// formulario M3U y hace submit. La TV recibe el POST y carga la playlist.
class PairingServer {
  static const int port = 8080;

  HttpServer? _server;
  String?     _ip;

  /// URL completa del servidor: `http://<ip>:8080`, o null si no hay red.
  String? get serverUrl => _ip != null ? 'http://$_ip:$port' : null;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Arranca el servidor y llama [onReceived] cuando el móvil hace submit.
  Future<void> start(void Function(String url, String name) onReceived) async {
    _ip = await _localIp();
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port,
        shared: true);
    _handle(onReceived);
  }

  /// Para el servidor de forma segura.
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  // ── Request handler ────────────────────────────────────────────────────────

  void _handle(void Function(String url, String name) onReceived) {
    _server!.listen((HttpRequest req) async {
      // CORS headers para que el fetch del móvil funcione.
      req.response.headers
        ..add('Access-Control-Allow-Origin', '*')
        ..add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        ..add('Access-Control-Allow-Headers', 'Content-Type');

      if (req.method == 'OPTIONS') {
        req.response
          ..statusCode = HttpStatus.ok
          ..close();
        return;
      }

      if (req.method == 'GET') {
        req.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.html
          ..write(_html)
          ..close();
        return;
      }

      if (req.method == 'POST') {
        try {
          final body   = await utf8.decoder.bind(req).join();
          final params = Uri.splitQueryString(body);
          final url    = (params['url'] ?? '').trim();
          final name   = (params['name'] ?? '').trim();

          req.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write('{"ok":true}')
            ..close();

          if (url.isNotEmpty) onReceived(url, name);
        } catch (_) {
          req.response
            ..statusCode = HttpStatus.badRequest
            ..close();
        }
        return;
      }

      req.response
        ..statusCode = HttpStatus.methodNotAllowed
        ..close();
    });
  }

  // ── IP helper ──────────────────────────────────────────────────────────────

  Future<String?> _localIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      // Prioridad: rangos privados típicos de LAN
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final a = addr.address;
          if (a.startsWith('192.168.') ||
              a.startsWith('10.')      ||
              a.startsWith('172.')) {
            return a;
          }
        }
      }
      // Fallback: cualquier IPv4 que no sea loopback
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          return addr.address;
        }
      }
    } catch (_) {}
    return null;
  }

  // ── HTML portal ────────────────────────────────────────────────────────────

  static const String _html = '''<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width,initial-scale=1.0">
  <title>IPTV Player — Agregar Playlist</title>
  <style>
    *{box-sizing:border-box;margin:0;padding:0}
    body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;
         background:#111827;color:#f9fafb;min-height:100vh;
         display:flex;align-items:center;justify-content:center;padding:24px}
    .card{background:#1f2937;border-radius:16px;padding:32px 24px;
          width:100%;max-width:480px;box-shadow:0 20px 60px rgba(0,0,0,.5)}
    .logo{font-size:32px;text-align:center;margin-bottom:6px}
    h1{font-size:22px;font-weight:700;text-align:center;margin-bottom:6px}
    .sub{color:#9ca3af;text-align:center;font-size:14px;margin-bottom:28px}
    label{display:block;font-size:13px;font-weight:600;color:#d1d5db;margin-bottom:6px}
    input{width:100%;padding:14px 16px;background:#374151;border:2px solid #4b5563;
          border-radius:10px;color:#f9fafb;font-size:16px;outline:none;
          transition:border-color .2s;margin-bottom:18px}
    input:focus{border-color:#7c3aed}
    button{width:100%;padding:16px;background:#7c3aed;color:#fff;border:none;
           border-radius:10px;font-size:16px;font-weight:700;cursor:pointer;
           transition:background .2s;margin-top:4px}
    button:hover{background:#6d28d9}
    button:disabled{background:#4b5563;cursor:default}
    .note{margin-top:16px;font-size:12px;color:#6b7280;text-align:center}
    #ok{display:none;text-align:center;padding:24px 0}
    .ok-icon{font-size:52px;margin-bottom:12px}
  </style>
</head>
<body>
  <div class="card">
    <div class="logo">📺</div>
    <h1>Agregar Playlist</h1>
    <p class="sub">Introduce los datos de tu lista M3U</p>

    <div id="form">
      <label for="url">URL de la Playlist M3U *</label>
      <input type="url" id="url" name="url"
             placeholder="http://proveedor.com/lista.m3u"
             required autocomplete="off" autocorrect="off" spellcheck="false">
      <label for="name">Nombre (opcional)</label>
      <input type="text" id="name" name="name" placeholder="Mi Playlist">
      <button id="btn" type="button">&#10003; Cargar en el televisor</button>
      <p class="note">La playlist se cargará directamente en tu televisor.</p>
    </div>

    <div id="ok">
      <div class="ok-icon">&#10003;</div>
      <p style="font-size:18px;font-weight:700">&#161;Enviado!</p>
      <p style="color:#9ca3af;margin-top:8px">Cargando en el televisor&hellip;</p>
    </div>
  </div>

  <script>
    document.getElementById('btn').addEventListener('click',function(){
      var url=document.getElementById('url').value.trim();
      if(!url){document.getElementById('url').focus();return;}
      var btn=document.getElementById('btn');
      btn.disabled=true; btn.textContent='Enviando...';
      var body='url='+encodeURIComponent(url)
              +'&name='+encodeURIComponent(document.getElementById('name').value);
      fetch('/',{method:'POST',
                 headers:{'Content-Type':'application/x-www-form-urlencoded'},
                 body:body})
        .then(function(){
          document.getElementById('form').style.display='none';
          document.getElementById('ok').style.display='block';
        })
        .catch(function(){
          document.getElementById('form').style.display='none';
          document.getElementById('ok').style.display='block';
        });
    });
  </script>
</body>
</html>''';
}
