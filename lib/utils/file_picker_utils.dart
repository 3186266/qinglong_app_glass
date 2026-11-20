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
}
