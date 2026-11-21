import 'package:flutter/widgets.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:qinglong_app/base/http/api.dart';
import 'package:qinglong_app/base/http/http.dart';
import 'package:qinglong_app/base/single_account_page.dart';
import 'package:qinglong_app/main.dart';
import 'package:qinglong_app/module/home/system_bean.dart';
import 'package:qinglong_app/module/task/task_bean.dart';
import 'package:qinglong_app/module/task/task_bean2.dart';

/// 日志页「运行 / 暂停 / 恢复」的公共逻辑。
///
/// 两步：
/// 1. [locate] 定位日志所属的定时任务（优先用调用方给的 cronId，
///    其次用日志目录名反查，只有唯一命中才返回，避免误操作）
/// 2. [run] / [pause] / [resume] 执行动作，返回 null 表示成功，
///    否则返回可直接 toast 的错误文案
class CronTaskActions {
  final BuildContext context;

  CronTaskActions(this.context);

  Api get _api => SingleAccountPageState.ofApi(context);

  int get _index => SingleAccountPageState.of(context)?.index ?? 0;

  /// 按面板版本拉全量任务列表
  Future<List<TaskBean>?> fetchTasks() async {
    try {
      SystemBean systemBean;
      try {
        systemBean = getIt<SystemBean>(instanceName: _index.toString());
      } catch (e) {
        systemBean = SystemBean(version: "2.10.13", fromAutoGet: false);
      }

      if (systemBean.isUpperVersion2_13_9()) {
        HttpResponse<TaskBean2> response = await _api.crons2_13_09();
        if (response.success) return response.bean?.data;
      } else {
        HttpResponse<List<TaskBean>> response = await _api.crons();
        if (response.success) return response.bean;
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  /// 定位日志对应的任务。cronId 为空时用日志目录名反查。
  Future<TaskBean?> locate({String? cronId, String? logDir}) async {
    final List<TaskBean>? tasks = await fetchTasks();
    if (tasks == null || tasks.isEmpty) return null;

    final String wantId = (cronId ?? "").trim();
    if (wantId.isNotEmpty) {
      for (final TaskBean item in tasks) {
        if ((item.sId ?? "") == wantId) return item;
      }
      // 给了 id 却查不到：任务已被删除，不给操作入口
      return null;
    }

    final String dir = (logDir ?? "").trim();
    if (dir.isEmpty) return null;
    final List<TaskBean> matched =
        tasks.where((e) => logDirMatches(e, dir)).toList();
    return matched.length == 1 ? matched.first : null;
  }

  /// 面板按 `task scripts/xx.py` -> `scripts_xx` 落盘。
  /// 优先用任务自带的 log_path 精确匹配，其次用 command 推导。
  static bool logDirMatches(TaskBean task, String dir) {
    final String logPath = (task.logPath ?? "").trim();
    if (logPath.isNotEmpty && _normalize(logPath) == _normalize(dir)) {
      return true;
    }
    final String command = (task.command ?? "").trim();
    if (command.startsWith("task ")) {
      final String key =
          command.substring(5).replaceAll("/", "_").split(".").first;
      if (_normalize(key) == _normalize(dir)) return true;
    }
    return false;
  }

  static String _normalize(String value) => value
      .replaceAll("_", "")
      .replaceAll("/", "")
      .replaceAll(" ", "")
      .toLowerCase();

  /// 立即运行一次
  Future<String?> run(TaskBean task) async {
    final String id = task.sId ?? "";
    if (id.isEmpty) return "任务 ID 无效";
    EasyLoading.show(status: "运行中...");
    HttpResponse<NullResponse> response = await _api.startTasks([id]);
    EasyLoading.dismiss();
    return response.success ? null : (response.message ?? "运行失败");
  }

  /// 暂停：先停掉运行中的实例，再禁用定时任务
  Future<String?> pause(TaskBean task) async {
    final String id = task.sId ?? "";
    if (id.isEmpty) return "任务 ID 无效";
    EasyLoading.show(status: "暂停中...");
    if ((task.status ?? 1) == 0) {
      await _api.stopTasks([id]);
    }
    HttpResponse<NullResponse> response = await _api.disableTask([id]);
    EasyLoading.dismiss();
    return response.success ? null : (response.message ?? "暂停失败");
  }

  /// 恢复被暂停（禁用）的任务
  Future<String?> resume(TaskBean task) async {
    final String id = task.sId ?? "";
    if (id.isEmpty) return "任务 ID 无效";
    EasyLoading.show(status: "恢复中...");
    HttpResponse<NullResponse> response = await _api.enableTask([id]);
    EasyLoading.dismiss();
    return response.success ? null : (response.message ?? "恢复失败");
  }
}
