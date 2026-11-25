import 'package:flutter/services.dart';

class FilePickerResult {
  final String? path;
  final String? name;

  FilePickerResult({this.path, this.name});
}

class FilePickerUtils {
  static const MethodChannel _channel = MethodChannel(
    'com.qlapp.qinglong_app/file_picker',
  );

  static Future<FilePickerResult?> pickFile() async {
    try {
      final result = await _channel.invokeMethod('pickFile');
      if (result != null && result is Map) {
        return FilePickerResult(
          path: result['path'] as String?,
          name: result['name'] as String?,
        );
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// 一次选择多个文件（脚本管理 → 上传脚本）
  ///
  /// 原生 pickFiles 未实现（旧安装包/其它平台）时自动退化为单选，
  /// 至少保证「传一个」可用，不会因为通道不支持而完全不能上传。
  static Future<List<FilePickerResult>> pickFiles() async {
    try {
      final result = await _channel.invokeMethod('pickFiles');
      if (result is List) {
        return result
            .whereType<Map>()
            .map(
              (e) => FilePickerResult(
                path: e['path'] as String?,
                name: e['name'] as String?,
              ),
            )
            .where((e) => e.path != null && e.path!.isNotEmpty)
            .toList();
      }
      if (result is Map) {
        return [
          FilePickerResult(
            path: result['path'] as String?,
            name: result['name'] as String?,
          ),
        ];
      }
      return const [];
    } catch (_) {
      final one = await pickFile();
      return one == null ? const [] : [one];
    }
  }

  /// 让用户自己选择保存位置并写入文件（系统「存储/文件」面板）。
  ///
  /// 这是 iOS 上唯一能让文件真正出现在「文件」App 里的方式：
  /// 应用沙盒目录默认对用户不可见，写进去在文件管理器里根本找不到。
  ///
  /// [fileName] 建议的文件名（面板里可改）；
  /// [initialDirectory] 上次保存的目录（iOS 用它作为起始位置，
  /// 让用户不用每次重新导航）。
  ///
  /// 返回保存后的可读路径；用户取消返回 `null`；
  /// 通道不支持时抛 [MissingPluginException]，调用方自行回退。
  static Future<FilePickerResult?> saveFile({
    required String fileName,
    required String content,
    String? initialDirectory,
  }) async {
    final result = await _channel.invokeMethod<dynamic>('saveFile', {
      'fileName': fileName,
      'content': content,
      'initialDirectory': initialDirectory ?? '',
    });
    if (result is Map) {
      return FilePickerResult(
        path: result['path'] as String?,
        name: result['name'] as String?,
      );
    }
    return null;
  }
}
