import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qinglong_app/base/app_colors.dart';
import 'package:qinglong_app/base/http/api.dart';
import 'package:qinglong_app/base/http/http.dart';
import 'package:qinglong_app/base/ql_app_bar.dart';
import 'package:qinglong_app/base/routes.dart';
import 'package:qinglong_app/base/single_account_page.dart';
import 'package:qinglong_app/base/theme.dart';
import 'package:qinglong_app/base/ui/capsule_glow_card.dart';
import 'package:qinglong_app/base/ui/cyber/cyber_background.dart';
import 'package:qinglong_app/base/ui/loading_widget.dart';
import 'package:qinglong_app/base/ui/log_entry_button.dart';
import 'package:qinglong_app/module/dashboard/dashboard_models.dart';
import 'package:qinglong_app/module/home/system_bean.dart';
import 'package:qinglong_app/module/task/intime_log/intime_log_page.dart';

import '../../main.dart';
import '../../base/ui/container_page_route.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  DashboardPageState createState() => DashboardPageState();
}

class DashboardPageState extends ConsumerState<DashboardPage> {
  /// 全局字重（build 顶部统一 watch，供 helper 方法使用）
  FontWeight _globalFw = FontWeight.w400;
  bool _loading = true;
  String? _errorMsg;

  // 概览数据
  Map<String, dynamic>? _overview;
  // 系统资源数据
  Map<String, dynamic>? _system;
  // 运行时数据
  Map<String, dynamic>? _runtime;
  // 近 7 日趋势
  List<Map<String, dynamic>> _trend = [];
  // 今日耗时 Top 5
  List<Map<String, dynamic>> _topTime = [];
  // 今日执行次数 Top 5
  List<Map<String, dynamic>> _topCount = [];
  // 标签统计
  List<Map<String, dynamic>> _labels = [];
  // 今日成功 / 失败任务明细：直接铺在仪表盘上，不必先点数字才看得到
  List<DashboardTaskResult> _successes = const [];
  List<DashboardTaskResult> _failures = const [];
  // 明细接口可用性（面板 <2.22 / 开放应用无 dashboard 权限 的提示各不相同）
  DashboardApiStatus _detailStatus = DashboardApiStatus.ok;
  // 面板过低（dashboard 接口整体缺失）时用 /api/crons 兜底出的基础统计
  int? _fallbackTotal;
  int? _fallbackEnabled;
  int? _fallbackRunning;
  String? _fallbackTip;
  // 版本号
  String _version = '';

  /// 成功明细里的次数之和
  int get _successTotal => _successes.fold<int>(0, (sum, e) => sum + e.count);

  /// 失败明细里的次数之和
  int get _failTotal => _failures.fold<int>(0, (sum, e) => sum + e.count);

  /// 卡片上展示的今日成功次数：优先服务端概览口径，明细更大时以明细为准
  /// （两者都来自 CrontabStat，正常应一致；取大值可避免任一接口短暂滞后时显示 0）
  int get _todaySuccessValue {
    final int fromOverview =
        (_overview?['todaySuccess'] as num?)?.toInt() ?? 0;
    return fromOverview > _successTotal ? fromOverview : _successTotal;
  }

