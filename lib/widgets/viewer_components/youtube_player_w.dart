import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';


import 'package:webview_flutter/webview_flutter.dart' as yt_mobile;
import 'package:webview_windows/webview_windows.dart' as yt_windows;

import '../../models/university_video.dart';

// ─────────────────────────────────────────────────────────────────────────────
// YouTube player for the university library.
//
// YouTubeEmbedView renders the official YouTube embed player inside the app's
// central viewer area using the platform's native WebView:
//   * Windows desktop  -> webview_windows (WebView2, built into Win10/11)
//   * Android / iOS    -> webview_flutter
// If the WebView fails (e.g. WebView2 runtime missing), the user gets a
// "open in browser" fallback instead of a dead player.
// ─────────────────────────────────────────────────────────────────────────────

const String _ytEmbedBase = 'https://www.youtube-nocookie.com/embed';

/// Virtual host that serves [_ytEmbedWrapperHtml] on Windows.
///
/// WebView2 maps [_ytWrapperFolderName] to the `https://` origin of
/// [_ytWrapperHost], so the player iframe is requested from a real web origin -
/// and therefore carries a `Referer` header - even though the page itself is
/// local. Loading the embed URL as a top-level navigation sends no referrer at
/// all, which is what makes YouTube answer with "Error 153 - Video player
/// configuration error".
const String _ytWrapperHost = 'studyflow.app';
const String _ytWrapperFolderName = 'yt_embed';
const String _ytWrapperFileName = 'youtube_embed.html';

