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
  dynamic _hands; // MediaPipe Hands
  Timer? _detectionTimer;
  String _aiMessage = "Iniciando protocolos de inteligência...";
  bool _isAiTalking = false;
  bool _isProcessing = false; // API interaction processing
  bool _isFaceProcessing = false; // MediaPipe Face processing
  bool _isHandsProcessing = false; // MediaPipe Hands processing
  bool _faceIaAborted = false; // Detecta se o motor travou
  bool _handsIaAborted = false; // Detecta se o motor travou
  bool _hasCamera = true;
  bool _isIaReady = false;
  List<List<Offset>> _detectedFaces = [];
  String? _duelGifBase64;
  bool _isLoadingDuel = false;
  String? _currentImageUrl; // Armazena a imagem atual da explicação

  // Variáveis do Sabre de Luz
  Offset _handPos = const Offset(0.5, 0.9); // Posição inicial no fundo
  double _saberAngle = 0.0;
  bool _isHandVisible = true; // Sempre visível agora
  bool _isHandDetected = false; // Rastreia se a mão real foi detectada
  bool _firstInteractionDone = false;

  // Controllers para entrada do usuário
  final TextEditingController _textController = TextEditingController();
  dynamic _recognition; // SpeechRecognition
  bool _isListening = false;

  // Configuração do Servidor Hugging Face Exclusivo (URL Corrigida para hifens)
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
    _initHandsIA(); // Inicializa rastreio de mãos
    _startCamera();
    _initSpeechRecognition();
    _loadDuelAnimation(); // Carrega a luta de Padawans

    // Testa a conexão ao iniciar
    _checkServerStatus();
  }

  Future<void> _checkServerStatus() async {
    try {
      // Chama o fetch do JS diretamente para evitar erro de tipo no Dart
      final promise = js_util.callMethod(html.window, 'fetch', [
        "https://tertulianoshow-terlinet-universe.hf.space/",
        js_util.jsify({'method': 'GET'})
      ]);
      final dynamic response = await js_util.promiseToFuture(promise);
      final bool ok = js_util.getProperty(response, 'ok') ?? false;
      if (ok) {
        print("Conexão com servidor TerlineT estabelecida com sucesso.");
      }
    } catch (e) {
      print("Aviso: Servidor pode estar iniciando ou bloqueado por CORS.");
    }
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
          
          if (mounted) {
            setState(() {
              _textController.text = transcript;
              _isListening = false;
            });
            _triggerAiInteraction(customText: transcript);
          }
        }));

        js_util.setProperty(_recognition, 'onerror', allowInterop((error) {
          if (mounted) setState(() => _isListening = false);
        }));

        js_util.setProperty(_recognition, 'onend', allowInterop((_) {
          if (mounted) setState(() => _isListening = false);
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

  void _initHandsIA() {
    try {
      final handsClass = js_util.getProperty(html.window, 'Hands');
      if (handsClass == null) return;

      final options = js_util.newObject();
      js_util.setProperty(options, 'locateFile', allowInterop((file, base) =>
        'https://cdn.jsdelivr.net/npm/@mediapipe/hands@0.4/$file'));

      _hands = js_util.callConstructor(handsClass, [options]);

      js_util.setProperty(_hands, 'onError', allowInterop((err) {
        print("MediaPipe Hands error: $err");
        _handsIaAborted = true;
      }));

      js_util.callMethod(_hands, 'setOptions', [
        js_util.jsify({
          'maxNumHands': 1,
          'modelComplexity': 1,
          'minDetectionConfidence': 0.5,
          'minTrackingConfidence': 0.5
        })
      ]);

      js_util.callMethod(_hands, 'onResults', [
        allowInterop((results) {
          if (!mounted || results == null) return;
          final multiHandLandmarks = js_util.getProperty(results, 'multiHandLandmarks');

          if (multiHandLandmarks != null && js_util.getProperty(multiHandLandmarks, 'length') > 0) {
            final landmarks = js_util.getProperty(multiHandLandmarks, 0);

            // Pega o pulso (0) e o dedo médio (12) para calcular ângulo e posição
            final wrist = js_util.getProperty(landmarks, 0);
            final middleFinger = js_util.getProperty(landmarks, 12);

            if (mounted) {
              setState(() {
                _isHandDetected = true;
                _handPos = Offset(
                  js_util.getProperty(wrist, 'x'),
                  js_util.getProperty(wrist, 'y')
                );

                // Calcula ângulo do sabre baseado na inclinação da mão
                double dx = js_util.getProperty(middleFinger, 'x') - js_util.getProperty(wrist, 'x');
                double dy = js_util.getProperty(middleFinger, 'y') - js_util.getProperty(wrist, 'y');
                _saberAngle = math.atan2(dy, dx) + (math.pi / 2);
              });
            }
          } else {
            if (mounted && _isHandDetected) {
              setState(() {
                _isHandDetected = false;
                // Mantém o sabre visível na posição padrão quando a mão some
                _handPos = const Offset(0.5, 0.9);
                _saberAngle = 0.0;
              });
            }
          }
        })
      ]);
    } catch (e) {
      print('Erro ao iniciar IA de mãos: $e');
    }
  }

  void _initFaceIA({int attempt = 0}) {
    if (_faceDetection != null) return;

    try {
      final faceClass = js_util.getProperty(html.window, 'FaceDetection');
      if (faceClass == null) {
        if (attempt < 20) { // Tenta por ~10 segundos
          Future.delayed(const Duration(milliseconds: 500), () => _initFaceIA(attempt: attempt + 1));
        } else {
          print("FaceDetection não disponível após várias tentativas.");
          if (mounted) {
            setState(() {
              _aiMessage = "Sensor facial indisponível. Use texto/voz.";
              _hasCamera = false;
            });
          }
        }
        return;
      }

      final options = js_util.newObject();
      js_util.setProperty(options, 'locateFile', allowInterop((file, base) {
        return 'https://cdn.jsdelivr.net/npm/@mediapipe/face_detection@0.4/$file';
      }));
      
      _faceDetection = js_util.callConstructor(faceClass, [options]);
      
      // Tratamento de erros do MediaPipe
      js_util.setProperty(_faceDetection, 'onError', allowInterop((err) {
        print("MediaPipe FaceDetection error: $err");
        if (mounted) setState(() => _hasCamera = false);
      }));

      js_util.callMethod(_faceDetection, 'setOptions', [
        js_util.jsify({
          'model': 'short',
          'minDetectionConfidence': 0.6
        })
      ]);

      js_util.callMethod(_faceDetection, 'onResults', [
        allowInterop((results) {
          if (!mounted || results == null) return;

          try {
            final detections = js_util.getProperty(results, 'detections');
            if (detections == null) {
              if (mounted) setState(() { _detectedFaces = []; _isUserLooking = false; });
              return;
            }
            
            final int len = js_util.getProperty(detections, 'length') ?? 0;
            bool found = len > 0;

            List<List<Offset>> allFaces = [];
            for (int d = 0; d < len; d++) {
              final detection = js_util.getProperty(detections, d);
              if (detection != null) {
                final locationData = js_util.getProperty(detection, 'locationData');
                if (locationData != null) {
                  final keypoints = js_util.getProperty(locationData, 'relativeKeypoints');
                  if (keypoints != null) {
                    List<Offset> facePoints = [];
                    final int kpLen = js_util.getProperty(keypoints, 'length') ?? 0;
                    for (int i = 0; i < kpLen; i++) {
                      final kp = js_util.getProperty(keypoints, i);
                      if (kp != null) {
                        try {
                          double? x = js_util.getProperty(kp, 'x')?.toDouble();
                          double? y = js_util.getProperty(kp, 'y')?.toDouble();
                          if (x != null && y != null) {
                            facePoints.add(Offset(x, y));
                          }
                        } catch (_) {}
                      }
                    }
                    allFaces.add(facePoints);
                  }
                }
              }
            }

            if (mounted) {
              setState(() {
                _detectedFaces = allFaces;
                _isIaReady = true;
                if (found != _isUserLooking) {
                  _isUserLooking = found;
                  if (_isUserLooking && !_isProcessing) {
                    _triggerAiInteraction();
                  }
                }
              });
            }
          } catch (e) {
            // Silencia erros de processamento de frame
          }
        })
      ]);
    } catch (e) {
      print('Erro ao iniciar IA: $e');
      Future.delayed(const Duration(seconds: 2), () => _initFaceIA(attempt: attempt + 1));
    }
  }

  Future<void> _startCamera() async {
    try {
      final stream = await html.window.navigator.mediaDevices!.getUserMedia({'video': true});
      _cameraVideoElement
        ..srcObject = stream
        ..autoplay = true
        ..muted = true;

      // Espera um pouco mais para a câmera estabilizar
      await Future.delayed(const Duration(milliseconds: 500));

      _detectionTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) async {
        if (!mounted) return;

        if (_cameraVideoElement.readyState >= 2) {
          final imageSource = js_util.jsify({'image': _cameraVideoElement});

          // Envia para Face Detection (com trava para evitar memory access out of bounds)
          if (_faceDetection != null && !_isFaceProcessing && !_faceIaAborted) {
            _isFaceProcessing = true;
            try {
              final promise = js_util.callMethod(_faceDetection, 'send', [imageSource]);
              if (promise != null) {
                await js_util.promiseToFuture(promise);
              }
            } catch (e) {
              print("Erro Face send (Motor possivelmente abortado): $e");
              if (e.toString().contains("Aborted") || e.toString().contains("out of bounds")) {
                _faceIaAborted = true;
              }
            } finally {
              _isFaceProcessing = false;
            }
          }

          // Envia para Hand Tracking (com trava independente)
          if (_hands != null && !_isHandsProcessing && !_handsIaAborted) {
            _isHandsProcessing = true;
            try {
              final promise = js_util.callMethod(_hands, 'send', [imageSource]);
              if (promise != null) {
                await js_util.promiseToFuture(promise);
              }
            } catch (e) {
              print("Erro Hands send (Motor possivelmente abortado): $e");
              if (e.toString().contains("Aborted") || e.toString().contains("out of bounds")) {
                _handsIaAborted = true;
              }
            } finally {
              _isHandsProcessing = false;
            }
          }
        }
      });
      if (mounted) setState(() => _hasCamera = true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasCamera = false;
          _aiMessage = "Sensor visual desativado. Interaja via texto ou voz.";
        });
      }
    }
  }

  Future<void> _loadDuelAnimation() async {
    setState(() => _isLoadingDuel = true);
    try {
      final promise = js_util.callMethod(html.window, 'fetch', [
        "https://tertulianoshow-terlinet-universe.hf.space/generate_duel",
        js_util.jsify({'method': 'GET'})
      ]);
      final dynamic response = await js_util.promiseToFuture(promise);
      final String responseText = await js_util.promiseToFuture(js_util.callMethod(response, 'text', []));
      final Map<String, dynamic> data = jsonDecode(responseText);

      if (mounted) {
        setState(() {
          _duelGifBase64 = data['gif'];
          _isLoadingDuel = false;
        });
      }
    } catch (e) {
      print("Erro ao carregar duelo: $e");
      if (mounted) setState(() => _isLoadingDuel = false);
    }
  }

  // Chamada Real para o seu Servidor no Hugging Face
  Future<void> _triggerAiInteraction({String? customText}) async {
    if (_isProcessing) return;
    
    String prompt = customText ?? "Olá TerlineT, acabei de olhar para você. Me dê as boas vindas ao seu universo e pergunte como pode me ajudar.";

    // Se for a primeira interação, injeta a instrução do Sabre de Luz
    if (!_firstInteractionDone && customText == null) {
      prompt = "Olá TerlineT, acabei de olhar para você pela primeira vez. Me dê as boas vindas. "
               "Além disso, percebi um sabre de luz vermelho flutuando aqui embaixo. "
               "Faça uma brincadeira me desafiando a usar minha 'Força Jedi' para levantá-lo e controlá-lo.";
      _firstInteractionDone = true;
    }

    if (mounted) {
      setState(() {
        _isProcessing = true;
        _isAiTalking = true;
        _aiMessage = "Conectando ao núcleo neural...";
      });
    }

    try {
      // Usa js_util para chamar o window.fetch REAL do navegador
      // Isso evita o erro de LegacyJavaScriptObject
      final promise = js_util.callMethod(html.window, 'fetch', [
        _apiUrl,
        js_util.jsify({
          'method': 'POST',
          'headers': {
            'Content-Type': 'application/json',
          },
          'body': jsonEncode({
            'text': prompt,
            'is_agent': false,
          }),
        })
      ]);

      final dynamic response = await js_util.promiseToFuture(promise);

      final bool ok = js_util.getProperty(response, 'ok') ?? false;
      if (!ok) {
        final int status = js_util.getProperty(response, 'status') ?? 0;
        throw Exception("Erro no servidor: $status");
      }

      // Lê o texto da resposta via JS
      final String responseText = await js_util.promiseToFuture(
        js_util.callMethod(response, 'text', [])
      );

      final Map<String, dynamic> data = jsonDecode(responseText);
      final String textResponse = data['text'] ?? "Sem resposta do núcleo.";
      final String? audioBase64 = data['audio'];
      final String? imageUrl = data['image_url'];

      if (mounted) {
        setState(() {
          _aiMessage = textResponse;
          _currentImageUrl = imageUrl;
          _isProcessing = false;
          _textController.clear();
        });
      }

      if (audioBase64 != null) {
        _playAiVoice(audioBase64);
      }
    } catch (e) {
      print("DETALHE DO ERRO DE CONEXÃO: $e");
      if (mounted) {
        setState(() {
          _aiMessage = "Sincronização pendente. Verifique a conexão com o servidor.";
          _isProcessing = false;
        });
      }
    }
  }

  void _playAiVoice(String base64Audio) {
    try {
      final uri = 'data:audio/mp3;base64,$base64Audio';
      final audio = html.AudioElement(uri);

      // Captura a promessa do play() para evitar erro no console
      final dynamic playPromise = js_util.callMethod(audio, 'play', []);

      if (playPromise != null) {
        js_util.promiseToFuture(playPromise).catchError((e) {
          print("Navegador bloqueou áudio automático. Clique na tela para liberar.");
          // Se falhou, podemos tentar novamente após um clique global
        });
      }
    } catch (e) {
      print("Erro ao processar áudio: $e");
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

          // HUD de Visão de IA (Canto superior) - Mostra apenas os pontos de detecção
          Positioned(
            left: 30,
            top: 30,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 150,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Stack(
                      children: [
                        if (_duelGifBase64 != null)
                          Image.memory(
                            base64Decode(_duelGifBase64!),
                            fit: BoxFit.contain,
                            width: 150,
                            height: 120,
                          )
                        else
                          const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        Container(
                          padding: const EdgeInsets.all(4),
                          color: Colors.black26,
                          child: const Text(
                            "HOLOGRAMA: SETOR 7",
                            style: TextStyle(color: Colors.blueAccent, fontSize: 7, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: _loadDuelAnimation,
                  child: Text(
                    "REINICIAR SIMULAÇÃO",
                    style: TextStyle(color: Colors.blueAccent.withOpacity(0.5), fontSize: 8, decoration: TextDecoration.underline),
                  ),
                ),
              ],
            ),
          ),

          // VISÃO DE IA EM TELA CHEIA (Efeito Espelho)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: FaceAnalysisPainter(
                  faces: _detectedFaces,
                  isActive: _isIaReady,
                ),
              ),
            ),
          ),

          // HUD de Status (Canto superior direito)
          Positioned(
            right: 30,
            top: 30,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (_isUserLooking)
                  const Text(
                    "SISTEMAS CONECTADOS",
                    style: TextStyle(
                      color: Colors.blueAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2.0,
                    ),
                  )
                else
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _faceIaAborted = false;
                        _handsIaAborted = false;
                      });
                      _initFaceIA();
                      _initHandsIA();
                      _startCamera();
                    },
                    child: Text(
                      _isIaReady ? "AGUARDANDO USUÁRIO" : "SINCRONIZAR SENSOR",
                      style: TextStyle(
                        color: _isIaReady ? Colors.white24 : Colors.orangeAccent,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                        decoration: _isIaReady ? null : TextDecoration.underline,
                      ),
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

                  // SABRE DE LUZ INTERATIVO (Agora ancorado abaixo do logo)
                  const SizedBox(height: 30),
                  SizedBox(
                    width: 400,
                    height: 60,
                    child: CustomPaint(
                      painter: LightsaberPainter(
                        pos: _isHandDetected ? _handPos : const Offset(0.5, 0.5),
                        angle: _isHandDetected ? _saberAngle : math.pi / 2,
                        isFixed: !_isHandDetected,
                      ),
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
                        if (_currentImageUrl != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                                ),
                                child: Image.network(
                                  _currentImageUrl!,
                                  height: 200,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      height: 200,
                                      color: Colors.blue.withOpacity(0.05),
                                      child: const Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.wallpaper, color: Colors.blueAccent, size: 40),
                                          SizedBox(height: 8),
                                          Text(
                                            "PROJETANDO HOLOGRAMA...",
                                            style: TextStyle(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                  loadingBuilder: (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return const SizedBox(
                                      height: 200,
                                      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                    );
                                  },
                                ),
                              ),
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

          // Remover o sabre flutuante que bloqueava a tela
        ],
      ),
    );
  }
}

