
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qinglong_app/base/app_colors.dart';
import 'package:qinglong_app/base/cron_task_actions.dart';
import 'package:qinglong_app/base/http/http.dart';
import 'package:qinglong_app/base/ql_app_bar.dart';
import 'package:qinglong_app/base/single_account_page.dart';
import 'package:qinglong_app/base/theme.dart';
import 'package:qinglong_app/base/ui/lazy_load_state.dart';
import 'package:qinglong_app/base/ui/loading_widget.dart';
import 'package:qinglong_app/module/task/task_bean.dart';
import 'package:qinglong_app/utils/extension.dart';
import 'package:qinglong_app/utils/share_utils.dart';

import '../../../base/cupertino_sheet.dart';
import '../../../base/ui/container_page_route.dart';
import '../../../base/ui/log_text_view.dart';
import '../../../main.dart';
import '../../home/system_bean.dart';
import 'intime_log_page.dart';

class InTimeHistoryLogPage extends ConsumerStatefulWidget {
  final String title;
  final String path;

  /// 已知的任务 id（从任务详情/实时日志 Tab 进入时传入）。
  /// 为空时按日志目录名反查任务，只有唯一命中才展示运行/暂停按钮。
  final String? cronId;

  /// 任务名称（仅用于展示与兜底匹配）
  final String? cronName;

  const InTimeHistoryLogPage({
    super.key,
    required this.title,
    required this.path,
    this.cronId,
    this.cronName,
  });

  @override
  ConsumerState<InTimeHistoryLogPage> createState() =>
      _InTimeHistoryLogPageState();
}

