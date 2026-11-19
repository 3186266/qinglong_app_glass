import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 远程列表的「首屏快照」缓存。
///
/// 解决的问题：任务列表 / 环境变量这类数据每次冷启动（或换账号）都要等一次
/// 完整的远程往返，期间页面上只有一个转圈。这里把上一次成功拉取的结果落到
/// 本地，页面打开时先用快照立即渲染，网络结果回来后再覆盖 —— 体感上是「秒开」，
/// 数据仍然是新的。
///
/// 设计取舍：
/// - **只缓存最后一次成功结果**，覆盖写，不做多版本，避免无限增长；
/// - **按账号 + 面板域名分区**（见 [buildKey]），避免换号后串数据；
/// - **体积上限** [maxChars]：超出就不落盘。大列表序列化本身就慢，
///   宁可退回原来的「转圈 + 网络」，也不要拖慢启动；
/// - **所有 IO 失败静默忽略**：缓存只是锦上添花，任何异常都不能影响主流程，
///   更不能让页面报错。
class RemoteListCache {
  RemoteListCache._();

  /// 单条快照的字符上限（约等于字节数，中文 JSON 会略大，宁保守）
  static const int maxChars = 2 * 1024 * 1024;

  /// 进程内层：命中时免掉一次磁盘 IO
  static final Map<String, String> _memory = <String, String>{};

  static Directory? _dir;

  /// 生成分区 key：账号槽位 + 面板域名 + 资源名。
  ///
  /// 把域名也算进来，是因为同一个槽位可能被登出后换成另一个面板，
  /// 只按槽位做 key 会把上一个面板的环境变量（含密钥）显示到新面板上。
  static String buildKey(int index, String? host, String name) {
    final String safeHost = (host ?? '').replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');
    return '${index}_${safeHost}_$name';
  }

  /// 同步读内存层（无 IO，可在首帧前直接调用）
  static String? peek(String key) => _memory[key];

  /// 读快照：内存未命中时读磁盘
  static Future<String?> read(String key) async {
    final String? cached = _memory[key];
    if (cached != null) return cached;
    try {
      final File file = await _fileOf(key);
      if (!await file.exists()) return null;
      final String text = await file.readAsString();
      if (text.isEmpty) return null;
      _memory[key] = text;
      return text;
    } catch (_) {
      return null;
    }
  }

  /// 写入快照（内容与内存层一致时直接跳过，避免频繁落盘）
  static Future<void> write(String key, String json) async {
    if (json.isEmpty || json.length > maxChars) return;
    if (_memory[key] == json) return;
    _memory[key] = json;
    try {
      final File file = await _fileOf(key);
      await file.writeAsString(json, flush: false);
    } catch (_) {
      // 磁盘写失败不影响使用，内存层仍然可用
    }
  }

  /// 删除某条快照
  static Future<void> remove(String key) async {
    _memory.remove(key);
    try {
      final File file = await _fileOf(key);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  /// 清空全部快照（登出 / 切换账号时调用）
  static Future<void> clearAll() async {
    _memory.clear();
    try {
      final Directory? dir = await _cacheDir();
      if (dir == null) return;
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      _dir = null;
    } catch (_) {}
  }

  static Future<File> _fileOf(String key) async {
    final Directory? dir = await _cacheDir();
    if (dir == null) {
      throw const FileSystemException('cache dir unavailable');
    }
    return File('${dir.path}${Platform.pathSeparator}${_safeName(key)}.json');
  }

  static Future<Directory?> _cacheDir() async {
    if (_dir != null) return _dir;
    try {
      final Directory base = await getApplicationSupportDirectory();
      final Directory dir = Directory(
        '${base.path}${Platform.pathSeparator}list_cache',
      );
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _dir = dir;
      return dir;
    } catch (_) {
      return null;
    }
  }

  static String _safeName(String key) {
    return key.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
  }

  /// 把一组对象编码成可落盘的 JSON 数组字符串
  static String encodeList<T>(
    List<T> list,
    Map<String, dynamic> Function(T item) toJson,
  ) {
    return jsonEncode(list.map(toJson).toList(growable: false));
  }

  /// 解码快照；格式不符或解析失败时返回 null（当作没有缓存）
  static List<T>? decodeList<T>(
    String? json,
    T Function(Map<String, dynamic> map) fromJson,
  ) {
    if (json == null || json.isEmpty) return null;
    try {
      final dynamic data = jsonDecode(json);
      if (data is! List) return null;
      final List<T> result = <T>[];
      for (final dynamic item in data) {
        if (item is Map) {
          result.add(fromJson(Map<String, dynamic>.from(item)));
        }
      }
      return result.isEmpty ? null : result;
    } catch (_) {
      return null;
    }
  }
}