class LightsaberPainter extends CustomPainter {
  final Offset pos;
  final double angle;
  final bool isFixed;

  LightsaberPainter({required this.pos, required this.angle, required this.isFixed});

  @override
  void paint(Canvas canvas, Size size) {
    double x, y;

    if (isFixed) {
      x = size.width / 2;
      y = size.height / 2;
    } else {
      // Quando interativo, permite um leve deslocamento dentro da área
      x = (1.0 - pos.dx) * size.width;
      y = pos.dy * size.height;
    }

    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(angle);

    // Ajuste matemático para centralizar o objeto inteiro no eixo de rotação
    const double bladeLength = 220.0;
    const double hiltLength = 35.0;
    // (bladeLength - hiltLength) / 2 centraliza o sabre horizontalmente
    const double verticalBalance = (bladeLength - hiltLength) / 2;
    canvas.translate(0, verticalBalance);

    // Cabo do Sabre (Metalizado com detalhe de botão)
    final hiltPaint = Paint()..color = const Color(0xFF888888);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(-6, 0, 12, hiltLength), const Radius.circular(3)),
      hiltPaint
    );
    canvas.drawCircle(const Offset(0, 10), 3, Paint()..color = Colors.redAccent);

    // Lâmina do Sabre (Efeito Neon Realista)
    final color = Colors.redAccent;
    final bladeRect = const Rect.fromLTWH(-4, -bladeLength, 8, bladeLength);

    // Camadas de Brilho (Glow)
    for (int i = 15; i > 0; i -= 3) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(bladeRect, const Radius.circular(8)),
        Paint()
          ..color = color.withOpacity(0.5 / i)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, i.toDouble()),
      );
    }

    // Núcleo da Lâmina (Branco)
    canvas.drawRRect(
      RRect.fromRectAndRadius(bladeRect, const Radius.circular(8)),
      Paint()..color = Colors.white,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant LightsaberPainter oldDelegate) => true;
}