  int get _todayFailValue {
    final int fromOverview = (_overview?['todayFail'] as num?)?.toInt() ?? 0;
    return fromOverview > _failTotal ? fromOverview : _failTotal;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  // 记录当前在新数据返回前是否已有可展示的旧数据，避免二次进入闪烁全屏转圈
  bool _hasData = false;

  Future<void> _loadData() async {
    final bool firstLoad = !_hasData;
    setState(() {
      // 仅首次无数据时全屏转圈；已有数据时保留旧数据显示、后台刷新
      _loading = firstLoad;
      _errorMsg = null;
    });

    final systemBean = getIt<SystemBean>(
      instanceName: (SingleAccountPageState.of(context)?.index ?? 0).toString(),
    );
    _version = systemBean.version ?? '未知';

    final api = SingleAccountPageState.ofApi(context);

    // 8 个接口并行：主体 6 个负责概览/趋势/Top/标签，末尾 2 个是今日成功/失败明细。
    // 明细与概览同批发出，仪表盘一屏就能看到「今天哪些任务成功、哪些失败」。
    final results = await Future.wait([
      api.dashboardOverview(),
      api.dashboardRuntime(),
      api.dashboardTrend(days: 7),
      api.dashboardTopTime(),
      api.dashboardTopCount(),
      api.dashboardLabels(),
      api.dashboardSuccesses(),
      api.dashboardFailures(),
    ]);

    final overviewRes = results[0];
    final runtimeRes = results[1];
    final trendRes = results[2];
    final topTimeRes = results[3];
    final topCountRes = results[4];
    final labelsRes = results[5];
    final successRes = results[6];
    final failRes = results[7];

    final DashboardApiStatus detailStatus = DashboardApiStatus.fromResponses([
      successRes,
      failRes,
    ]);

    if (!mounted) return;
    setState(() {
      _loading = false;
      _overview = parseDashboardObject(overviewRes.bean);
      _runtime = parseDashboardObject(runtimeRes.bean);
      _trend = parseDashboardList(trendRes.bean);
      _topTime = parseDashboardList(topTimeRes.bean);
      _topCount = parseDashboardList(topCountRes.bean);
      _labels = parseDashboardList(labelsRes.bean);
      _successes = parseDashboardTaskResults(successRes.bean, isSuccess: true);
      _failures = parseDashboardTaskResults(failRes.bean, isSuccess: false);
      _detailStatus = detailStatus;
      if (_overview != null ||
          _runtime != null ||
          _trend.isNotEmpty ||
          _topTime.isNotEmpty ||
          _topCount.isNotEmpty ||
          _labels.isNotEmpty) {
        _hasData = true;
      }

      // 仅当所有主体接口都失败时才显示整页错误（容忍老版本部分接口不存在）
      if (!overviewRes.success &&
          !runtimeRes.success &&
          !trendRes.success &&
          !topTimeRes.success &&
          !topCountRes.success &&
          !labelsRes.success) {
        _errorMsg =
            (overviewRes.message ?? '').isNotEmpty
                ? overviewRes.message
                : '当前版本不支持仪表盘，请将青龙更新到最新版';
      }
    });

    // 面板 <2.22：dashboard 接口整体不存在。此时用 /api/crons 兜底出
    // 总任务/已启用/运行中，至少让仪表盘不是一页空白或一句报错。
    if (_overview == null) {
      await _loadCronsFallback(api, overviewRes);
    }

    // 含 CPU/磁盘的 system 接口独立加载，返回后原位更新资源卡片
    await _loadSystem(api);
  }

  /// overview 不可用时的兜底：/api/crons 是所有青龙版本都有的接口
  ///
  /// 面板过低（404）与无权限（403）提示语不同，不能都说成「版本过低」。
  Future<void> _loadCronsFallback(
    Api api,
    HttpResponse<String> overviewRes,
  ) async {
    try {
      final res = await api.crons();
      if (!mounted) return;
      final list = res.bean;
      if (!res.success || list == null) return;
      final int enabled = list.where((e) => (e.isDisabled ?? 0) == 0).length;
      final int running = list.where((e) => e.status == 1).length;
      final DashboardApiStatus status = DashboardApiStatus.fromResponses([
        overviewRes,
      ]);
      final String tip = switch (status.state) {
        DashboardApiState.denied =>
          '开放应用未授予 dashboard 权限（403），今日统计不可用；'
              '请在青龙「应用」中为该应用勾选 dashboard 权限',
        DashboardApiState.missing =>
          '当前面板未提供仪表盘统计接口（需青龙 2.22 及以上），'
              '以下为任务列表实时统计，今日执行/成功/失败不可用',
        _ =>
          '仪表盘统计接口请求失败（${status.message ?? '网络异常'}），'
              '以下为任务列表实时统计',
      };
      setState(() {
        _fallbackTotal = list.length;
        _fallbackEnabled = enabled;
        _fallbackRunning = running;
        _fallbackTip = tip;
        _hasData = true;
        // 有兜底数据就不再整页报错
        _errorMsg = null;
      });
    } catch (_) {
      // 兜底失败则保留原错误提示
    }
  }

  Future<void> _loadSystem(Api api) async {
    try {
      final systemRes = await api.dashboardSystem();
      if (!mounted) return;
      setState(() {
        _system = parseDashboardObject(systemRes.bean);
      });
    } catch (_) {
      // 网络波动或老版本无此接口时忽略，保留 _system 旧值（或隐藏资源卡片）
    }
  }

  @override
  Widget build(BuildContext context) {
    final _ = ref.watch(themeProvider);
    _globalFw = FontWeight(ref.watch(textWeightProvider));
    final bool isCyber = ref.watch(themeProvider).themeMode == modeCyber;

    Widget body =
        _loading
            ? _buildLoading(isCyber)
            : (_errorMsg != null &&
                    _overview == null &&
                    _system == null &&
                    _runtime == null &&
                    _trend.isEmpty &&
                    _topTime.isEmpty &&
                    _topCount.isEmpty &&
                    _labels.isEmpty
                ? _buildError(isCyber)
                : _buildContent(isCyber));

    if (isCyber) {
      body = CyberBackground(child: body);
    }

    return Scaffold(
      backgroundColor:
          isCyber
              ? CyberColors.bg
              : ref.watch(themeProvider).themeColor.bg2Color(),
      appBar: QlAppBar(
        title: '仪表盘',
        canBack: true,
        actions: [
          CupertinoButton(
            color: Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 15),
            onPressed: _loadData,
            child: Icon(
              CupertinoIcons.refresh,
              color: ref.watch(themeProvider).primaryColor,
              size: 22,
            ),
          ),
        ],
      ),
      body: body,
    );
  }

  Widget _buildLoading(bool isCyber) {
    return Center(
      child: LoadingWidget(
        color: ref.watch(themeProvider).primaryColor,
        size: 30,
      ),
    );
  }

