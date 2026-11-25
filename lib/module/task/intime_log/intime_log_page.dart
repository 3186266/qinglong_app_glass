
import 'package:qinglong_app/utils/share_utils.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qinglong_app/base/app_colors.dart';
import 'package:qinglong_app/base/cron_task_actions.dart';
import 'package:qinglong_app/base/http/http.dart';
import 'package:qinglong_app/base/ql_app_bar.dart';
import 'package:qinglong_app/base/single_account_page.dart';
import 'package:qinglong_app/base/ui/pauseable_timer_mixin.dart';
import 'package:qinglong_app/base/sp_const.dart';
import 'package:qinglong_app/base/ui/lazy_load_state.dart';
import 'package:qinglong_app/base/ui/loading_widget.dart';
import 'package:qinglong_app/base/ui/log_scroll_button.dart';
import 'package:qinglong_app/module/scan_page.dart';
import 'package:qinglong_app/module/task/task_bean.dart';
import 'package:qinglong_app/utils/extension.dart';
import 'package:qinglong_app/utils/sp_utils.dart';

import '../../../base/commit_button.dart';
import '../../../base/http/api.dart';
import '../../../base/theme.dart';
import '../../../base/ui/log_text_view.dart';
import 'task_history_log_tab.dart';

class InTimeLogPage extends ConsumerStatefulWidget {
  final String cronId;
  final bool needTimer;
  final String title;
  final String? command;

  const InTimeLogPage(
    this.cronId,
    this.needTimer,
    this.title, {
    super.key,
    this.command,
  });

  @override
  ConsumerState<InTimeLogPage> createState() => _InTimeLogPageState();
}

