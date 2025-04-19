import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(TranscaribeApp());
}

class TranscaribeApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TransCaribe SSO',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.teal),
      home: LoginPage(),
    );
  }
}

///
/// 1) API de TransCaribe: todo el flujo de SSO para el portal web
///
class TranscaribeApi {
  final _client = http.Client();
  String? _cookie;
  String? _dni; // lo guardamos para el createSession final

  /// Paso 1: validar DNI enviando appUrl
  Future<void> validateDni(String dni) async {
    final url = Uri.parse('https://recaudo.sondapay.com/usuario/verificaIndValido');
    final body = jsonEncode({
      'dni': dni,
      'appUrl': 'https://recaudo.sondapay.com/Pocae'
    });

    final resp = await _client.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json, text/plain, */*',
        'Origin': 'https://recaudo.sondapay.com',
      },
      body: body,
    );

    if (resp.statusCode != 200) {
      throw 'Paso 1 HTTP ${resp.statusCode}';
    }
    final data = jsonDecode(resp.body);
    if (data['numError'] != 0) {
      throw data['msjError'] ?? 'DNI no válido';
    }

    _cookie = resp.headers['set-cookie'];
    _dni = dni;
    debugPrint('✅ Paso 1 OK — Cookie parcial guardada');
  }

  /// Paso 2: validar contraseña enviando password + nomHost
  Future<void> validatePassword(String password) async {
    final url = Uri.parse('https://recaudo.sondapay.com/usuario/verificaIndValido');
    final body = jsonEncode({
      'dni': _dni,
      'password': password,
      'nomHost': '127.0.0.1',
    });

    final resp = await _client.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json, text/plain, */*',
        'Origin': 'https://recaudo.sondapay.com',
        'Cookie': _cookie ?? '',
      },
      body: body,
    );

    if (resp.statusCode != 200) {
      throw 'Paso 2 HTTP ${resp.statusCode}';
    }
    final data = jsonDecode(resp.body);
    if (data['numError'] != 0) {
      throw data['msjError'] ?? 'Contraseña incorrecta';
    }

    _cookie = resp.headers['set-cookie'];
    debugPrint('✅ Paso 2 OK — Cookie final guardada');
  }

  /// Paso 3: crea la sesión en /usuario/sesion/creaSesion
  Future<void> createSession() async {
    final url = Uri.parse('https://recaudo.sondapay.com/usuario/sesion/creaSesion');
    final body = jsonEncode({
      'dni': _dni,
      'appUrl': 'https://recaudo.sondapay.com/Pocae'
    });

    final resp = await _client.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json, text/plain, */*',
        'Origin': 'https://recaudo.sondapay.com',
        'Cookie': _cookie ?? '',
      },
      body: body,
    );

    if (resp.statusCode != 200) {
      throw 'createSession HTTP ${resp.statusCode}';
    }

    debugPrint('✅ Sesión portal creada correctamente');
  }

  String? get cookie => _cookie;
}


///
/// 2) Pantalla de login
///
class LoginPage extends StatefulWidget {
  @override
  _LoginPageState createState() => _LoginPageState();
}
class _LoginPageState extends State<LoginPage> {
  final _dniCtrl  = TextEditingController();
  final _passCtrl = TextEditingController();
  bool  _loading = false;
  String? _error;
  final _api = TranscaribeApi();

  Future<void> _onLoginPressed() async {
    setState(() {
      _loading = true;
      _error   = null;
    });
    try {
      await _api.validateDni(_dniCtrl.text.trim());
      await _api.validatePassword(_passCtrl.text);
      await _api.createSession();

      // Navegar al portal ya autenticado
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => PortalPage(api: _api))
      );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Iniciar sesión')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            TextField(
              controller: _dniCtrl,
              decoration: InputDecoration(labelText: 'Cédula de identidad'),
              keyboardType: TextInputType.number,
            ),
            SizedBox(height: 16),
            TextField(
              controller: _passCtrl,
              decoration: InputDecoration(labelText: 'Contraseña'),
              obscureText: true,
              maxLength: 12,
            ),
            if (_error != null) ...[
              SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Colors.red)),
            ],
            Spacer(),
            ElevatedButton(
              onPressed: _loading ? null : _onLoginPressed,
              style: ElevatedButton.styleFrom(minimumSize: Size(double.infinity, 48)),
              child: _loading
                  ? CircularProgressIndicator(color: Colors.white)
                  : Text('Iniciar sesión'),
            ),
          ],
        ),
      ),
    );
  }
}


///
/// 3) WebView con sesión ya iniciada
///
class PortalPage extends StatefulWidget {
  final TranscaribeApi api;
  PortalPage({required this.api});

  @override
  _PortalPageState createState() => _PortalPageState();
}
class _PortalPageState extends State<PortalPage> {
  late final WebViewController _webCtrl;

  @override
  void initState() {
    super.initState();

    _webCtrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (url) => debugPrint('🔵 Cargada $url'),
      ));

    if (!kIsWeb && widget.api.cookie != null) {
      // inyectar cookie en WebView (Android/iOS)
      final parts = widget.api.cookie!.split(';').first.split('=');
      final name  = parts[0];
      final value = parts.sublist(1).join('=');

      WebViewCookieManager()
          .setCookie(WebViewCookie(
        name:   name,
        value:  value,
        domain: 'recaudo.sondapay.com',
        path:   '/',
      ))
          .then((_) {
        debugPrint('✅ Cookie inyectada: $name=$value');
        _webCtrl.loadRequest(Uri.parse('https://recaudo.sondapay.com/Pocae/#/'));
      });
    } else {
      _webCtrl.loadRequest(Uri.parse('https://recaudo.sondapay.com/Pocae/#/'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Portal TransCaribe')),
      body: WebViewWidget(controller: _webCtrl),
    );
  }
}
