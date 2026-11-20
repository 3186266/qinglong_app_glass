import 'dart:convert';

import 'package:qinglong_app/base/http/http.dart';

/// 仪表盘公共数据模型与解析工具
///
/// 对应青龙服务端（back/api/dashboard.ts，2.22 起提供）：
///   GET /api/dashboard/overview    -> data: { total, enabled, disabled,
///                                       todayRuns, todaySuccess, todayFail,
///                                       successRate, avgTime, ... }
///   GET /api/dashboard/successes   -> data: [{ id, name, command,
///                                       successCount, deleted }]
///   GET /api/dashboard/failures    -> data: [{ id, name, command,
///                                       failCount, deleted }]
///
/// Http 层对 String 泛型会把 envelope 里的 data 段 jsonEncode 后返回，
/// 因此这里统一按「可能是 data 本身、也可能仍是 {code,data} 信封」两种形态解析。

/// 今日成功 / 今日失败中的一行任务
class DashboardTaskResult {
  /// 定时任务 id（0 表示服务端未给出，日志入口不可用）
  final int id;

  /// 任务名（任务被删除时服务端回退为 命令 或 任务#id）
  final String name;

  /// 任务命令
  final String command;

  /// 成功次数 / 失败次数（由 [isSuccess] 决定取哪个字段）
  final int count;

  /// 任务已被删除（服务端查不到对应 cron）
  final bool deleted;

  const DashboardTaskResult({
    required this.id,
    required this.name,
    required this.command,
    required this.count,
    required this.deleted,
  });

  factory DashboardTaskResult.fromJson(
    Map<String, dynamic> json, {
    required bool isSuccess,
  }) {
    final int id = (json['id'] as num?)?.toInt() ?? 0;
    final String name = json['name']?.toString() ?? '';
    final String command = json['command']?.toString() ?? '';
    // 服务端只用其中之一：成功明细给 successCount，失败明细给 failCount。
    // 兜底兼容下划线命名的老/自定义实现。
    final int count =
        (json[isSuccess ? 'successCount' : 'failCount'] as num?)?.toInt() ??
        (json[isSuccess ? 'success_count' : 'fail_count'] as num?)?.toInt() ??
        0;
    return DashboardTaskResult(
      id: id,
      name: name.isNotEmpty ? name : (command.isNotEmpty ? command : '任务#$id'),
      command: command,
      count: count,
      deleted: json['deleted'] == true,
    );
  }
}

/// 单个仪表盘接口的可用性结论
///
/// 青龙 2.22 之前没有 /api/dashboard/*（Express 落 SPA 兜底返回 HTML →
/// Http 层转成 code 404「接口不存在」）；开放应用未授予 dashboard scope
/// 时会拿到 403。两种情况提示语完全不同，不能都显示成「加载失败」。
enum DashboardApiState {
  /// 正常
  ok,

  /// 路由不存在（404）：面板未提供任务级明细接口（青龙 2.21 及更早）
  missing,

  /// 无权限（403，通常是 client_id/secret 登录的开放应用缺 dashboard scope）
  denied,

  /// 其它错误（网络、500 等）
  failed,
}

class DashboardApiStatus {
  final DashboardApiState state;
  final String? message;

  const DashboardApiStatus(this.state, [this.message]);

  static const DashboardApiStatus ok = DashboardApiStatus(DashboardApiState.ok);

  /// 把一组响应的失败原因归并成一个结论：
  /// 只要有一个成功就算可用；否则按 403 > 404 > 其它 的优先级取结论。
  factory DashboardApiStatus.fromResponses(List<HttpResponse<String>> list) {
    if (list.any((e) => e.success)) return DashboardApiStatus.ok;
    final bool denied = list.any((e) => e.code == 403);
    if (denied) {
      return const DashboardApiStatus(
        DashboardApiState.denied,
        '暂无权限（403）：开放应用需勾选 dashboard 权限',
      );
    }
    final bool missing =
        list.any((e) => e.code == 404) ||
        list.any((e) => (e.message ?? '').contains('接口不存在'));
    if (missing) {
      return const DashboardApiStatus(
        DashboardApiState.missing,
        '当前面板未提供任务级明细，已按今日运行日志统计',
      );
    }
    final String msg =
        list
            .map((e) => e.message)
            .whereType<String>()
            .firstWhere((e) => e.trim().isNotEmpty, orElse: () => '');
    return DashboardApiStatus(
      DashboardApiState.failed,
      msg.isEmpty ? '仪表盘加载失败' : msg,
    );
  }
}

/// 解析 object 型 data（兼容信封）
Map<String, dynamic>? parseDashboardObject(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    final dynamic decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      final dynamic data = decoded['data'];
      if (data is Map<String, dynamic>) return data;
      return decoded;
    }
    return null;
  } catch (_) {
    return null;
  }
}

/// 解析 list 型 data（兼容信封）
List<Map<String, dynamic>> parseDashboardList(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    final dynamic decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      final dynamic data = decoded['data'];
      if (data is List) {
        return data.whereType<Map<String, dynamic>>().toList(growable: false);
      }
      return const [];
    }
    if (decoded is List) {
      return decoded.whereType<Map<String, dynamic>>().toList(growable: false);
    }
    return const [];
  } catch (_) {
    return const [];
  }
}

/// 解析今日成功/失败明细
List<DashboardTaskResult> parseDashboardTaskResults(
  String? raw, {
  required bool isSuccess,
}) {
  return parseDashboardList(raw)
      .map((e) => DashboardTaskResult.fromJson(e, isSuccess: isSuccess))
      .where((e) => e.count > 0)
      .toList(growable: false);
}
