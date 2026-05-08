import 'dart:async';
import 'dart:math' as math;
import 'dart:html' as html;
import 'dart:js' show allowInterop;
import 'dart:js_util' as js_util;
import 'dart:ui_web' as ui_web;
import 'dart:convert';
import 'package:flutter/material.dart';

void main() {
  runApp(const TerlineTUniverseApp());
}

class TerlineTUniverseApp extends StatelessWidget {
  const TerlineTUniverseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'TerlineT Universe',
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: Colors.blue,
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<Particle> particles = [];
  final math.Random random = math.Random();
  static const int particleCount = 480;

  // IA & Camera Variables
  final html.VideoElement _cameraVideoElement = html.VideoElement();
  bool _isUserLooking = false;
  dynamic _faceDetection;
  Timer? _detectionTimer;
  String _aiMessage = "Sistemas prontos. Olhe para a tela ou digite algo para iniciar.";
  bool _isAiTalking = false;
  bool _isProcessing = false;
  bool _hasCamera = true;

  // Controllers para entrada do usuário
  final TextEditingController _textController = TextEditingController();
  dynamic _recognition; // SpeechRecognition
  bool _isListening = false;

  // Configuração do Servidor Hugging Face Exclusivo
  final String _apiUrl = "https://tertulianoshow-terlinet-universe.hf.space/query";

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    // Initialize particles
    for (int i = 0; i < particleCount; i++) {
      String? label;
      if (random.nextDouble() > 0.8) {
        label = (random.nextDouble() * 50000 - 25000).toStringAsFixed(2);
        if (random.nextBool()) label = "$label%";
      }
      particles.add(Particle(
        x: random.nextDouble(),
        y: random.nextDouble(),
        vx: (random.nextDouble() - 0.5) * 0.003,
        vy: (random.nextDouble() - 0.5) * 0.003,
        label: label,
      ));
    }

    ui_web.platformViewRegistry.registerViewFactory(
      'webcam-view',
      (int viewId) => _cameraVideoElement,
    );

