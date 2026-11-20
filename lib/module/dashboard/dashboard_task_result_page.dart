import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qinglong_app/base/app_colors.dart';
import 'package:qinglong_app/base/ql_app_bar.dart';
import 'package:qinglong_app/base/single_account_page.dart';
import 'package:qinglong_app/base/theme.dart';
import 'package:qinglong_app/base/ui/capsule_glow_card.dart';
import 'package:qinglong_app/base/ui/cyber/cyber_background.dart';
import 'package:qinglong_app/base/ui/loading_widget.dart';
import 'package:qinglong_app/base/ui/log_entry_button.dart';
import 'package:qinglong_app/module/dashboard/dashboard_models.dart';
import 'package:qinglong_app/module/task/intime_log/intime_log_page.dart';

import '../../base/ui/container_page_route.dart';

/// 今日成功 / 今日失败 任务明细页
///
/// 对齐青龙 Web 面板仪表盘「今日成功」「今日失败」两张统计卡的点击效果：
/// GET /dashboard/successes | /dashboard/failures（无参数，服务端已按次数降序）
/// 返回 [{ id, name, command, successCount | failCount, deleted }]
///
/// 服务端自青龙 2.22 起提供该路由；更早的版本会落到 SPA 兜底（Http 层识别为
/// 404「接口不存在」），开放应用缺 dashboard 权限则是 403，两种提示分开给。
class DashboardTaskResultPage extends ConsumerStatefulWidget {
  /// true = 今日成功，false = 今日失败
  final bool isSuccess;

  const DashboardTaskResultPage({super.key, required this.isSuccess});

  @override
  DashboardTaskResultPageState createState() => DashboardTaskResultPageState();
}