class _InTimeLogPageState extends ConsumerState<InTimeLogPage>
    with
        LazyLoadState<InTimeLogPage>,
        PauseableTimerMixin<InTimeLogPage>,
        SingleTickerProviderStateMixin {
  String? content;

  /// 「最新日志 / 历史日志」两个页签
  late final TabController _tabController;

  int _tabIndex = 0;

  /// 传给 LogTextView 的渲染内容：超长日志仅渲染尾部（实时页自动滚底，
  /// 完整内容仍可分享），避免 2s 轮询的全量重建成本随日志增长无上限
  String? _renderContent;

  /// 实时页单次渲染的最大字符数（字符数 ≈ 字节数级，中文按 1 字符计）。
  /// 96KB 太小：正常脚本动辄几十万字符，前面内容全被丢弃且没有任何提示，
  /// 现在放宽到 512KB（仍远低于会卡死主线程的量级），并在超出时给入口看全文。
  static const int _maxRenderChars = 512 * 1024;

  /// 从 [content] 尾部取约 [limit] 字符，并上移到最近的换行，
  /// 避免首行是半截内容（尤其 UTF-8 截断后的乱码）
  static String _tailFromLineStart(String content, int limit) {
    if (content.length <= limit) return content;
    final int start = content.length - limit;
    final int nl = content.indexOf('\n', start);
    if (nl >= 0 && nl + 1 < content.length) return content.substring(nl + 1);
    return content.substring(start);
  }

  /// 本次会话已尝试自动安装的依赖（面板安装是异步的，任务日志会持续打印
  /// 同一条缺依赖错误——不去重会导致 安装→重启→再报错 的无限循环，
  /// 每 2s 一轮打满主线程直接 ANR 卡死）
  final Set<String> _autoInstallTried = {};

  bool isRequest = false;
  bool canRequest = true;
  int _emptyCount = 0;
  bool alwaysAuthScroll = false;

  /// 当前日志所属的定时任务（用于顶栏「运行 / 暂停」）
  TaskBean? _task;

  /// 连续空日志的容错次数（默认 3 次，点「运行」后临时放大）
  int _emptyTolerance = 3;

  /// 操作进行中（run / stop），防重复点击
  String? _acting;

  /// 刚点完运行/暂停时的本地期望状态，面板状态刷新有延迟时先顶住按钮外观
  bool? _optimisticRunning;

  ScrollController? controller = ScrollController();
  bool showVIPReminder = false;

  getLogData() async {
    if (!canRequest) return;
    if (isRequest) return;
    if (!mounted) return;
    isRequest = true;
    HttpResponse<String> response = await SingleAccountPageState.ofApi(
      context,
    ).inTimeLog(widget.cronId);

    if (!mounted) return;
    isRequest = false;
    if (response.success) {
      if (!mounted) return;
      String? newContent = response.bean;
      if (newContent == null || newContent.isEmpty) {
        _emptyCount++;
        if (_emptyCount >= _emptyTolerance) {
          // 注意：这里停止轮询是"省电"策略，但脚本启动慢、依赖安装久、
          // 面板写盘延迟都可能让日志在 6 秒内为空 —— 停了之后即使脚本
          // 开始输出也再不会刷新，用户看到的就是"没有日志"。
          // 因此空态页面提供一个「重新加载」按钮（见 _buildEmptyHint）。
          stopPauseableTimer();
          canRequest = false;
          content = "";
          _renderContent = "";
          if (!mounted) return;
          setState(() {});
        }
        return;
      }
      final bool changed = newContent != content;
      if (changed) {
        _emptyCount = 0;
        // 已有输出：容错次数恢复默认，脚本结束后仍能按原逻辑停下轮询
        _emptyTolerance = 3;
      }
      final String prev = content ?? "";
      content = newContent;

      // 渲染先落地：不等依赖检测/安装（自动安装可能耗时很长，曾把首帧
      // 渲染卡成永久加载），日志内容先展示，依赖处理在后续轮询中继续
      //
      // 上限说明：超长日志只渲染尾部 _maxRenderChars（原先写死 96KB 且无提示，
      // 用户会以为日志丢了）。截断点上移到最近的换行，避免第一行是半截
      // UTF-8/半行内容；顶部另有「查看完整日志」入口可看全文。
      final String newRender =
          (newContent.length > _maxRenderChars)
              ? _tailFromLineStart(newContent, _maxRenderChars)
              : newContent;
      if (newRender != _renderContent) {
        _renderContent = newRender;
        if (!mounted) return;
        setState(() {});
      }

      if (changed) {
        // 依赖检测只跑新增增量：全量正则随日志增长变慢（MB 级日志每 2s 全量
        // 扫描曾把主线程卡到 ANR），且依赖报错只会出现在新增输出里
        final String delta =
            (newContent.length >= prev.length && newContent.endsWith(prev))
                ? newContent.substring(prev.length)
                : newContent;
        List<String> foundDeps = ScanPageState.foundAllReg(delta);
        if (foundDeps.isNotEmpty &&
            widget.command != null &&
            (widget.command!.endsWith(".js") ||
                widget.command!.endsWith(".ts") ||
                widget.command!.endsWith(".py")) &&
            SpUtil.getInt(spVIP, defValue: typeNormal) != typeNormal) {
          Api api = Api(SingleAccountPageState.of(context)?.index ?? 0);
          bool isPy = widget.command!.endsWith(".py");
          for (String found in foundDeps) {
            // 同一依赖本次会话只尝试一次：面板安装异步生效，运行中任务会
            // 持续打印同一条缺依赖错误，无去重会陷入 安装→再报错 死循环
            if (!_autoInstallTried.add(found)) continue;
            var result = await ScanPageState.autoInstallFounded(
              api,
              found,
              isPy,
            );
            if (result == true) {
              "已安装依赖 $found".toast();
            }
          }
        }
      }

      if (changed && alwaysAuthScroll) {
        scrollLogToBottom(controller);
      }
    } else {
      // 拉取失败（如任务已被删除）也落地空态，避免永久加载
      if (!hasToastedFailed) {
        hasToastedFailed = true;
        response.message?.toast();
      }
      if (content == null) {
        content = "";
        _renderContent = "";
      }
      if (!mounted) return;
      setState(() {});
    }
  }

  bool hasToastedFailed = false;

  /// 空日志且轮询已停时的占位：说明 + 重新加载
  ///
  /// 轮询策略是「连续 _emptyTolerance 次拿不到内容就停」，用来省电；
  /// 但脚本启动慢时日志会长时间为空，停了之后本页就永远停在空态。
  Widget _buildEmptyReload(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "暂无日志",
            style: TextStyle(
              fontSize: 12,
              color: CupertinoColors.systemGrey.resolveFrom(context),
            ),
          ),
          const SizedBox(height: 12),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            color: AppColors.actionRed,
            borderRadius: BorderRadius.circular(999),
            onPressed: () {
              // 重置空计数与容错次数，重新拉起 2s 轮询
              _emptyCount = 0;
              _emptyTolerance = 30;
              canRequest = true;
              startPauseableTimer(
                const Duration(seconds: 2),
                () => getLogData(),
              );
              getLogData();
              if (mounted) setState(() {});
            },
            child: const Text("重新加载", style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  /// 打开完整日志（不受渲染上限影响），长日志可在此查看全部内容
  void _openFullLog(String full) {
    if (full.isEmpty) {
      "暂无日志".toast();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => Scaffold(
              appBar: QlAppBar(canBack: true, title: "${widget.title} · 完整日志"),
              body: CupertinoScrollbar(
                child: LogTextView(
                  content: full,
                  accountIndex:
                      SingleAccountPageState.of(context)?.index ?? 0,
                ),
              ),
            ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabIndex != _tabController.index) {
        setState(() => _tabIndex = _tabController.index);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    cancelPauseableTimer();
    controller?.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    final _ = ref.watch(themeProvider);
    final bool running =
        _optimisticRunning ?? CronTaskActions.isRunning(_task);
    return Builder(
      builder: (context) {
        return Scaffold(
          floatingActionButton:
              _tabIndex == 0
                  ? LogScrollButton(
                    active: alwaysAuthScroll,
                    onTap: () {
                      setState(() {
                        alwaysAuthScroll = !alwaysAuthScroll;
                      });
                      // 开启瞬间立即滚底：日志不再变化时（任务已结束）轮询的
                      // changed 条件永远不满足，只切标记会表现为「点击开启无效」
                      if (alwaysAuthScroll) {
                        scrollLogToBottom(controller);
                      }
                    },
                  )
                  : null,
          appBar: QlAppBar(
            canBack: true,
            actions:
                _tabIndex == 0
                    ? [
                      if (_task != null) ...[
                        _LogActionIcon(
                          icon: CupertinoIcons.play_fill,
                          color: AppColors.actionRed,
                          loading: _acting == "run",
                          onTap: _acting != null ? null : _runTask,
                        ),
                        if (running)
                          _LogActionIcon(
                            icon: CupertinoIcons.pause_fill,
                            color: AppColors.actionRed,
                            loading: _acting == "stop",
                            onTap: _acting != null ? null : _stopTask,
                          ),
                      ],
                      CommitButton(
                        title: "分享",
                        onTap: () {
                          ShareUtils.share(content ?? "");
                        },
                      ),
                    ]
                    : const [],
            title: widget.title,
          ),
          body: Column(
            children: [
              _buildTabBar(context),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // 最新日志：现有实时流
                    (content == null)
                        ? const Center(child: LoadingWidget())
                        : (content!.isEmpty && !canRequest)
                        // 轮询已停且无内容：多半是脚本还没开始写日志，
                        // 给个手动重开的入口，不然这页永远停在"暂无日志"
                        ? _buildEmptyReload(context)
                        : CupertinoScrollbar(
                          child: LogTextView(
                            content: _renderContent ?? content,
                            accountIndex:
                                SingleAccountPageState.of(context)?.index ?? 0,
                            scrollController: controller,
                            // 超过渲染上限时，顶部给「查看完整日志」入口。
                            // 原来只看最后 96KB 且没有任何提示，
                            // 长日志用户会以为前面内容丢了（"日志显示不全"）
                            truncatedHint:
                                (content?.length ?? 0) > _maxRenderChars
                                    ? "仅显示最后 ${(_maxRenderChars / 1024).round()}KB"
                                        "（共 ${((content?.length ?? 0) / 1024).round()}KB），"
                                        "点击查看完整日志"
                                    : null,
                            onShowFull: () => _openFullLog(content ?? ""),
                          ),
                        ),
                    // 历史日志：该任务的历史日志文件列表，点击直接查看
                    TaskHistoryLogTab(
                      cronId: widget.cronId,
                      taskName: widget.title,
                      command: widget.command,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 顶部「最新日志 / 历史日志」页签。
  /// 选中态：主题色文字 + 短下划线；未选态：次色文字（对齐参考图样式）
  Widget _buildTabBar(BuildContext context) {
    final bool isCyber = ref.read(themeProvider).themeMode == modeCyber;
    final Color accent = ref.watch(themeProvider).primaryColor;
    final Color descColor =
        isCyber
            ? CyberColors.idleGray
            : ref.watch(themeProvider).themeColor.descColor();
    final Color dividerColor =
        isCyber ? const Color(0x22FFFFFF) : const Color(0xFFE5E5EA);

    return Container(
      height: 46,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: dividerColor, width: 0.5)),
      ),
      child: Row(
        children: [
          _buildTabItem(0, "最新日志", accent, descColor),
          _buildTabItem(1, "历史日志", accent, descColor),
        ],
      ),
    );
  }

  Widget _buildTabItem(
    int index,
    String label,
    Color accent,
    Color descColor,
  ) {
    final bool selected = _tabIndex == index;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _tabController.animateTo(index),
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 160),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? accent : descColor,
                  ),
                  child: Text(label),
                ),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 58,
              height: 3,
              decoration: BoxDecoration(
                color: selected ? accent : Colors.transparent,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void onLazyLoad() {
    alwaysAuthScroll = SpUtil.getBool(spLogAutoJump2Bottom, defValue: false);
    if (widget.needTimer) {
      // 金标联盟公平调度：使用可暂停的周期 Timer，应用进入后台时自动暂停
      startPauseableTimer(const Duration(seconds: 2), () => getLogData());
    } else {
      WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
        getLogData();
      });
    }
    _loadTask();
  }

  // ------------------------------------------------------------------
  // 顶栏「运行 / 暂停 / 恢复」
  // ------------------------------------------------------------------
  Future<void> _loadTask() async {
    final TaskBean? task = await CronTaskActions(
      context,
    ).locate(cronId: widget.cronId);
    if (!mounted) return;
    // 网络抖动导致这次没定位到：保留上次结果，避免顶栏按钮消失
    if (task == null && _task != null) return;
    setState(() => _task = task);
  }

  /// 任务刚被拉起时日志是空的、轮询已按「连续空数据」停掉，
  /// 这里重置空计数并重新开轮询，否则点了运行看不到新日志
  void _resumePolling() {
    _emptyCount = 0;
    // 刚启动的脚本要跑几秒才出日志：临时放宽容错次数，避免 6 秒内没输出就停了轮询
    _emptyTolerance = 30;
    canRequest = true;
    hasToastedFailed = false;
    if (widget.needTimer) {
      startPauseableTimer(const Duration(seconds: 2), () => getLogData());
    } else {
      getLogData();
    }
  }

  Future<void> _runTask() async {
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
      _resumePolling();
      _syncTaskLater();
    } else {
      error.toast();
    }
  }

  Future<void> _stopTask() async {
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

  /// 等面板真实状态追上本地期望值后再撤掉乐观标记，避免按钮来回跳
  Future<void> _syncTaskLater() async {
    for (int i = 0; i < 3; i++) {
      await Future.delayed(const Duration(milliseconds: 1500));
      if (!mounted) return;
      await _loadTask();
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
}

/// 顶栏的圆形动作按钮（运行 / 暂停 / 恢复），点击区 40x40
class _LogActionIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool loading;
  final VoidCallback? onTap;

  const _LogActionIcon({
    required this.icon,
    required this.color,
    required this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 40,
        height: 40,
        child: Center(
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: onTap == null ? 0.5 : 1,
            child:
                loading
                    ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    )
                    : Icon(icon, size: 22, color: color),
          ),
        ),
      ),
    );
  }
}