  Widget _buildError(bool isCyber) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Text(
          _errorMsg ?? '加载失败',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: ref.watch(themeProvider).themeColor.descColor(),
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildContent(bool isCyber) {
    final double gap = AppleColors.spaceMd;
    // 性能：用 ListView 替代 Column + SingleChildScrollView。
    // ListView 会为每个子项自动加 RepaintBoundary，滚动时只重绘新进入视口的项；
    // 原先整页每帧重绘（7 张卡片的 BoxShadow + 趋势图每帧 TextPainter 文本布局）
    // 是仪表盘滑动掉帧的主因。
    final List<Widget> cards = [
      _buildVersionCard(isCyber),
      if (_overview != null || _fallbackTotal != null)
        _buildOverviewCard(isCyber),
      // 今日成功 / 失败任务直接上屏（原实现只在点数字后才看得到明细）。
      // 面板整体过低时不重复刷两块告警，概览卡片的兜底提示已说明原因。
      if (_detailStatus.state == DashboardApiState.ok || _overview != null) ...[
        _buildTodayResultCard(isCyber, isSuccess: true),
        _buildTodayResultCard(isCyber, isSuccess: false),
      ],
      if (_trend.isNotEmpty) _buildTrendCard(isCyber),
      if (_topTime.isNotEmpty) _buildTopTimeCard(isCyber),
      if (_topCount.isNotEmpty) _buildTopCountCard(isCyber),
      if (_labels.isNotEmpty) _buildLabelsCard(isCyber),
      if (_runtime != null) _buildRuntimeCard(isCyber),
      if (_system != null) _buildSystemCard(isCyber),
    ];

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          left: AppleColors.spaceMd,
          right: AppleColors.spaceMd,
          top: AppleColors.spaceMd,
          bottom: MediaQuery.of(context).viewPadding.bottom + 30,
        ),
        itemCount: cards.length,
        separatorBuilder: (_, _) => SizedBox(height: gap),
        itemBuilder: (context, index) => cards[index],
      ),
    );
  }

  // 版本信息卡片
  Widget _buildVersionCard(bool isCyber) {
    return _buildCard(
      isCyber: isCyber,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: ref.watch(themeProvider).primaryColor
                  .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              CupertinoIcons.info,
              color: ref.watch(themeProvider).primaryColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '青龙版本',
                  style: TextStyle(
                    fontSize: 13,
                    color: ref
                            .watch(themeProvider)
                            .themeColor
                            .descColor(),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _version,
                  style: TextStyle(
                    fontSize: isCyber ? 20 : 17,
                    fontWeight: _globalFw,
                    color:
                        ref.watch(themeProvider).themeColor.titleColor(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 任务概览卡片
  //
  // 数据来源有两种：
  // 1. 正常：/api/dashboard/overview（青龙 2.22+）
  // 2. 面板过低（接口 404）：用 /api/crons 兜底，只显示总任务/已启用/运行中，
  //    今日执行/成功/失败三格显示「-」并在卡片底部说明原因，不再整页报错。
  Widget _buildOverviewCard(bool isCyber) {
    final bool fromApi = _overview != null;
    final total =
        fromApi
            ? ((_overview!['total'] as num?)?.toInt() ?? 0)
            : (_fallbackTotal ?? 0);
    final enabled =
        fromApi
            ? ((_overview!['enabled'] as num?)?.toInt() ?? 0)
            : (_fallbackEnabled ?? 0);
    final disabled =
        fromApi
            ? ((_overview!['disabled'] as num?)?.toInt() ?? 0)
            : ((_fallbackTotal ?? 0) - (_fallbackEnabled ?? 0));
    final String todayRuns =
        fromApi ? '${(_overview!['todayRuns'] as num?)?.toInt() ?? 0}' : '-';
    // 明细接口可用时以明细求和兜底，避免概览统计滞后时今日成功/失败显示 0
    final String todaySuccess =
        fromApi ? '$_todaySuccessValue' : (_successTotal > 0 ? '$_successTotal' : '-');
    final String todayFail =
        fromApi ? '$_todayFailValue' : (_failTotal > 0 ? '$_failTotal' : '-');
    final successRate = fromApi ? (_overview!['successRate']?.toString() ?? '0') : '-';
    final avgTime = fromApi ? ((_overview!['avgTime'] as num?)?.toInt() ?? 0) : 0;
    final bool canOpenDetail =
        _detailStatus.state == DashboardApiState.ok || !fromApi;

    return _buildSectionCard(
      isCyber: isCyber,
      title: '任务概览',
      icon: CupertinoIcons.chart_bar,
      children: [
        Row(
          children: [
            Expanded(
              child: _buildStatCell(isCyber, '总任务', '$total', CyberColors.cyan),
            ),
            Expanded(
              child: _buildStatCell(
                isCyber,
                '已启用',
                '$enabled',
                CyberColors.neonGreen,
              ),
            ),
            Expanded(
              child: _buildStatCell(
                isCyber,
                '已禁用',
                '$disabled',
                ref.watch(themeProvider).themeColor.descColor(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatCell(
                isCyber,
                '今日执行',
                todayRuns,
                CyberColors.cyan,
              ),
            ),
            Expanded(
              child: _buildStatCell(
                isCyber,
                '今日成功',
                todaySuccess,
                CyberColors.neonGreen,
                // 与网页版一致：点击查看今日成功任务明细
                onTap:
                    canOpenDetail
                        ? () => _openTaskResult(isSuccess: true)
                        : null,
              ),
            ),
            Expanded(
              child: _buildStatCell(
                isCyber,
                '今日失败',
                todayFail,
                CyberColors.neonRed,
                // 与网页版一致：点击查看今日失败任务明细
                onTap:
                    canOpenDetail
                        ? () => _openTaskResult(isSuccess: false)
                        : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatCell(
                isCyber,
                '成功率',
                fromApi ? '$successRate%' : '-',
                CyberColors.neonGreen,
              ),
            ),
            Expanded(
              child: _buildStatCell(
                isCyber,
                '平均耗时',
                fromApi ? _formatTime(avgTime) : '-',
                CyberColors.cyan,
              ),
            ),
            Expanded(
              child: _buildStatCell(
                isCyber,
                '运行中',
                '${_runtime?['runningCount'] ?? _fallbackRunning ?? 0}',
                CyberColors.neonYellow,
              ),
            ),
          ],
        ),
        if (!fromApi && _fallbackTip != null) ...[
          const SizedBox(height: 12),
          _buildNotice(isCyber, _fallbackTip!),
        ],
      ],
    );
  }

  // 今日成功 / 今日失败任务卡片
  //
  // 数据源：/api/dashboard/successes | /api/dashboard/failures
  // 明细直接铺在仪表盘上（最多 5 行），点「全部明细」进完整列表页。
  Widget _buildTodayResultCard(bool isCyber, {required bool isSuccess}) {
    final List<DashboardTaskResult> items =
        isSuccess ? _successes : _failures;
    final int totalCount = isSuccess ? _successTotal : _failTotal;
    final Color accent =
        isSuccess ? CyberColors.neonGreen : CyberColors.neonRed;
    final Color titleColor = ref.watch(themeProvider).themeColor.titleColor();
    final Color descColor = ref.watch(themeProvider).themeColor.descColor();

    final List<Widget> children = [];

    if (_detailStatus.state != DashboardApiState.ok) {
      // 面板过低 / 无权限 / 网络错误：分别给出可执行的提示
      children.add(_buildNotice(isCyber, _detailStatus.message ?? '明细加载失败'));
    } else if (items.isEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            isSuccess ? '今日暂无成功的任务' : '今日暂无失败的任务',
            style: TextStyle(fontSize: 13, color: descColor),
          ),
        ),
      );
    } else {
      for (int i = 0; i < items.length && i < 5; i++) {
        if (i > 0) {
          children.add(
            Divider(
              height: 1,
              thickness: 0.5,
              color: descColor.withValues(alpha: 0.18),
            ),
          );
        }
        children.add(
          _buildTodayResultRow(isCyber, i, items[i], isSuccess: isSuccess),
        );
      }
    }

    return _buildSectionCard(
      isCyber: isCyber,
      title: isSuccess ? '今日成功任务' : '今日失败任务',
      icon:
          isSuccess
              ? CupertinoIcons.checkmark_seal
              : CupertinoIcons.exclamationmark_triangle,
      trailing:
          items.length > 5
              ? GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _openTaskResult(isSuccess: isSuccess),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '全部 ${items.length} 个',
                      style: TextStyle(fontSize: 12, color: descColor),
                    ),
                    Icon(CupertinoIcons.chevron_right, size: 11, color: descColor),
                  ],
                ),
              )
              : null,
      children: [
        // 顶部结论行：今日成功/失败总次数（口径与概览卡一致）
        Row(
          children: [
            Text(
              '$totalCount',
              style: TextStyle(
                fontSize: isCyber ? 22 : 20,
                fontWeight: _globalFw,
                color: isCyber ? accent : titleColor,
              ),
            ),
            const SizedBox(width: 4),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '次',
                style: TextStyle(fontSize: 12, color: descColor),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                items.isEmpty ? '' : '共 ${items.length} 个任务',
                style: TextStyle(fontSize: 12, color: descColor),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  /// 明细单行：序号 + 任务名（可带「已删除」）+ 命令 + 次数 + 日志入口
  Widget _buildTodayResultRow(
    bool isCyber,
    int index,
    DashboardTaskResult item, {
    required bool isSuccess,
  }) {
    final Color descColor = ref.watch(themeProvider).themeColor.descColor();
    final Color titleColor = ref.watch(themeProvider).themeColor.titleColor();
    final Color accent =
        isSuccess ? CyberColors.neonGreen : CyberColors.neonRed;
    final bool canOpenLog = !item.deleted && item.id > 0;
    return InkWell(
      onTap:
          canOpenLog
              ? () => _openLog(item.id, item.name, command: item.command)
              : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 18,
              child: Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(
                  '${index + 1}',
                  style: TextStyle(fontSize: 12, color: descColor),
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: isCyber ? 13 : 14,
                            fontWeight: _globalFw,
                            color: titleColor,
                          ),
                        ),
                      ),
                      if (item.deleted) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 0.5,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: descColor.withValues(alpha: 0.5),
                              width: 0.5,
                            ),
                          ),
                          child: Text(
                            '已删除',
                            style: TextStyle(fontSize: 10, color: descColor),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (item.command.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      item.command,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: descColor),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${item.count}',
              style: TextStyle(
                fontSize: isCyber ? 15 : 14,
                fontWeight: _globalFw,
                color: isCyber ? accent : titleColor,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '次',
                style: TextStyle(fontSize: 11, color: descColor),
              ),
            ),
            const SizedBox(width: 10),
            LogEntryButton(
              label: '日志',
              fontSize: 11,
              enabled: canOpenLog,
              onTap: () => _openLog(item.id, item.name, command: item.command),
            ),
          ],
        ),
      ),
    );
  }

  /// 统一提示条（面板版本过低 / 无权限 / 接口异常）
  Widget _buildNotice(bool isCyber, String text) {
    final Color warn = isCyber ? CyberColors.neonYellow : AppColors.warning;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: warn.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: warn.withValues(alpha: 0.35), width: 0.8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(CupertinoIcons.info_circle, size: 14, color: warn),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: ref.watch(themeProvider).themeColor.titleColor(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 近 7 日趋势卡片（折线图，支持点按/横向拖动查看某日明细）
  Widget _buildTrendCard(bool isCyber) {
    return _buildSectionCard(
      isCyber: isCyber,
      title: '近 7 日趋势',
      icon: CupertinoIcons.graph_circle,
      children: [
        _TrendChart(
          data: _trend,
          isCyber: isCyber,
          primaryColor: ref.watch(themeProvider).primaryColor,
          descColor: ref.watch(themeProvider).themeColor.descColor(),
        ),
      ],
    );
  }

  // 今日耗时 Top 5 卡片
  Widget _buildTopTimeCard(bool isCyber) {
    return _buildSectionCard(
      isCyber: isCyber,
      title: '今日耗时 Top 5',
      icon: CupertinoIcons.timer,
      children: [
        _buildTableHeader(
          isCyber,
          ['#', '定时任务', '平均耗时', '最长单次'],
          flex: [1, 3, 2, 2],
        ),
        const SizedBox(height: 6),
        ..._topTime.asMap().entries.map((entry) {
          final i = entry.key;
          final row = entry.value;
          return _buildTableRow(
            isCyber,
            [
              '${row['rank'] ?? (i + 1)}',
              row['name']?.toString() ?? '-',
              _formatTime((row['avgTime'] as num?)?.toInt() ?? 0),
              _formatTime((row['maxTime'] as num?)?.toInt() ?? 0),
            ],
            flex: [1, 3, 2, 2],
            highlight: i == 0,
          );
        }),
      ],
    );
  }

  // 今日执行次数 Top 5 卡片
  Widget _buildTopCountCard(bool isCyber) {
    return _buildSectionCard(
      isCyber: isCyber,
      title: '今日执行次数 Top 5',
      icon: CupertinoIcons.flame,
      children: [
        _buildTableHeader(
          isCyber,
          ['#', '定时任务', '次数', '平均耗时', '成功率'],
          flex: [1, 3, 1, 2, 2],
        ),
        const SizedBox(height: 6),
        ..._topCount.asMap().entries.map((entry) {
          final i = entry.key;
          final row = entry.value;
          final rate = row['successRate']?.toString() ?? '0';
          return _buildTableRow(
            isCyber,
            [
              '${row['rank'] ?? (i + 1)}',
              row['name']?.toString() ?? '-',
              '${row['runCount'] ?? 0}',
              _formatTime((row['avgTime'] as num?)?.toInt() ?? 0),
              '$rate%',
            ],
            flex: [1, 3, 1, 2, 2],
            highlight: i == 0,
          );
        }),
      ],
    );
  }

  // 标签统计卡片
  Widget _buildLabelsCard(bool isCyber) {
    return _buildSectionCard(
      isCyber: isCyber,
      title: '标签统计',
      icon: CupertinoIcons.tag,
      children: [
        _buildTableHeader(
          isCyber,
          ['标签', '任务数', '今日执行', '成功率', '平均耗时'],
          flex: [3, 1, 2, 2, 2],
        ),
        const SizedBox(height: 6),
        ..._labels.map((row) {
          return _buildTableRow(
            isCyber,
            [
              row['label']?.toString() ?? '-',
              '${row['count'] ?? 0}',
              '${row['todayRuns'] ?? 0}',
              '${row['successRate'] ?? 0}%',
              _formatTime((row['avgTime'] as num?)?.toInt() ?? 0),
            ],
            flex: [3, 1, 2, 2, 2],
          );
        }),
      ],
    );
  }

  // 实时运行态卡片
  Widget _buildRuntimeCard(bool isCyber) {
    final runningCount = (_runtime!['runningCount'] as num?)?.toInt() ?? 0;
    final queuedCount = (_runtime!['queuedCount'] as num?)?.toInt() ?? 0;
    final running = (_runtime!['running'] as List?) ?? const [];
    final idleTasks = (_runtime!['idleTasks'] as List?) ?? const [];

    return _buildSectionCard(
      isCyber: isCyber,
      title: '实时运行态',
      icon: CupertinoIcons.bolt,
      children: [
        Row(
          children: [
            Expanded(
              child: _buildStatCell(
                isCyber,
                '运行中',
                '$runningCount',
                CyberColors.neonGreen,
              ),
            ),
            Expanded(
              child: _buildStatCell(
                isCyber,
                '排队中',
                '$queuedCount',
                AppColors.warning,
              ),
            ),
            const Expanded(child: SizedBox()),
          ],
        ),
        if (running.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            '正在运行的任务',
            style: TextStyle(
              fontSize: isCyber ? 12 : 13,
              color:
                  ref.watch(themeProvider).themeColor.descColor(),
            ),
          ),
          const SizedBox(height: 8),
          ...running.take(5).map((item) {
            final m = item as Map<String, dynamic>;
            final id = (m['id'] as num?)?.toInt() ?? 0;
            final name = m['name']?.toString() ?? '-';
            final pid = m['pid']?.toString() ?? '-';
            final elapsed = (m['elapsed'] as num?)?.toInt() ?? 0;
            return _buildRunningTask(isCyber, id, name, pid, elapsed);
          }),
        ],
        if (idleTasks.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            '24 小时未运行（最多 5 个）',
            style: TextStyle(
              fontSize: isCyber ? 12 : 13,
              color:
                  ref.watch(themeProvider).themeColor.descColor(),
            ),
          ),
          const SizedBox(height: 8),
          ...idleTasks.take(5).map((item) {
            final m = item as Map<String, dynamic>;
            final name = m['name']?.toString() ?? '-';
            final lastRun = m['lastRun']?.toString() ?? '-';
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: AppColors.warning,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color:
                            ref.watch(themeProvider).themeColor.titleColor(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    lastRun,
                    style: TextStyle(
                      fontSize: isCyber ? 12 : 13,
                      color: ref
                              .watch(themeProvider)
                              .themeColor
                              .descColor(),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildRunningTask(
    bool isCyber,
    int id,
    String name,
    String pid,
    int elapsed,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: CyberColors.neonGreen,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color:
                    ref.watch(themeProvider).themeColor.titleColor(),
              ),
            ),
          ),
          if (pid != '-' && pid.isNotEmpty) ...[
            Text(
              'PID $pid',
              style: TextStyle(
                fontSize: 11,
                color:
                    ref.watch(themeProvider).themeColor.descColor(),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            _formatTime(elapsed * 1000),
            style: TextStyle(
              fontSize: isCyber ? 12 : 13,
              color:
                  ref.watch(themeProvider).themeColor.descColor(),
            ),
          ),
          const SizedBox(width: 10),
          // 与网页版一致：运行中任务可直接查看最新日志
          LogEntryButton(
            label: '日志',
            fontSize: 11,
            onTap: () => _openLog(id, name),
          ),
        ],
      ),
    );
  }

  /// 打开该任务的最新日志（复用实时日志页）
  ///
  /// [command] 用于「历史日志」页签定位日志目录（青龙按脚本路径建目录），
  /// 拿不到时传空字符串即可，历史页签会退化为按任务名匹配。
  void _openLog(int id, String name, {String command = ''}) {
    if (id <= 0) return;
    Navigator.of(context).push(
      ContainerPageRoute(
        builder:
            (context) => InTimeLogPage(
              '$id',
              true,
              name,
              command: command.isEmpty ? null : command,
            ),
      ),
    );
  }

  /// 打开今日成功 / 失败明细列表页
  void _openTaskResult({required bool isSuccess}) {
    Navigator.of(
      context,
    ).pushNamed(Routes.routeDashboardTaskResult, arguments: isSuccess);
  }

  // 系统资源卡片
  Widget _buildSystemCard(bool isCyber) {
    final platform = _system!['platform']?.toString() ?? '-';
    final uptime = (_system!['uptime'] as num?)?.toInt() ?? 0;
    final memTotal = (_system!['memTotal'] as num?)?.toDouble() ?? 0;
    final memFree = (_system!['memFree'] as num?)?.toDouble() ?? 0;
    final memPercent = _system!['memUsagePercent']?.toString() ?? '0';
    final heapUsed = (_system!['heapUsed'] as num?)?.toDouble() ?? 0;
    final heapTotal = (_system!['heapTotal'] as num?)?.toDouble() ?? 0;
    final cpus = (_system!['cpus'] as num?)?.toInt() ?? 0;
    final loadAvg = _system!['loadAvg'] as List?;
    final memUsed = memTotal - memFree;
    final memPercentVal = double.tryParse(memPercent.replaceAll('%', '')) ?? 0;

    // CPU 使用率（青龙开源后端 /api/dashboard/system 未返回此字段）
    // 预留解析位置：后端扩展 cpuUsage 字段后可直接展示
    final cpuUsageRaw = _system!['cpuUsage'];
    final cpuUsagePercent = cpuUsageRaw != null
        ? (double.tryParse(cpuUsageRaw.toString().replaceAll('%', '')) ?? 0)
        : null;

    return _buildSectionCard(
      isCyber: isCyber,
      title: '系统资源',
      icon: CupertinoIcons.gauge,
      children: [
        _buildInfoRow(isCyber, '系统平台', platform),
        _buildInfoRow(isCyber, 'CPU 核心', '$cpus'),
        if (cpuUsagePercent != null) ...[
          const SizedBox(height: 8),
          _buildProgress(
            isCyber,
            'CPU 使用率',
            '${cpuUsagePercent.toStringAsFixed(1)}%',
            cpuUsagePercent / 100,
          ),
        ],
        if (loadAvg != null && loadAvg.length >= 3) ...[
          const SizedBox(height: 8),
          _buildLoadAvgChart(isCyber, cpus, loadAvg),
        ],
        _buildInfoRow(isCyber, '运行时长', _formatUptime(uptime)),
        const SizedBox(height: 10),
        _buildProgress(
          isCyber,
          '内存使用',
          '${_formatBytes(memUsed)} / ${_formatBytes(memTotal)}',
          memPercentVal / 100,
        ),
        const SizedBox(height: 8),
        _buildProgress(
          isCyber,
          '堆内存',
          '${heapUsed.toStringAsFixed(1)} MB / ${heapTotal.toStringAsFixed(1)} MB',
          heapTotal > 0 ? heapUsed / heapTotal : 0,
        ),
        // 磁盘容量（青龙 dashboard/system 扩展字段，未返回时隐藏）
        if (_system!['diskTotal'] != null) ...[
          const SizedBox(height: 8),
          _buildProgress(
            isCyber,
            '磁盘容量',
            '${_formatBytes((_system!['diskUsed'] as num?)?.toDouble() ?? 0)} / '
            '${_formatBytes((_system!['diskTotal'] as num?)?.toDouble() ?? 0)}',
            (double.tryParse(
                  (_system!['diskUsagePercent']?.toString() ?? '0').replaceAll(
                    '%',
                    '',
                  ),
                ) ??
                0) /
                100,
          ),
        ],
      ],
    );
  }

  // 系统平均负载可视化图表
  // loadAvg 为 1/5/15 分钟平均负载，以 CPU 核心数为基准计算负载比率
  // 比率 < 70% 绿色（轻松），70-100% 橙色（较忙），> 100% 红色（过载）
  Widget _buildLoadAvgChart(bool isCyber, int cpus, List<dynamic> loadAvg) {
    final labels = ['1分钟', '5分钟', '15分钟'];
    final values = loadAvg
        .map((e) => (e as num?)?.toDouble() ?? 0)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '系统负载',
              style: TextStyle(
                fontSize: isCyber ? 12 : 13,
                color: ref
                    .watch(themeProvider)
                    .themeColor
                    .descColor(),
              ),
            ),
            Text(
              '基准: $cpus核',
              style: TextStyle(
                fontSize: isCyber ? 11 : 11,
                color: ref.watch(themeProvider).themeColor.descColor(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ...List.generate(3, (i) {
          final ratio = cpus > 0 ? values[i] / cpus : 0.0;
          final percentDisplay = (ratio * 100).clamp(0, 999);
          // 颜色分级：绿色 <70%，橙色 70-100%，红色 >100%
          final Color color;
          if (ratio < 0.7) {
            color = isCyber ? CyberColors.neonGreen : const Color(0xFF34C759);
          } else if (ratio <= 1.0) {
            color = isCyber ? CyberColors.neonYellow : AppColors.warning;
          } else {
            color = isCyber ? CyberColors.neonRed : AppColors.danger;
          }

          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      labels[i],
                      style: TextStyle(
                        fontSize: isCyber ? 12 : 12,
                        color: ref
                            .watch(themeProvider)
                            .themeColor
                            .descColor(),
                      ),
                    ),
                    Text(
                      '${values[i].toStringAsFixed(2)}  ${percentDisplay.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: isCyber ? 12 : 12,
                        color: ref.watch(themeProvider).themeColor.titleColor(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    // 进度条最大到 100%，过载时显示满格
                    value: ratio.clamp(0.0, 1.0),
                    backgroundColor: color.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // 表格行
  Widget _buildTableHeader(
    bool isCyber,
    List<String> cells, {
    required List<int> flex,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: List.generate(cells.length, (i) {
          return Expanded(
            flex: flex[i],
            child: Text(
              cells[i],
              style: TextStyle(
                fontSize: isCyber ? 11 : 12,
                color:
                    ref.watch(themeProvider).themeColor.descColor(),
                fontWeight: _globalFw,
              ),
              textAlign: i == 0 ? TextAlign.start : TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          );
        }),
      ),
    );
  }

  Widget _buildTableRow(
    bool isCyber,
    List<String> cells, {
    required List<int> flex,
    bool highlight = false,
  }) {
    final textColor =
        highlight
            ? ref.watch(themeProvider).primaryColor
            : ref.watch(themeProvider).themeColor.titleColor();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: List.generate(cells.length, (i) {
          return Expanded(
            flex: flex[i],
            child: Text(
              cells[i],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: isCyber ? 12 : 13,
                // 高亮行靠颜色区分，字重统一跟随全局设置
                fontWeight: _globalFw,
                color: textColor,
              ),
              textAlign: i == 0 ? TextAlign.start : TextAlign.center,
            ),
          );
        }),
      ),
    );
  }

  // 统计单元格（onTap 非空时可点击，标签右侧显示小箭头提示）
  Widget _buildStatCell(
    bool isCyber,
    String label,
    String value,
    Color color, {
    VoidCallback? onTap,
  }) {
    final Color descColor = ref.watch(themeProvider).themeColor.descColor();
    final Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: isCyber ? 12 : 13,
                color: descColor,
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 2),
              Icon(CupertinoIcons.chevron_right, size: 10, color: descColor),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: isCyber ? 18 : 17,
            fontWeight: _globalFw,
            color: isCyber ? color : AppleColors.textPrimary,
          ),
        ),
      ],
    );

    if (onTap == null) return content;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: content,
    );
  }

  // 进度条
  Widget _buildProgress(
    bool isCyber,
    String label,
    String value,
    double percent,
  ) {
    final color = ref.watch(themeProvider).primaryColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: isCyber ? 12 : 13,
                color:
                    ref.watch(themeProvider).themeColor.descColor(),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: isCyber ? 12 : 13,
                color:
                    ref.watch(themeProvider).themeColor.titleColor(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: percent.clamp(0.0, 1.0),
            backgroundColor: color.withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 6,
          ),
        ),
      ],
    );
  }

  // 信息行
  Widget _buildInfoRow(bool isCyber, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color:
                  ref.watch(themeProvider).themeColor.descColor(),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: ref.watch(themeProvider).themeColor.titleColor(),
            ),
          ),
        ],
      ),
    );
  }

  // 区块卡片
  Widget _buildSectionCard({
    required bool isCyber,
    required String title,
    required IconData icon,
    required List<Widget> children,
    Widget? trailing,
  }) {
    return _buildCard(
      isCyber: isCyber,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: ref.watch(themeProvider).primaryColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: isCyber ? 15 : 17,
                    fontWeight: _globalFw,
                    color:
                        ref.watch(themeProvider).themeColor.titleColor(),
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  // 基础卡片容器（高光内发光样式，统一走 CapsuleGlowCard）
  Widget _buildCard({required bool isCyber, required Widget child}) {
    return SizedBox(
      width: double.infinity,
      child: CapsuleGlowCard.continuous(
        isCyber: isCyber,
        isPinned: false,
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    );
  }

  String _formatBytes(double bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    int unitIndex = 0;
    double size = bytes;
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }
    return '${size.toStringAsFixed(1)} ${units[unitIndex]}';
  }

  String _formatTime(int ms) {
    if (ms <= 0) return '0ms';
    if (ms < 1000) return '${ms}ms';
    final seconds = ms ~/ 1000;
    if (seconds < 60) return '${seconds}s';
    final minutes = seconds ~/ 60;
    final remainSeconds = seconds % 60;
    if (minutes < 60) return '${minutes}m${remainSeconds}s';
    final hours = minutes ~/ 60;
    final remainMinutes = minutes % 60;
    return '${hours}h${remainMinutes}m';
  }

  String _formatUptime(int seconds) {
    if (seconds <= 0) return '-';
    final days = seconds ~/ 86400;
    final hours = (seconds % 86400) ~/ 3600;
    final mins = (seconds % 3600) ~/ 60;
    if (days > 0) return '$days天$hours小时';
    if (hours > 0) return '$hours小时$mins分';
    return '$mins分';
  }
}

/// 近 7 日趋势折线图 + 点按浮层明细（对齐青龙网页版 hover 提示）
///
/// 交互：点按某一列显示该日「总执行/成功/失败」浮层；再点同一列关闭；
/// 横向拖动可连续查看。选中态由本组件自持，避免拖动时整页 setState 重建。
class _TrendChart extends StatefulWidget {
  final List<Map<String, dynamic>> data;
  final bool isCyber;
  final Color primaryColor;
  final Color descColor;

  const _TrendChart({
    required this.data,
    required this.isCyber,
    required this.primaryColor,
    required this.descColor,
  });

  @override
  State<_TrendChart> createState() => _TrendChartState();
}

class _TrendChartState extends State<_TrendChart> {
  /// 图表高度（与浮层定位、其下坐标轴留白配合）
  static const double _height = 160;

  /// 与 _TrendChartPainter 布局保持一致：左侧 36px 给 y 轴刻度，右侧留 4px
  static const double _chartLeft = 36.0;
  static const double _chartRightPad = 4.0;

  /// 选中的列下标（null 表示未选中，不显示浮层）
  int? _selected;

  int _indexAt(double dx, double width) {
    final int count = widget.data.length;
    final double chartWidth = width - _chartRightPad - _chartLeft;
    if (count <= 1 || chartWidth <= 0) return 0;
    final double stepX = chartWidth / (count - 1);
    return ((dx - _chartLeft) / stepX).round().clamp(0, count - 1);
  }

  /// 点按：命中同一列则关闭浮层，便于查看完整图表
  void _onTap(double dx, double width) {
    if (widget.data.isEmpty) return;
    final int index = _indexAt(dx, width);
    setState(() => _selected = (_selected == index) ? null : index);
  }

  /// 拖动：只跟随，不做开关切换
  void _onDrag(double dx, double width) {
    if (widget.data.isEmpty) return;
    final int index = _indexAt(dx, width);
    if (index == _selected) return;
    setState(() => _selected = index);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double width = constraints.maxWidth;
          final int? selected = _selected;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => _onTap(details.localPosition.dx, width),
            onHorizontalDragStart: (details) =>
                _onDrag(details.localPosition.dx, width),
            onHorizontalDragUpdate: (details) =>
                _onDrag(details.localPosition.dx, width),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                RepaintBoundary(
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _TrendChartPainter(
                      data: widget.data,
                      isCyber: widget.isCyber,
                      primaryColor: widget.primaryColor,
                      descColor: widget.descColor,
                      selectedIndex: selected,
                    ),
                  ),
                ),
                if (selected != null && selected < widget.data.length)
                  _buildTooltip(width, selected),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 浮层明细：日期 + 总执行/成功/失败（与网页版一致）
  Widget _buildTooltip(double width, int index) {
    final Map<String, dynamic> row = widget.data[index];
    final int count = widget.data.length;
    final double chartWidth = width - _chartRightPad - _chartLeft;
    final double pointX = count > 1
        ? _chartLeft + chartWidth / (count - 1) * index
        : _chartLeft + chartWidth / 2;

    const double tipWidth = 118;
    // 默认放在指示线右侧，右侧放不下则翻到左侧
    double left = pointX + 10;
    if (left + tipWidth > width - _chartRightPad) {
      left = pointX - 10 - tipWidth;
    }
    left = left.clamp(0.0, (width - tipWidth).clamp(0.0, double.infinity));

    final Color successColor = widget.isCyber
        ? CyberColors.neonGreen
        : AppColors.success;
    final Color failColor =
        widget.isCyber ? CyberColors.neonRed : AppColors.danger;

    return Positioned(
      left: left,
      top: 4,
      child: IgnorePointer(
        child: Container(
          width: tipWidth,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: widget.isCyber ? const Color(0xFF0E1620) : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.isCyber
                  ? widget.primaryColor.withValues(alpha: 0.45)
                  : const Color(0x1F000000),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: widget.isCyber ? 0.5 : 0.12,
                ),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                row['date']?.toString() ?? '',
                style: TextStyle(fontSize: 11, color: widget.descColor),
              ),
              const SizedBox(height: 2),
              _tooltipRow('总执行', row['total'], widget.primaryColor),
              _tooltipRow('成功', row['success'], successColor),
              _tooltipRow('失败', row['fail'], failColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tooltipRow(String label, dynamic value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 11, color: widget.descColor),
            ),
          ),
          Text(
            '${value ?? 0}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: widget.isCyber ? Colors.white : AppleColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 近 7 日趋势折线图（纯 CustomPaint 绘制，避免引入 fl_chart 依赖）
class _TrendChartPainter extends CustomPainter {
  final List<Map<String, dynamic>> data;
  final bool isCyber;
  final Color primaryColor;
  final Color descColor;

  /// 选中的列下标（null = 无选中，不画指示线与强调点）
  final int? selectedIndex;

  _TrendChartPainter({
    required this.data,
    required this.isCyber,
    required this.primaryColor,
    required this.descColor,
    this.selectedIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final color = primaryColor;
    final successColor = isCyber ? CyberColors.neonGreen : AppColors.success;
    final failColor = isCyber ? CyberColors.neonRed : AppColors.danger;
    final gridColor = descColor.withValues(alpha: 0.15);
    final textColor = descColor;

    // 解析 total 数据
    final values = <double>[];
    final labels = <String>[];
    for (final row in data) {
      final v = (row['total'] as num?)?.toDouble() ?? 0;
      values.add(v);
      labels.add(row['date']?.toString() ?? '');
    }

    if (values.isEmpty) return;

    // 成功/失败序列：虚线绘制与选中列强调点共用，避免重复遍历
    final success = <double>[];
    final fail = <double>[];
    for (final row in data) {
      success.add((row['success'] as num?)?.toDouble() ?? 0);
      fail.add((row['fail'] as num?)?.toDouble() ?? 0);
    }

    final maxV = values.reduce(math.max);
    final minV = 0.0;
    // y 轴范围留 10% 顶部空白
    final range = (maxV - minV) == 0 ? 1.0 : (maxV - minV);
    final yMax = maxV + range * 0.1;

    // 布局：左侧 36px 给 y 轴刻度文字，底部 22px 给 x 轴日期
    final chartLeft = 36.0;
    final chartTop = 8.0;
    final chartRight = size.width - 4.0;
    final chartBottom = size.height - 22.0;
    final chartWidth = chartRight - chartLeft;
    final chartHeight = chartBottom - chartTop;

    // 绘制网格线（4 条水平线）
    final gridPaint =
        Paint()
          ..color = gridColor
          ..strokeWidth = 1
          ..style = PaintingStyle.stroke;
    final textStyle = TextStyle(
      fontSize: isCyber ? 9 : 10,
      color: textColor,
    );
    const gridLines = 4;
    for (var i = 0; i <= gridLines; i++) {
      final y = chartTop + chartHeight * i / gridLines;
      canvas.drawLine(Offset(chartLeft, y), Offset(chartRight, y), gridPaint);
      final v = yMax * (1 - i / gridLines);
      final tp = TextPainter(
        text: TextSpan(
          text:
              v >= 1000
                  ? '${(v / 1000).toStringAsFixed(1)}k'
                  : v.toInt().toString(),
          style: textStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 30);
      tp.paint(canvas, Offset(chartLeft - tp.width - 4, y - tp.height / 2));
    }

    if (values.length == 1) {
      // 单点直接画圆点
      final cx = chartLeft + chartWidth / 2;
      final cy = chartTop + chartHeight * (1 - values[0] / yMax);
      canvas.drawCircle(Offset(cx, cy), 3, Paint()..color = color);
    } else {
      // x 步进
      final stepX = chartWidth / (values.length - 1);

      // 折线（总）
      final linePath = Path();
      for (var i = 0; i < values.length; i++) {
        final x = chartLeft + stepX * i;
        final y = chartTop + chartHeight * (1 - values[i] / yMax);
        if (i == 0) {
          linePath.moveTo(x, y);
        } else {
          linePath.lineTo(x, y);
        }
      }
      // 区域填充
      final fillPath =
          Path.from(linePath)
            ..lineTo(chartLeft + stepX * (values.length - 1), chartBottom)
            ..lineTo(chartLeft, chartBottom)
            ..close();
      final fillPaint =
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [color.withValues(alpha: 0.35), color.withValues(alpha: 0.0)],
            ).createShader(
              Rect.fromLTWH(chartLeft, chartTop, chartWidth, chartHeight),
            );
      canvas.drawPath(fillPath, fillPaint);
      // 折线
      canvas.drawPath(
        linePath,
        Paint()
          ..color = color
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );

      // 成功/失败 虚线（如果数据存在）
      void drawDash(List<double> list, Color c) {
        final p = Path();
        for (var i = 0; i < list.length; i++) {
          final x = chartLeft + stepX * i;
          final y = chartTop + chartHeight * (1 - list[i] / yMax);
          if (i == 0) {
            p.moveTo(x, y);
          } else {
            p.lineTo(x, y);
          }
        }
        canvas.drawPath(
          p,
          Paint()
            ..color = c
            ..strokeWidth = 1.5
            ..style = PaintingStyle.stroke,
        );
      }

      drawDash(success, successColor);
      drawDash(fail, failColor);

      // 圆点
      for (var i = 0; i < values.length; i++) {
        final x = chartLeft + stepX * i;
        final y = chartTop + chartHeight * (1 - values[i] / yMax);
        canvas.drawCircle(Offset(x, y), 3, Paint()..color = color);
        canvas.drawCircle(
          Offset(x, y),
          2,
          Paint()..color = isCyber ? const Color(0xFF1A1A2E) : Colors.white,
        );
      }

      // x 轴日期
      final dateStyle = TextStyle(
        fontSize: isCyber ? 9 : 10,
        color: textColor,
      );
      // 控制标签密度：超过 7 个则只显示首尾
      final showEvery = values.length > 8 ? (values.length / 6).ceil() : 1;
      for (var i = 0; i < values.length; i++) {
        if (i % showEvery != 0 && i != values.length - 1) continue;
        final x = chartLeft + stepX * i;
        final tp = TextPainter(
          text: TextSpan(text: labels[i], style: dateStyle),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 40);
        tp.paint(canvas, Offset(x - tp.width / 2, chartBottom + 6));
      }
    }

    // 选中列：竖向指示线 + 三个数据点强调（对应浮层里的 总执行/成功/失败）
    final int? selected = selectedIndex;
    if (selected != null && selected >= 0 && selected < values.length) {
      final double stepX = values.length > 1
          ? chartWidth / (values.length - 1)
          : 0;
      final double x = values.length > 1
          ? chartLeft + stepX * selected
          : chartLeft + chartWidth / 2;

      canvas.drawLine(
        Offset(x, chartTop),
        Offset(x, chartBottom),
        Paint()
          ..color = color.withValues(alpha: 0.55)
          ..strokeWidth = 1,
      );

      void mark(double value, Color c) {
        final double y = chartTop + chartHeight * (1 - value / yMax);
        canvas.drawCircle(Offset(x, y), 4.5, Paint()..color = c);
        canvas.drawCircle(
          Offset(x, y),
          2,
          Paint()..color = isCyber ? const Color(0xFF1A1A2E) : Colors.white,
        );
      }

      mark(values[selected], color);
      if (selected < success.length) mark(success[selected], successColor);
      if (selected < fail.length) mark(fail[selected], failColor);
    }
  }

  @override
  bool shouldRepaint(covariant _TrendChartPainter old) {
    return old.data != data ||
        old.isCyber != isCyber ||
        old.primaryColor != primaryColor ||
        old.selectedIndex != selectedIndex;
  }
}