/// Wrapper page hosting the YouTube iframe.
///
/// It keeps the referrer policy permissive (`strict-origin-when-cross-origin`),
/// enables the iframe player API so player errors are reported, and forwards
/// `onError` events through `window.chrome.webview.postMessage` (surfaced in
/// Dart as [yt_windows.WebviewController.webMessage]).
const String _ytEmbedWrapperHtml = r'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="referrer" content="strict-origin-when-cross-origin">
<title>YouTube</title>
<style>
  html, body { margin: 0; padding: 0; height: 100%; background: #0B1120; overflow: hidden; }
  #player { position: fixed; top: 0; left: 0; width: 100%; height: 100%; border: 0; }
</style>
</head>
<body>
<iframe id="player" title="YouTube"
        allow="autoplay; encrypted-media; fullscreen; picture-in-picture"
        allowfullscreen
        referrerpolicy="strict-origin-when-cross-origin"></iframe>
<script>
  (function () {
    var id = new URLSearchParams(window.location.search).get('v') || '';
    var origin = window.location.origin;
    document.getElementById('player').src =
      'https://www.youtube-nocookie.com/embed/' + encodeURIComponent(id) +
      '?autoplay=1&rel=0&playsinline=1&enablejsapi=1&origin=' +
      encodeURIComponent(origin);

    window.addEventListener('message', function (event) {
      var data = event.data;
      if (typeof data === 'string') {
        try { data = JSON.parse(data); } catch (err) { return; }
      }
      if (!data || typeof data !== 'object' || data.event !== 'onError') return;
      var info = data.info;
      var code = null;
      if (typeof info === 'number') {
        code = info;
      } else if (info && typeof info === 'object' &&
                 typeof info.errorCode === 'number') {
        code = info.errorCode;
      }
      try {
        window.chrome.webview.postMessage({
          source: 'youtube', event: 'onError', code: code
        });
      } catch (err) { /* not hosted inside WebView2 */ }
    });
  })();
</script>
</body>
</html>
''';

/// Injected into every document WebView2 creates (including the cross-origin
/// YouTube iframe) to keep playback inside the app: refuses clicks on links
/// that leave for YouTube, suppresses the context menu / drag-out and hides the
/// player top bar (video title link and share buttons).
const String _ytEmbedGuardScript = r'''
(function () {
  function harden() {
    document.addEventListener('contextmenu', function (e) {
      e.preventDefault();
    }, true);
    document.addEventListener('dragstart', function (e) {
      e.preventDefault();
    }, true);
    document.addEventListener('click', function (e) {
      var node = e.target;
      while (node && node.nodeType === 1) {
        var href = node.getAttribute && (node.getAttribute('href') || '');
        if (href && /youtube\.com|youtu\.be|googlevideo/i.test(href)) {
          e.preventDefault();
          e.stopPropagation();
          return;
        }
        node = node.parentNode;
      }
    }, true);
    try {
      var style = document.createElement('style');
      style.textContent =
        '.ytp-chrome-top,.ytp-gradient-top,.ytp-title,.ytp-share-button,' +
        '.ytp-watch-later-button,.ytp-youtube-button,.ytp-watermark' +
        '{display:none !important}';
      (document.head || document.documentElement).appendChild(style);
    } catch (err) {}
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', harden);
  } else {
    harden();
  }
})();
''';

const String _desktopUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

bool _useWindowsWebview() => !kIsWeb && Platform.isWindows;

/// Opens the full-screen embedded YouTube player for [video].
Future<void> showYouTubeVideoPlayer(
  BuildContext context,
  UniversityVideo video,
) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.black.withValues(alpha: 0.6),
    transitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (ctx, anim1, anim2) => FadeTransition(
      opacity: anim1,
      child: YouTubeVideoPlayerDialog(video: video),
    ),
  );
}

class YouTubeVideoPlayerDialog extends StatelessWidget {
  final UniversityVideo video;

  const YouTubeVideoPlayerDialog({super.key, required this.video});

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDarkMode
                ? const [Color(0xFF0B1120), Color(0xFF020617)]
                : const [Color(0xFF0F172A), Color(0xFF0B1120)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ── Top bar ───────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        LucideIcons.arrowLeft,
                        color: Colors.white,
                      ),
                      tooltip: 'إغلاق',
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        video.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Player ────────────────────────────────────────────────
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: _PlayerWithFallback(videoId: video.videoId),
                      ),
                    ),
                  ),
                ),
              ),

              const Padding(
                padding: EdgeInsets.only(bottom: 20),
                child: Text(
                  'يوتيوب · التشغيل متاح داخل التطبيق فقط',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows the YouTube thumbnail with a play button; tapping starts the in-app
/// WebView embed. Playback is locked to this app on purpose: no external link
/// is offered and the player chrome that could lead out of the app is covered
/// (the click shield below plus [_ytEmbedGuardScript]).
class _PlayerWithFallback extends StatefulWidget {
  final String videoId;

  const _PlayerWithFallback({required this.videoId});

  @override
  State<_PlayerWithFallback> createState() => _PlayerWithFallbackState();
}

class _PlayerWithFallbackState extends State<_PlayerWithFallback> {
  bool _started = false;

  String get _thumbUrl =>
      'https://i.ytimg.com/vi/${widget.videoId}/hqdefault.jpg';

  @override
  Widget build(BuildContext context) {
    if (_started) {
      return Stack(
        fit: StackFit.expand,
        children: [
          YouTubeEmbedView(videoId: widget.videoId),
          // Absorbs taps on YouTube's own top bar (video title link and share
          // buttons) so nothing inside the player can lead out of the app.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              onLongPress: () {},
              child: const SizedBox(height: 48),
            ),
          ),
        ],
      );
    }

    return GestureDetector(
      onTap: () => setState(() => _started = true),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            _thumbUrl,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stack) => Container(
              color: const Color(0xFF0B1120),
              child: const Center(
                child: Icon(
                  LucideIcons.youtube,
                  color: Color(0xFFEF4444),
                  size: 48,
                ),
              ),
            ),
          ),
          Container(color: Colors.black.withValues(alpha: 0.35)),
          Center(
            child: Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                LucideIcons.play,
                color: Colors.white,
                size: 34,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders the YouTube embed on the platform's native WebView.
class YouTubeEmbedView extends StatefulWidget {
  final String videoId;

  const YouTubeEmbedView({super.key, required this.videoId});

  @override
  State<YouTubeEmbedView> createState() => _YouTubeEmbedViewState();
}

class _YouTubeEmbedViewState extends State<YouTubeEmbedView> {
  yt_mobile.WebViewController? _mobileController;
  yt_windows.WebviewController? _windowsController;
  yt_windows.WebviewController? _candidate;
  StreamSubscription<yt_windows.LoadingState>? _loadingSub;
  StreamSubscription<dynamic>? _messageSub;
  bool _loading = true;
  String? _error;

  String get _embedUrl =>
      '$_ytEmbedBase/${widget.videoId}?autoplay=1&rel=0&playsinline=1';

  /// Wrapper page URL, hosted on [_ytWrapperHost] so the YouTube iframe request
  /// carries the `Referer` header YouTube now requires.
  String get _wrapperUrl =>
      'https://$_ytWrapperHost/$_ytWrapperFileName'
      '?v=${Uri.encodeQueryComponent(widget.videoId)}';


  @override
  void initState() {
    super.initState();
    if (_useWindowsWebview()) {
      _initWindowsWebview();
    } else {
      _initMobileWebview();
    }
  }

  Future<void> _initMobileWebview() async {
    try {
      final controller = yt_mobile.WebViewController()
        ..setJavaScriptMode(yt_mobile.JavaScriptMode.unrestricted)
        ..setUserAgent(_desktopUserAgent)
        ..setBackgroundColor(const Color(0xFF0B1120))
        ..setNavigationDelegate(
          yt_mobile.NavigationDelegate(
            onPageFinished: (url) {
              if (mounted && _loading) {
                setState(() => _loading = false);
              }
            },
            onWebResourceError: (error) {
              if (mounted) {
                _error = error.description;
                _loading = false;
              }
            },
          ),
        );
      await controller.loadRequest(Uri.parse(_embedUrl));
      if (!mounted) return;
      setState(() {
        _mobileController = controller;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  /// Returns the installed WebView2 Runtime version, or null when the runtime
  /// isn't installed (or the native plugin channel is unavailable).
  Future<String?> _webViewVersionSafe() async {
    try {
      return await yt_windows.WebviewController.getWebViewVersion();
    } catch (_) {
      return null;
    }
  }

  Future<void> _initWindowsWebview() async {
    _candidate = yt_windows.WebviewController();

    // WebView2 Runtime is a hard dependency on Windows. If it isn't installed,
    // the native side fails to create the WebView2 environment and throws
    // MissingPluginException / PlatformException on io.jns.webview.win — the
    // plugin's own docs tell us to check the version first and guide the user
    // to install the runtime. `getWebViewVersion()` returns null when missing.
    final webViewVersion = await _webViewVersionSafe();
    if (webViewVersion == null) {
      _initWebView2NotInstalled();
      return;
    }

    final controller = _candidate!;
    try {
      await controller.initialize();
      await controller.setPopupWindowPolicy(
        yt_windows.WebviewPopupWindowPolicy.deny,
      );
      // WebView2's default UA is rejected by the YouTube embed player, which
      // then shows "Video player configuration error". Present a desktop
      // Chrome UA so the embed initialises like a normal browser.
      try {
        await controller.setUserAgent(_desktopUserAgent);
      } catch (_) {}

      // Keeps playback inside the app: blocks links that leave for youtube.com
      // and hides YouTube's own top bar (title link / share buttons).
      try {
        await controller.addScriptToExecuteOnDocumentCreated(
          _ytEmbedGuardScript,
        );
      } catch (_) {}

      _messageSub = controller.webMessage.listen(_handleWebMessage);
      _loadingSub = controller.loadingState.listen((state) {
        if (mounted &&
            _loading &&
            state == yt_windows.LoadingState.navigationCompleted) {
          setState(() => _loading = false);
        }
      });

      // Error 153 is caused by the embed request arriving without a `Referer`
      // header, and a top-level WebView2 navigation never sends one. Loading
      // the player inside the wrapper page served from a virtual https origin
      // gives the iframe request a real referrer; when that host cannot be
      // mounted we fall back to the plain embed URL.
      final wrapperUrl = await _mountWindowsWrapper(controller);
      await controller.loadUrl(wrapperUrl ?? _embedUrl);
      if (wrapperUrl != null && !await _wrapperServed(controller)) {
        await controller.loadUrl(_embedUrl);
      }
      if (!mounted) return;
      setState(() {
        _windowsController = controller;
        _candidate = null;
        _loading = false;
      });
    } on PlatformException catch (e) {
      _fail(e.message ?? 'WebView2 غير متوفر على هذا الجهاز');
    } catch (e) {
      _fail(e.toString());
    }
  }

  /// Writes [_ytEmbedWrapperHtml] to disk and maps it to [_ytWrapperHost].
  ///
  /// Returns the URL to load, or `null` when the virtual host cannot be
  /// mounted (the caller then loads [_embedUrl] directly).
  Future<String?> _mountWindowsWrapper(
    yt_windows.WebviewController controller,
  ) async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      final folder = Directory(p.join(supportDir.path, _ytWrapperFolderName));
      await folder.create(recursive: true);
      final file = File(p.join(folder.path, _ytWrapperFileName));
      if (!await file.exists() ||
          await file.readAsString() != _ytEmbedWrapperHtml) {
        await file.writeAsString(_ytEmbedWrapperHtml, flush: true);
      }
      await controller.addVirtualHostNameMapping(
        _ytWrapperHost,
        folder.path,
        yt_windows.WebviewHostResourceAccessKind.allow,
      );
      return _wrapperUrl;
    } catch (e) {
      debugPrint('▶️ [YouTube] wrapper host unavailable: $e');
      return null;
    }
  }

  /// Confirms the wrapper document really rendered, so a broken virtual host
  /// mapping cannot leave the viewer with a blank page.
  Future<bool> _wrapperServed(yt_windows.WebviewController controller) async {
    for (var attempt = 0; attempt < 16; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      try {
        final result = await controller.executeScript(
          '!!document.getElementById("player")',
        );
        if (result == true || result?.toString().toLowerCase() == 'true') {
          return true;
        }
      } catch (_) {
        // Document not ready yet.
      }
    }
    return false;
  }

  /// Handles `onError` reports forwarded by the wrapper page, replacing a
  /// silently broken player with an actionable message.
  void _handleWebMessage(dynamic message) {
    final text = (message?.toString() ?? '').replaceAll(r'\"', '"');
    if (!RegExp(r'"source"\s*:\s*"youtube"').hasMatch(text)) return;
    debugPrint('▶️ [YouTube] player reported: $text');
    final match = RegExp(r'"code"\s*:\s*(\d+)').firstMatch(text);
    final code = int.tryParse(match?.group(1) ?? '');
    scheduleMicrotask(() => _fail(_playerErrorMessage(code)));
  }

  /// Human readable message for a YouTube IFrame API `onError` code.
  String _playerErrorMessage(int? code) {
    final suffix = code == null ? '' : ' (خطأ $code)';
    switch (code) {
      case 2:
        return 'رابط الفيديو غير صالح أو المعرّف غير صحيح.';
      case 5:
        return 'تعذّر تشغيل مشغل HTML5 لهذا الفيديو.\n'
            'يمكنك فتحه في المتصفح من الزر بالأعلى.';
      case 100:
        return 'الفيديو غير متوفر أو تم حذفه من يوتيوب.';
      case 101:
      case 150:
        return 'مالك الفيديو منع التضمين خارج يوتيوب.\n'
            'يمكنك فتحه في المتصفح من الزر بالأعلى.';
      case 153:
        return 'رفض يوتيوب تشغيل الفيديو داخل التطبيق (خطأ 153).\n'
            'يمكنك فتحه في المتصفح من الزر بالأعلى.';
      default:
        return 'تعذّر تشغيل الفيديو داخل التطبيق$suffix.\n'
            'يمكنك فتحه في المتصفح من الزر بالأعلى.';
    }
  }

  void _fail(String message) {
    _loadingSub?.cancel();
    _loadingSub = null;
    _messageSub?.cancel();
    _messageSub = null;
    _candidate?.dispose();
    _candidate = null;
    _windowsController?.dispose();
    _windowsController = null;
    if (mounted) {
      setState(() {
        _error = message;
        _loading = false;
      });
    }
  }

  /// WebView2 Runtime isn't installed (or is too old) on this Windows machine.
  /// Show a clear message instead of a raw MissingPluginException.
  void _initWebView2NotInstalled() {
    _fail(
      'مكوّن WebView2 غير مثبّت على هذا الجهاز — لا يمكن تشغيل الفيديو داخلياً.\n'
      'يمكنك تثبيت WebView2 Runtime من موقع Microsoft ثم إعادة تشغيل البرنامج.',
    );
  }


  @override
  void dispose() {
    _loadingSub?.cancel();
    _messageSub?.cancel();
    _candidate?.dispose();
    _windowsController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Container(
        color: const Color(0xFF0B1120),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.alertTriangle,
                  color: Colors.amber, size: 36),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'تعذّر تشغيل الفيديو داخل التطبيق\n$_error',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Windows WebView2 render.
    if (_useWindowsWebview()) {
      final controller = _windowsController;
      if (controller == null) {
        return _loadingBox();
      }
      return yt_windows.Webview(controller);
    }

    // Mobile / web WebView render.
    final mobileController = _mobileController;
    if (mobileController != null) {
      return yt_mobile.WebViewWidget(controller: mobileController);
    }
    return _loadingBox();
  }

  Widget _loadingBox() {
    return const ColoredBox(
      color: Color(0xFF0B1120),
      child: Center(
        child:
            CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
      ),
    );
  }
}