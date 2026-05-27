import 'package:flutter/material.dart';

/// ブランドロゴ画像を表示するウィジェット。
///
/// - URL指定があれば NetworkImage で表示（読込中/失敗時は fallback）
/// - URLなし or 失敗時は emoji/icon フォールバック
class BrandLogo extends StatelessWidget {
  final String? iconUrl;
  final String? fallbackEmoji;
  final IconData? fallbackIcon;
  final Color fallbackBgColor;
  final Color fallbackFgColor;
  final double size;
  final double borderRadius;

  const BrandLogo({
    super.key,
    this.iconUrl,
    this.fallbackEmoji,
    this.fallbackIcon,
    this.fallbackBgColor = const Color(0xFFF3F4F6),
    this.fallbackFgColor = const Color(0xFF6B7280),
    this.size = 32,
    this.borderRadius = 6,
  });

  @override
  Widget build(BuildContext context) {
    final url = iconUrl?.trim();
    if (url == null || url.isEmpty) {
      return _fallback();
    }
    // DPR(devicePixelRatio) を考慮して、物理ピクセル基準で必要十分な
    // 解像度だけデコードする。これにより：
    // - 画質劣化なし（実際の描画pixel = size * DPR まではフル解像度）
    // - メモリ節約（元画像が巨大でも 物理pixel 以上はデコードしない）
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cachePx = (size * dpr).ceil();

    // 画像のアスペクト比に関わらず常に正方形（size x size）で表示する。
    // 縦横比が異なる画像は中央でクロップ（BoxFit.cover）。背景色も敷いて
    // 透過PNG / 余白多めのfaviconでも統一感が出るようにする。
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fallbackBgColor,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      clipBehavior: Clip.hardEdge,
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: cachePx,
        cacheHeight: cachePx,
        errorBuilder: (context, error, stack) => _fallback(),
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return SizedBox(
            width: size,
            height: size,
            child: const Center(
              child: SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.5),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _fallback() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fallbackBgColor,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      alignment: Alignment.center,
      child: fallbackEmoji != null
          ? Text(fallbackEmoji!, style: TextStyle(fontSize: size * 0.6))
          : Icon(fallbackIcon ?? Icons.business,
              size: size * 0.6, color: fallbackFgColor),
    );
  }
}

/// ドメインから Google Favicon API のURLを生成する。
/// 例: "smbc-card.com" → "https://www.google.com/s2/favicons?domain=smbc-card.com&sz=128"
/// URLが渡された場合はホスト名を抽出。
String? domainToFaviconUrl(String input) {
  var s = input.trim();
  if (s.isEmpty) return null;
  // 完全URLからホスト抽出
  if (s.startsWith('http://') || s.startsWith('https://')) {
    try {
      final host = Uri.parse(s).host;
      if (host.isNotEmpty) s = host;
    } catch (_) {}
  }
  // 「www.」は付けたままでもOK
  return 'https://www.google.com/s2/favicons?domain=$s&sz=128';
}
