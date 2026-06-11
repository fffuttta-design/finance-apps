import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../data/backup_repository.dart';
import '../../../screens/settings_screen.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/v2_card.dart';

/// v2.1 ネイティブ バックアップ / 取り込み panel。
/// - 書き出し: 独自実装（BackupRepository.exportAll → JSON ファイル → 共有）
/// - 取り込み: v1 SettingsScreen を Navigator.push で開く（D&D・件数差分表示が複雑なため）
/// - 自動スナップショット履歴は v1 設定経由（次フェーズで v2.1 化）
class V2BackupPanel extends StatefulWidget {
  const V2BackupPanel({super.key});

  @override
  State<V2BackupPanel> createState() => _V2BackupPanelState();
}

class _V2BackupPanelState extends State<V2BackupPanel> {
  DateTime? _lastManualAt;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _loadLastBackup();
  }

  Future<void> _loadLastBackup() async {
    final last =
        await BackupRepository.instance.lastManualBackupAt();
    if (!mounted) return;
    setState(() => _lastManualAt = last);
  }

  Future<void> _export() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final json = await BackupRepository.instance.exportAll();
      final now = DateTime.now();
      final stamp =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}'
          '-${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
      final fileName = 'futa-finance-backup-$stamp.json';

      if (kIsWeb) {
        // Web: SharePlus.shareXFiles で blob ダウンロード
        await SharePlus.instance.share(
          ShareParams(
            files: [
              XFile.fromData(
                // ★UTF-8 でエンコード（json.codeUnits は日本語が下位バイトに
                //   切り詰められて文字化けするバグだった）。
                Uint8List.fromList(utf8.encode(json)),
                name: fileName,
                mimeType: 'application/json; charset=utf-8',
              ),
            ],
            subject: 'FutaFinance バックアップ ($stamp)',
          ),
        );
      } else {
        // モバイル: 一時ファイル経由で共有
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/$fileName');
        await file.writeAsString(json);
        await SharePlus.instance.share(
          ShareParams(
            files: [
              XFile(file.path, mimeType: 'application/json')
            ],
            subject: 'FutaFinance バックアップ ($stamp)',
            text: 'FutaFinance のデータバックアップ ($stamp)。\n'
                '保存先推奨: マイドライブ/ツール開発/FutaFinance/backups/',
          ),
        );
      }
      await BackupRepository.instance.markManualBackupDone();
      await _loadLastBackup();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('書き出しに失敗しました: $e')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _openImportV1() async {
    // 取り込みは v1 SettingsScreen 内に組み込まれてる（D&D / 結果差分表示が複雑）
    // フルスクリーンで v1 設定を開いて、ユーザーが「データ管理 → バックアップを取り込む」を選ぶ
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    if (mounted) await _loadLastBackup();
  }

  String _lastBackupText() {
    final last = _lastManualAt;
    if (last == null) return 'まだ手動バックアップしていません';
    final now = DateTime.now();
    final days = now.difference(last).inDays;
    final stamp =
        '${last.year}/${last.month}/${last.day} ${last.hour.toString().padLeft(2, '0')}:${last.minute.toString().padLeft(2, '0')}';
    if (days == 0) return '今日 ($stamp)';
    if (days == 1) return '昨日 ($stamp)';
    return '$days 日前 ($stamp)';
  }

  Color _lastBackupColor() {
    final last = _lastManualAt;
    if (last == null) return V2Colors.warning;
    final days = DateTime.now().difference(last).inDays;
    if (days >= 14) return V2Colors.warning;
    return V2Colors.positive;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              V2Spacing.sm, 0, V2Spacing.sm, V2Spacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('バックアップ / 取り込み',
                  style: V2Typography.h1),
              const SizedBox(height: V2Spacing.xs),
              Text(
                'データを JSON で書き出し / 取り込みします。Drive 等に保存して安全に保管。',
                style: V2Typography.caption.copyWith(
                    color: V2Colors.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: V2Spacing.sm),
        Expanded(
          child: SingleChildScrollView(
          primary: false,
            padding: const EdgeInsets.only(bottom: V2Spacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── 最終バックアップ表示 ──
                V2Card(
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: _lastBackupColor()
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(
                              V2Spacing.radiusSm),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                            _lastManualAt == null
                                ? Icons.warning_amber
                                : Icons.check_circle_outline,
                            size: 18,
                            color: _lastBackupColor()),
                      ),
                      const SizedBox(width: V2Spacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text('最終手動バックアップ',
                                style: V2Typography.caption
                                    .copyWith(
                                        color: V2Colors
                                            .textSecondary,
                                        fontWeight:
                                            FontWeight.w600)),
                            Text(_lastBackupText(),
                                style: V2Typography.bodyStrong
                                    .copyWith(
                                        color: _lastBackupColor(),
                                        fontFeatures:
                                            V2Typography
                                                .tabularNums)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: V2Spacing.lg),
                // ── 書き出し ──
                V2Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: V2Colors.badgeGreenSoft,
                              borderRadius:
                                  BorderRadius.circular(
                                      V2Spacing.radiusSm),
                            ),
                            alignment: Alignment.center,
                            child: const Icon(
                                Icons.cloud_upload_outlined,
                                size: 16,
                                color: V2Colors.positive),
                          ),
                          const SizedBox(width: V2Spacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text('バックアップを書き出す',
                                    style: V2Typography
                                        .bodyStrong),
                                Text(
                                    '全データを 1 つの JSON ファイルにして共有シートで保存（Drive 推奨）',
                                    style: V2Typography.micro
                                        .copyWith(
                                            color: V2Colors
                                                .textSecondary)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: V2Spacing.md),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed:
                              _exporting ? null : _export,
                          icon: _exporting
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child:
                                      CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white),
                                )
                              : const Icon(Icons.cloud_upload,
                                  size: 14),
                          label: Text(_exporting
                              ? '書き出し中...'
                              : '書き出す'),
                          style: FilledButton.styleFrom(
                            backgroundColor: V2Colors.positive,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: V2Spacing.lg),
                // ── 取り込み ──
                V2Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: V2Colors.badgeBlueSoft,
                              borderRadius:
                                  BorderRadius.circular(
                                      V2Spacing.radiusSm),
                            ),
                            alignment: Alignment.center,
                            child: const Icon(
                                Icons.cloud_download_outlined,
                                size: 16,
                                color: V2Colors.badgeBlue),
                          ),
                          const SizedBox(width: V2Spacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text('バックアップを取り込む',
                                    style: V2Typography
                                        .bodyStrong),
                                Text(
                                    'JSON ファイルからデータを復元。Web ではドラッグ&ドロップにも対応',
                                    style: V2Typography.micro
                                        .copyWith(
                                            color: V2Colors
                                                .textSecondary)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: V2Spacing.md),
                      Container(
                        padding: const EdgeInsets.all(
                            V2Spacing.md),
                        decoration: BoxDecoration(
                          color: V2Colors.warningSoft
                              .withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(
                              V2Spacing.radiusSm),
                          border: Border.all(
                              color: V2Colors.warning
                                  .withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline,
                                size: 14,
                                color: V2Colors.warning),
                            const SizedBox(width: V2Spacing.sm),
                            Expanded(
                              child: Text(
                                '取り込み前に自動でスナップショットを取得します。失敗時は復元可能。',
                                style: V2Typography.micro
                                    .copyWith(
                                        color: V2Colors
                                            .textPrimary),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: V2Spacing.md),
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                          onPressed: _openImportV1,
                          icon: const Icon(Icons.open_in_new,
                              size: 14),
                          label: const Text('取り込み画面を開く'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: V2Spacing.lg),
                // ── 自動スナップショット ──
                V2Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: V2Colors.badgePurpleSoft,
                              borderRadius:
                                  BorderRadius.circular(
                                      V2Spacing.radiusSm),
                            ),
                            alignment: Alignment.center,
                            child: const Icon(
                                Icons.history,
                                size: 16,
                                color: V2Colors.badgePurple),
                          ),
                          const SizedBox(width: V2Spacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text('自動スナップショット',
                                    style: V2Typography
                                        .bodyStrong),
                                Text(
                                    '取り込み/破壊的操作の前に自動取得した履歴を確認・復元できます',
                                    style: V2Typography.micro
                                        .copyWith(
                                            color: V2Colors
                                                .textSecondary)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: V2Spacing.md),
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                          onPressed: _openImportV1,
                          icon: const Icon(Icons.open_in_new,
                              size: 14),
                          label: const Text('履歴を開く（v1 設定）'),
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
    );
  }
}