class DashboardTaskResultPageState
    extends ConsumerState<DashboardTaskResultPage> {
  /// 全局字重（build 顶部统一 watch，供 helper 方法使用）
  FontWeight _globalFw = FontWeight.w400;
  bool _loading = true;

  /// 接口可用性（成功 / 面板过低 / 无权限 / 其它错误）
  DashboardApiStatus _status = DashboardApiStatus.ok;

  /// 明细列表（服务端按次数降序返回）
  List<DashboardTaskResult> _items = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    if (!_loading && mounted) {
      setState(() => _loading = true);
    }
    final api = SingleAccountPageState.ofApi(context);
    final res =
        widget.isSuccess
            ? await api.dashboardSuccesses()
            : await api.dashboardFailures();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _items = parseDashboardTaskResults(res.bean, isSuccess: widget.isSuccess);
      _status = DashboardApiStatus.fromResponses([res]);
    });
  }

  /// 打开该任务的最新日志（复用实时日志页）
  void _openLog(DashboardTaskResult item) {
    Navigator.of(context).push(
      ContainerPageRoute(
        builder:
            (context) => InTimeLogPage(
              '${item.id}',
              true,
              item.name,
              command: item.command.isEmpty ? null : item.command,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final _ = ref.watch(themeProvider);
    _globalFw = FontWeight(ref.watch(textWeightProvider));
    final bool isCyber = ref.watch(themeProvider).themeMode == modeCyber;

    Widget body;
    if (_loading) {
      body = _buildLoading();
    } else if (_items.isEmpty) {
      body = _buildEmpty(isCyber);
    } else {
      body = _buildContent(isCyber);
    }

    if (isCyber) {
      body = CyberBackground(child: body);
    }

    return Scaffold(
      backgroundColor:
          isCyber
              ? CyberColors.bg
              : ref.watch(themeProvider).themeColor.bg2Color(),
      appBar: QlAppBar(
        title: widget.isSuccess ? '今日成功' : '今日失败',
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

  Widget _buildLoading() {
    return Center(
      child: LoadingWidget(
        color: ref.watch(themeProvider).primaryColor,
        size: 30,
      ),
    );
  }

  Widget _buildEmpty(bool isCyber) {
    // 接口不通时给「错误 + 重试」，接口通但没数据才说「暂无」
    final bool failed = _status.state != DashboardApiState.ok;
    final String text =
        failed
            ? (_status.message ?? '加载失败')
            : (widget.isSuccess ? '今日暂无成功的任务' : '今日暂无失败的任务');

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ref.watch(themeProvider).themeColor.descColor(),
                fontSize: 14,
                height: 1.5,
              ),
            ),
            if (failed) ...[
              const SizedBox(height: 18),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _loadData,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: ref.watch(themeProvider).primaryColor,
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    '重试',
                    style: TextStyle(
                      fontSize: 13,
                      color: ref.watch(themeProvider).primaryColor,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildContent(bool isCyber) {
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
        itemCount: _items.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: AppleColors.spaceMd),
        itemBuilder: (context, index) {
          // 首行：汇总（今日共 N 次 / M 个任务），避免用户还要自己数
          if (index == 0) return _buildSummary(isCyber);
          return _buildItemCard(isCyber, index - 1);
        },
      ),
    );
  }

  Widget _buildSummary(bool isCyber) {
    final int total = _items.fold<int>(0, (sum, e) => sum + e.count);
    final Color descColor = ref.watch(themeProvider).themeColor.descColor();
    final Color accent =
        widget.isSuccess ? CyberColors.neonGreen : CyberColors.neonRed;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 2),
      child: Row(
        children: [
          Text(
            '今日${widget.isSuccess ? '成功' : '失败'}',
            style: TextStyle(fontSize: 13, color: descColor),
          ),
          const SizedBox(width: 6),
          Text(
            '$total',
            style: TextStyle(
              fontSize: isCyber ? 18 : 16,
              fontWeight: _globalFw,
              color: isCyber ? accent : AppleColors.textPrimary,
            ),
          ),
          Text(' 次 · ${_items.length} 个任务', style: TextStyle(fontSize: 13, color: descColor)),
        ],
      ),
    );
  }

  /// 单个任务明细卡片：任务名（+已删除标签）/ 命令 + 次数 + 最新日志入口
  Widget _buildItemCard(bool isCyber, int index) {
    final DashboardTaskResult item = _items[index];
    final Color countColor =
        widget.isSuccess ? CyberColors.neonGreen : CyberColors.neonRed;
    final bool canOpenLog = !item.deleted && item.id > 0;

    return CapsuleGlowCard.continuous(
      isCyber: isCyber,
      isPinned: false,
      padding: const EdgeInsets.all(14),
      child: InkWell(
        onTap: canOpenLog ? () => _openLog(item) : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 排名序号
            SizedBox(
              width: 24,
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: _globalFw,
                  color: ref.watch(themeProvider).themeColor.descColor(),
                ),
              ),
            ),
            const SizedBox(width: 6),
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
                            fontSize: isCyber ? 14 : 15,
                            fontWeight: _globalFw,
                            color:
                                ref.watch(themeProvider).themeColor.titleColor(),
                          ),
                        ),
                      ),
                      if (item.deleted) ...[
                        const SizedBox(width: 6),
                        _buildDeletedTag(),
                      ],
                    ],
                  ),
                  if (item.command.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      item.command,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: ref.watch(themeProvider).themeColor.descColor(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  LogEntryButton(
                    enabled: canOpenLog,
                    onTap: () => _openLog(item),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // 次数
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${item.count}',
                  style: TextStyle(
                    fontSize: isCyber ? 20 : 18,
                    fontWeight: _globalFw,
                    color: isCyber ? countColor : AppleColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '次',
                  style: TextStyle(
                    fontSize: 12,
                    color: ref.watch(themeProvider).themeColor.descColor(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 已删除任务标记
  Widget _buildDeletedTag() {
    final Color color = ref.watch(themeProvider).themeColor.descColor();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 0.5),
      ),
      child: Text('已删除', style: TextStyle(fontSize: 10, color: color)),
    );
  }
}