class _InTimeHistoryLogPageState extends ConsumerState<InTimeHistoryLogPage>
    with LazyLoadState<InTimeHistoryLogPage> {
  String? content;

  /// 与当前日志对应的定时任务；为 null 时不展示底部操作栏
  TaskBean? _task;

  /// 操作进行中（run / stop），同时用于防重复点击与按钮 loading
  String? _acting;

  /// 刚点完运行/暂停时的本地期望状态，避免面板状态刷新有延迟导致按钮来回跳
  bool? _optimisticRunning;

  getLogData() async {
    HttpResponse<String> response = await SingleAccountPageState.ofApi(
      context,
    ).taskLogDetail(widget.title, widget.path);

    if (response.success) {
      content = response.bean;
    } else {
      // 拉取失败也落地空态（toast 一次），避免永久加载
      content ??= "";
      (response.message ?? "").toast();
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final Widget logBody =
        (content == null)
            ? const Center(child: LoadingWidget())
            : CupertinoScrollbar(
              child: LogTextView(
                content: content,
                accountIndex: SingleAccountPageState.of(context)?.index ?? 0,
              ),
            );

    return Scaffold(
      appBar: QlAppBar(
        canBack: true,
        actions: [
          CupertinoButton(
            color: Colors.transparent,
            padding: EdgeInsets.zero,
            onPressed: () {
              showMoreOperate(context, [
                CupertinoSheer(
                  title: "分享",
                  onTap: () async {
                    ShareUtils.share(content ?? "");
                  },
                ),
                addDivider(),
                CupertinoSheer(
                  title: "删除",
                  danger: true,
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    deleteFold(widget.title, widget.path);
                  },
                ),
              ]);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: Center(
                child: Icon(
                  Icons.more_horiz,
                  size: 26,
                  color: Theme.of(context).appBarTheme.iconTheme?.color,
                ),
              ),
            ),
          ),
        ],
        title: widget.title,
      ),
      body:
          _task == null
              ? logBody
              : Column(
                children: [Expanded(child: logBody), _buildActionBar(context)],
              ),
    );
  }

  // ------------------------------------------------------------------
  // 底部操作栏：运行 / 暂停（暂停 = 停止正在运行的实例，仅在运行时可用）
  // ------------------------------------------------------------------
  Widget _buildActionBar(BuildContext context) {
    final TaskBean task = _task!;
    final bool running = _optimisticRunning ?? CronTaskActions.isRunning(task);
    final Color accent = ref.watch(themeProvider).primaryColor;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(
            color:
                isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: CupertinoIcons.play_fill,
                  label: running ? "重新运行" : "运行",
                  color: accent,
                  filled: true,
                  loading: _acting == "run",
                  onTap: _acting != null ? null : runTask,
                ),
              ),
              // 没在运行时压根不给「暂停」，避免误以为脚本正在跑
              if (running) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: _ActionButton(
                    icon: CupertinoIcons.pause_fill,
                    label: "暂停",
                    color: AppColors.warning,
                    filled: false,
                    loading: _acting == "stop",
                    onTap: _acting != null ? null : stopTask,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  void onLazyLoad() {
    getLogData();
    loadTask();
  }

  Future<void> loadTask() async {
    final TaskBean? task = await CronTaskActions(
      context,
    ).locate(cronId: widget.cronId, logDir: widget.path);
    if (!mounted) return;
    // 网络抖动导致这次没定位到：保留上一次结果，别让底部按钮凭空消失
    if (task == null && _task != null) return;
    setState(() => _task = task);
  }

  Future<void> runTask() async {
    final TaskBean? task = _task;
    if (task == null || _acting != null) return;
    setState(() => _acting = "run");
    String? error;
    try {
      error = await CronTaskActions(context).run(task);
    } catch (e) {
      error = "运行失败：$e";
    }
    if (!mounted) return;
    setState(() {
      _acting = null;
      if (error == null) _optimisticRunning = true;
    });
    if (error == null) {
      "已开始运行".toast();
      _syncTaskLater();
      // 历史日志是静态文件，看不到新输出；直接带用户去实时日志，点完就能确认跑起来了
      _openInTimeLog(task);
    } else {
      error.toast();
    }
  }

  /// 跳到该任务的实时日志（首屏即可看到新跑出来的输出）
  void _openInTimeLog(TaskBean task) {
    final String cronId = task.sId ?? "";
    if (cronId.isEmpty) return;
    Navigator.of(context).push(
      ContainerPageRoute(
        builder:
            (context) =>
                InTimeLogPage(cronId, true, task.name ?? widget.title,
                  command: task.command),
      ),
    );
  }

  Future<void> stopTask() async {
    final TaskBean? task = _task;
    if (task == null || _acting != null) return;
    setState(() => _acting = "stop");
    String? error;
    try {
      error = await CronTaskActions(context).stop(task);
    } catch (e) {
      error = "暂停失败：$e";
    }
    if (!mounted) return;
    setState(() {
      _acting = null;
      if (error == null) _optimisticRunning = false;
    });
    if (error == null) {
      "已暂停".toast();
      _syncTaskLater();
    } else {
      error.toast();
    }
  }

  /// 面板对「运行/停止」的状态同步有延迟：轮询几次，等真实状态追上
  /// 本地期望值后再撤掉乐观标记，避免按钮立刻跳回原状态
  Future<void> _syncTaskLater() async {
    for (int i = 0; i < 3; i++) {
      await Future.delayed(const Duration(milliseconds: 1500));
      if (!mounted) return;
      await loadTask();
      if (!mounted) return;
      final TaskBean? task = _task;
      if (task != null &&
          CronTaskActions.isRunning(task) == _optimisticRunning) {
        setState(() => _optimisticRunning = null);
        return;
      }
    }
    if (!mounted) return;
    setState(() => _optimisticRunning = null);
  }

  void deleteFold(String title, String path) async {
    SystemBean systemBean;

    try {
      systemBean = getIt<SystemBean>(
        instanceName:
            (SingleAccountPageState.of(context)?.index ?? 0).toString(),
      );
    } catch (e) {
      systemBean = SystemBean(version: "2.10.13", fromAutoGet: false);
    }
    if (!systemBean.isUpperVersion2_14_5()) {
      "该功能仅支持v2.14.5及以上版本".toast();
      return;
    }

    EasyLoading.show(status: "删除中...");
    var temp = await SingleAccountPageState.ofApi(
      context,
    ).deleteLog(title, path);
    EasyLoading.dismiss();
    if (!mounted) return;
    if (temp.success) {
      "已删除".toast();
      Navigator.of(context).pop(true);
    } else {
      temp.message?.toast();
    }
  }
}

/// 日志页底部操作按钮（运行 / 暂停 / 恢复）
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool filled;
  final VoidCallback? onTap;
  final bool loading;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.filled,
    required this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: enabled ? 1 : 0.55,
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: filled ? color : color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border:
                filled
                    ? null
                    : Border.all(color: color.withValues(alpha: 0.45)),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      filled ? Colors.white : color,
                    ),
                  ),
                )
              else
                Icon(icon, size: 18, color: filled ? Colors.white : color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: filled ? Colors.white : color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