    _initFaceIA();
    _startCamera();
    _initSpeechRecognition();
  }

  void _initSpeechRecognition() {
    try {
      final speechClass = js_util.getProperty(html.window, 'webkitSpeechRecognition') ?? 
                          js_util.getProperty(html.window, 'SpeechRecognition');
      if (speechClass != null) {
        _recognition = js_util.callConstructor(speechClass, []);
        js_util.setProperty(_recognition, 'lang', 'pt-BR');
        js_util.setProperty(_recognition, 'interimResults', false);

        js_util.setProperty(_recognition, 'onresult', allowInterop((event) {
          final results = js_util.getProperty(event, 'results');
          final firstResult = js_util.getProperty(results, 0);
          final firstAlternative = js_util.getProperty(firstResult, 0);
          final transcript = js_util.getProperty(firstAlternative, 'transcript');
          
          setState(() {
            _textController.text = transcript;
            _isListening = false;
          });
          _triggerAiInteraction(customText: transcript);
        }));

        js_util.setProperty(_recognition, 'onerror', allowInterop((error) {
          setState(() => _isListening = false);
          print("Erro Speech Recognition: $error");
        }));

        js_util.setProperty(_recognition, 'onend', allowInterop((_) {
          setState(() => _isListening = false);
        }));
      }
    } catch (e) {
      print("Speech recognition não suportado: $e");
    }
  }

  void _toggleListening() {
    if (_recognition == null) return;
    if (_isListening) {
      js_util.callMethod(_recognition, 'stop', []);
    } else {
      setState(() => _isListening = true);
      js_util.callMethod(_recognition, 'start', []);
    }
  }

  void _initFaceIA() {
    try {
      final faceClass = js_util.getProperty(html.window, 'FaceDetection');
      if (faceClass == null) return;

      final options = js_util.newObject();
      js_util.setProperty(options, 'locateFile', allowInterop((file, base) => 
        'https://cdn.jsdelivr.net/npm/@mediapipe/face_detection/$file'));
      
      _faceDetection = js_util.callConstructor(faceClass, [options]);
      
      js_util.callMethod(_faceDetection, 'setOptions', [
        js_util.jsify({
          'model': 'short',
          'minDetectionConfidence': 0.6
        })
      ]);

      js_util.callMethod(_faceDetection, 'onResults', [
        allowInterop((results) {
          final detections = js_util.getProperty(results, 'detections');
          bool found = detections != null && js_util.getProperty(detections, 'length') > 0;
          
          if (found != _isUserLooking) {
            setState(() {
              _isUserLooking = found;
              if (_isUserLooking && !_isProcessing) {
                _triggerAiInteraction();
              }
            });
          }
        })
      ]);
    } catch (e) {
      print('Erro ao iniciar IA: $e');
    }
  }

  Future<void> _startCamera() async {
    try {
      final stream = await html.window.navigator.mediaDevices!.getUserMedia({'video': true});
      _cameraVideoElement
        ..srcObject = stream
        ..autoplay = true
        ..muted = true;

      _detectionTimer = Timer.periodic(const Duration(milliseconds: 150), (timer) async {
        if (_cameraVideoElement.readyState >= 4 && _faceDetection != null) {
          await js_util.promiseToFuture(
            js_util.callMethod(_faceDetection, 'send', [js_util.jsify({'image': _cameraVideoElement})])
          );
        }
      });
      setState(() => _hasCamera = true);
    } catch (e) {
      setState(() {
        _hasCamera = false;
        _aiMessage = "Câmera não detectada ou permissão negada. Use o teclado ou voz para falar.";
      });
    }
  }

  // Chamada Real para o seu Servidor no Hugging Face
  Future<void> _triggerAiInteraction({String? customText}) async {
    if (_isProcessing) return;
    
    final prompt = customText ?? "Olá TerlineT, acabei de olhar para você. Me dê as boas vindas ao seu universo e pergunte como pode me ajudar.";

    setState(() {
      _isProcessing = true;
      _isAiTalking = true;
      _aiMessage = "Consultando rede neural TerlineT...";
    });

    try {
      final response = await html.window.fetch(
        _apiUrl,
        js_util.jsify({
          'method': 'POST',
          'headers': {'Content-Type': 'application/json'},
          'body': jsonEncode({
            'text': prompt,
            'is_agent': false,
          }),
        }),
      );

      final data = await response.json();
      final textResponse = js_util.getProperty(data, 'text');
      final audioBase64 = js_util.getProperty(data, 'audio');

      setState(() {
        _aiMessage = textResponse;
        _isProcessing = false;
        _textController.clear();
      });

      if (audioBase64 != null) {
        _playAiVoice(audioBase64);
      }
    } catch (e) {
      setState(() {
        _aiMessage = "Erro ao conectar com TerlineT: Verifique se o servidor está online.";
        _isProcessing = false;
      });
      print("Erro na API HuggingFace: $e");
    }
  }

  void _playAiVoice(String base64Audio) {
    try {
      final uri = 'data:audio/mp3;base64,$base64Audio';
      final audio = html.AudioElement(uri);
      audio.play();
    } catch (e) {
      print("Erro ao reproduzir voz: $e");
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _detectionTimer?.cancel();
    _cameraVideoElement.srcObject?.getTracks().forEach((track) => track.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Universe background
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              for (var p in particles) {
                p.x = (p.x + p.vx) % 1.0;
                p.y = (p.y + p.vy) % 1.0;
              }
              return CustomPaint(
                painter: UniversePainter(
                  particles: particles, 
                  isUserLooking: _isUserLooking
                ),
                child: Container(),
              );
            },
          ),

          // HUD do Usuário (Canto superior)
          Positioned(
            right: 20,
            top: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  width: 120,
                  height: 90,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _isUserLooking ? Colors.blueAccent : Colors.white10,
                      width: 2
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: _isUserLooking ? [
                      BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 10)
                    ] : [],
                  ),
                  child: const ClipRRect(
                    borderRadius: BorderRadius.all(Radius.circular(10)),
                    child: HtmlElementView(viewType: 'webcam-view'),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _isUserLooking ? "USUÁRIO DETECTADO" : "SCANNING...",
                  style: TextStyle(
                    color: _isUserLooking ? Colors.blueAccent : Colors.white24,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5
                  ),
                ),
              ],
            ),
          ),

          // Logo e Mensagem da IA
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'T',
                        style: TextStyle(
                          fontSize: 62,
                          fontWeight: FontWeight.w900,
                          color: _isUserLooking ? Colors.blue[50] : Colors.white,
                          shadows: [
                            Shadow(
                              blurRadius: _isUserLooking ? 40 : 25,
                              color: Colors.blue.withOpacity(0.9),
                              offset: const Offset(0, 0),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      Text(
                        'ERLINE',
                        style: TextStyle(
                          fontSize: 38,
                          fontWeight: FontWeight.w900,
                          color: Colors.white.withOpacity(0.95),
                          letterSpacing: 12,
                          shadows: [
                            Shadow(
                              blurRadius: 25,
                              color: Colors.blue.withOpacity(0.9),
                              offset: const Offset(0, 0),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      Text(
                        'T',
                        style: TextStyle(
                          fontSize: 62,
                          fontWeight: FontWeight.w900,
                          color: _isUserLooking ? Colors.blue[50] : Colors.white,
                          shadows: [
                            Shadow(
                              blurRadius: _isUserLooking ? 40 : 25,
                              color: Colors.blue.withOpacity(0.9),
                              offset: const Offset(0, 0),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'UNIVERSE',
                    style: TextStyle(
                      fontSize: 24,
                      color: Colors.blue[200],
                      letterSpacing: 24,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                  
                  // Mensagem Dinâmica da IA (Servidor HuggingFace)
                  const SizedBox(height: 40),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 500),
                    constraints: const BoxConstraints(maxWidth: 600),
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: _isProcessing ? Colors.blueAccent : Colors.blue.withOpacity(0.2),
                        width: 1.5,
                      ),
                      boxShadow: _isProcessing ? [
                        BoxShadow(color: Colors.blue.withOpacity(0.2), blurRadius: 25)
                      ] : [],
                    ),
                    child: Column(
                      children: [
                        if (_isProcessing) 
                          const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: LinearProgressIndicator(
                              backgroundColor: Colors.transparent,
                              color: Colors.blueAccent,
                            ),
                          ),
                        Text(
                          _aiMessage,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            color: _isProcessing ? Colors.white : Colors.blue[50],
                            letterSpacing: 1.1,
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Entrada de Texto e Voz
                  const SizedBox(height: 30),
                  Container(
                    constraints: const BoxConstraints(maxWidth: 500),
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _textController,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              hintText: "Fale com a TerlineT...",
                              hintStyle: TextStyle(color: Colors.white24),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(horizontal: 10),
                            ),
                            onSubmitted: (value) => _triggerAiInteraction(customText: value),
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            _isListening ? Icons.mic : Icons.mic_none,
                            color: _isListening ? Colors.redAccent : Colors.blueAccent,
                          ),
                          onPressed: _toggleListening,
                        ),
                        IconButton(
                          icon: const Icon(Icons.send, color: Colors.blueAccent),
                          onPressed: () => _triggerAiInteraction(customText: _textController.text),
                        ),
                      ],
                    ),
                  ),
                  
                  if (!_hasCamera)
                    Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.videocam_off, color: Colors.redAccent, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            "MODO MANUAL ATIVO (CÂMERA NÃO DETECTADA)",
                            style: TextStyle(
                              color: Colors.redAccent.withOpacity(0.7),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class Particle {
  double x, y, vx, vy;
  String? label;
  Particle({required this.x, required this.y, required this.vx, required this.vy, this.label});
}

class UniversePainter extends CustomPainter {
  final List<Particle> particles;
  final bool isUserLooking;

  UniversePainter({required this.particles, required this.isUserLooking});

  @override
  void paint(Canvas canvas, Size size) {
    final pointPaint = Paint()
      ..color = (isUserLooking ? Colors.blue[100]! : Colors.white).withOpacity(0.6)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.0;

    final linePaint = Paint()..strokeWidth = 0.8;
    
    for (int i = 0; i < particles.length; i++) {
      var p1 = particles[i];
      double x1 = p1.x * size.width;
      double y1 = p1.y * size.height;

      canvas.drawCircle(Offset(x1, y1), 1.2, pointPaint);
      
      for (int j = i + 1; j < particles.length; j++) {
        var p2 = particles[j];
        double x2 = p2.x * size.width;
        double y2 = p2.y * size.height;

        double dx = x1 - x2;
        double dy = y1 - y2;
        double distance = math.sqrt(dx * dx + dy * dy);

        if (distance < 100) {
          double opacity = (1.0 - distance / 100);
          linePaint.color = i % 2 == 0 
              ? (isUserLooking ? Colors.blueAccent : Colors.white).withOpacity(opacity * 0.2) 
              : Colors.blue.withOpacity(opacity * 0.25);
          canvas.drawLine(Offset(x1, y1), Offset(x2, y2), linePaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant UniversePainter oldDelegate) => true;
}
