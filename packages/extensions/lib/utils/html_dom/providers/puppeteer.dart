import 'dart:io';
import 'package:puppeteer/protocol/network.dart';
import 'package:puppeteer/puppeteer.dart';
import '../html_dom.dart';

class PuppeteerProvider extends HtmlDOMProvider {
  late Browser browser;
  Page? page;
  String? chromiumPath;

  @override
  Future<void> initialize() async {
    final List<String?> chromiumPaths = <String?>[
      ...await PuppeteerProvider.getChromiumPaths(),
      null,
    ];

    for (final String? x in chromiumPaths) {
      try {
        await _launch(x);
        break;
      } catch (_) {}
    }

    ready = true;
  }

  Future<void> _launch(final String? executablePath) async {
    browser = await puppeteer.launch(
      executablePath: executablePath,
    );

    chromiumPath = executablePath;
  }

  @override
  Future<HtmlDOMTab> create() async {
    Page? page = await browser.newPage();

    return HtmlDOMTab(
      HtmlDOMTabImpl(
        open: (final String url) async {
          await page!.goto(url);
        },
        evalJavascript: (final String code) => page!.evaluate(code),
        getHtml: () async {
          final dynamic result =
              page!.evaluate('() => document.documentElement.outerHTML');
          return result is String ? result : null;
        },
        getCookies: (final String url) async {
          final Uri uri = Uri.parse(url);
          final String domain = uri.authority;
          final List<Cookie> cookies = await page!.cookies();

          return cookies
              .where((final Cookie x) => x.domain == domain)
              .toList()
              .asMap()
              .map(
                (final int i, final Cookie x) =>
                    MapEntry<String, String>(x.name, x.value),
              );
        },
        deleteCookie: (final String url, final String name) async {
          final Uri uri = Uri.parse(url);
          final String domain = uri.authority;
          final List<Cookie> cookies = await page!.cookies();

          await Future.wait(
            cookies.where((final Cookie x) => x.domain == domain).toList().map(
                  (final Cookie x) => page!.deleteCookie(
                    x.name,
                    domain: domain,
                  ),
                ),
          );
        },
        clearAllCookies: () async {
          await Future.wait(
            (await page!.cookies())
                .map((final Cookie x) => page!.deleteCookie(x.name)),
          );
        },
        dispose: () async {
          await page?.close();
          page = null;
        },
      ),
    );
  }

  @override
  Future<void> dispose() async {
    await Future.wait((await browser.pages).map((final Page x) => x.close()));

    await browser.close();
  }

  bool get isUsingInbuiltBrowser => chromiumPath != null;

  static const List<String> regKeys = <String>[
    r'HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\App Paths',
    r'HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\App Paths',
  ];

  static final RegExp chromiumAppMatcher =
      RegExp(r'\(Default\)\s+REG_SZ\s+(.*?\\(chrome|msedge)\.exe)');

  static bool isSupported() =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  static Future<List<String>> getChromiumPaths() async {
    final List<String> chromiumPaths = <String>[];

    for (final String regKey in regKeys) {
      final ProcessResult result = await Process.run(
        'REG',
        <String>['QUERY', regKey, '/s'],
        runInShell: true,
      );

      chromiumPaths.addAll(
        chromiumAppMatcher
            .allMatches(result.stdout.toString())
            .map((final RegExpMatch x) => x.group(1)!),
      );
    }

    return chromiumPaths;
  }
}