class Particle {
  double x, y, vx, vy;
  String? label;
  Particle({required this.x, required this.y, required this.vx, required this.vy, this.label});
}

class _PulseAnimation extends StatefulWidget {
  final Color color;
  const _PulseAnimation({required this.color});

  @override
  State<_PulseAnimation> createState() => _PulseAnimationState();
}

class _PulseAnimationState extends State<_PulseAnimation> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Container(
          width: 80 * _pulseController.value,
          height: 80 * _pulseController.value,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: widget.color.withOpacity(1.0 - _pulseController.value),
              width: 2,
            ),
          ),
        );
      },
    );
  }
}

class FaceAnalysisPainter extends CustomPainter {
  final List<List<Offset>> faces;
  final bool isActive;

  FaceAnalysisPainter({required this.faces, required this.isActive});

  @override
  void paint(Canvas canvas, Size size) {
    if (faces.isEmpty) return;

    final paint = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    final linePaint = Paint()
      ..color = Colors.greenAccent.withOpacity(0.5)
      ..strokeWidth = 1.2;

    for (var points in faces) {
      // Converte pontos relativos para coordenadas do widget (Efeito Espelho)
      List<Offset> canvasPoints = points.map((p) => Offset(
        (1 - p.dx) * size.width,
        p.dy * size.height
      )).toList();

      // Desenha as linhas de conexão (Malha de análise digital verde)
      for (int i = 0; i < canvasPoints.length; i++) {
        for (int j = i + 1; j < canvasPoints.length; j++) {
          canvas.drawLine(canvasPoints[i], canvasPoints[j], linePaint);
        }
      }

      // Desenha os pontos (Keypoints biométricos verdes)
      for (var point in canvasPoints) {
        // Ponto central sólido
        canvas.drawCircle(point, 6, paint);
        // Aura de brilho verde
        canvas.drawCircle(point, 12, Paint()
          ..color = Colors.greenAccent.withOpacity(0.2)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
      }
    }
  }

  @override
  bool shouldRepaint(covariant FaceAnalysisPainter oldDelegate) => true;
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
