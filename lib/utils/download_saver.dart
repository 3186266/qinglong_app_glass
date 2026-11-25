import 'dart:io';

import 'package:flutter/services.dart';
import 'package:qinglong_app/base/sp_const.dart';
import 'package:qinglong_app/utils/download_dir_utils.dart';
import 'package:qinglong_app/utils/file_picker_utils.dart';
import 'package:qinglong_app/utils/sp_utils.dart';

/// 下载结果
class SaveFileOutcome {
  /// 用户最终保存的位置（iOS 为文件 App 内的真实路径，Android 为公共目录路径）
  final String? path;

  /// 文件名
  final String? name;

  /// 用户是否在保存面板里点了取消
  final bool cancelled;

  /// 非空表示保存失败的原因
  final String? error;

  const SaveFileOutcome({
    this.path,
    this.name,
    this.cancelled = false,
    this.error,
  });

  bool get success => error == null && !cancelled && (path ?? '').isNotEmpty;
}

/// 「下载 / 导出」类操作的统一落地方式。
///
/// iOS：**必须**走系统保存面板（UIDocumentPickerViewController forExporting）。
/// 应用沙盒目录在「文件」App 里默认不可见，直接写 Documents/tmp 用户根本
/// 找不到文件——这是历史 bug 的根因。面板起始目录取上次保存的位置。
///
/// Android：仍写到公共 Download/qinglong（文件管理器可见）；
/// 若原生通道支持 SAF 则优先让用户自选，失败再回退公共目录。
class DownloadSaver {
  DownloadSaver._();

  /// 保存文本内容。
  ///
  /// [fileName] 建议文件名（用户可在面板里改）；
  /// [content] 文本内容。
  static Future<SaveFileOutcome> saveText({
    required String fileName,
    required String content,
  }) async {
    final String safeName = _sanitize(fileName);
    final String lastDir = SpUtil.getString(
      spLastSaveDirectory,
      defValue: '',
    );

    // 1. iOS / 支持 SAF 的平台：弹出系统保存面板
    if (Platform.isIOS || Platform.isAndroid) {
      try {
        final FilePickerResult? result = await FilePickerUtils.saveFile(
          fileName: safeName,
          content: content,
          initialDirectory: lastDir,
        );
        if (result == null) {
          // 用户取消（原生回 nil）
          return const SaveFileOutcome(cancelled: true);
        }
        if ((result.path ?? '').isNotEmpty) {
          _rememberDirectory(result.path!);
          return SaveFileOutcome(path: result.path, name: result.name);
        }
        return const SaveFileOutcome(cancelled: true);
      } on MissingPluginException {
        // 通道未实现（旧安装包）：iOS 无回退可用，Android 落到公共目录
        if (Platform.isIOS) {
          return const SaveFileOutcome(
            error: '当前版本不支持选择保存位置，请升级到最新版本',
          );
        }
      } on PlatformException catch (e) {
        // 原生写入失败（磁盘满 / 权限）：直接回报，让用户知道没保存成功
        return SaveFileOutcome(error: e.message ?? '保存失败');
      } catch (e) {
        return SaveFileOutcome(error: '保存失败：$e');
      }
    }

    // 2. Android 回退：公共 Download/qinglong 目录
    return _saveToAndroidPublicDir(safeName, content);
  }

  /// Android 回退路径：写公共 Download 子目录
  static Future<SaveFileOutcome> _saveToAndroidPublicDir(
    String fileName,
    String content,
  ) async {
    try {
      final Directory? dir = await resolveAndroidScriptDownloadDirectory();
      if (dir == null) {
        return const SaveFileOutcome(
          error: '无法写入下载目录，请检查存储权限',
        );
      }
      final File f = File('${dir.path}/$fileName');
      if (f.existsSync()) {
        // 同名文件加序号，避免静默覆盖用户已有文件
        final File alt = File('${dir.path}/${_withSuffix(fileName)}');
        await alt.writeAsString(content, flush: true);
        _rememberDirectory(alt.path);
        return SaveFileOutcome(path: alt.path, name: alt.path);
      }
      await f.writeAsString(content, flush: true);
      _rememberDirectory(f.path);
      return SaveFileOutcome(path: f.path, name: fileName);
    } catch (e) {
      return SaveFileOutcome(error: '保存失败：$e');
    }
  }

  /// 记住本次保存的目录，作为下次保存面板的起始位置
  static void _rememberDirectory(String filePath) {
    try {
      final int idx = filePath.lastIndexOf('/');
      if (idx <= 0) return;
      SpUtil.putString(spLastSaveDirectory, filePath.substring(0, idx));
    } catch (_) {}
  }

  /// 文件名清洗：去掉各平台不接受的字符
  static String _sanitize(String name) {
    String out = name
        .replaceAll('/', '_')
        .replaceAll('\\', '_')
        .replaceAll(':', '_')
        .replaceAll('\u0000', '')
        .trim();
    if (out.isEmpty) out = 'qinglong_export.txt';
    if (out.length > 120) out = out.substring(out.length - 120);
    return out;
  }

  /// 同名冲突时插入时间戳
  static String _withSuffix(String name) {
    final int dot = name.lastIndexOf('.');
    final String stamp = DateTime.now().millisecondsSinceEpoch.toString();
    if (dot <= 0) return '${name}_$stamp';
    return '${name.substring(0, dot)}_$stamp${name.substring(dot)}';
  }
}
