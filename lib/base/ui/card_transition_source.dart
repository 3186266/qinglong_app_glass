import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:qinglong_app/base/ui/container_page_route.dart';

/// 卡片共享转场源（同步自壁纸版 CardTransitionSource，剔除壁纸模糊参数）。
///
/// 包住真实可见卡片（含卡片底色与描边）：
/// 1. 点击时捕获卡片全局矩形（GlobalKey，精确到视觉卡片外框）；
/// 2. 隐藏真实卡片，同时以卡片内容（不含卡片底色材质）作为源内容
///    push [ContainerPageRoute]——容器首帧与卡片像素一致，从卡片
///    连续展开成整页，而不是在卡片上方盖一层深色面板；
/// 3. 返回时容器收回卡片矩形，源内容淡回，路由移除后恢复真实卡片。
///
/// 注意：卡片内部的 InkWell 需保留编辑模式等本地点击分支
/// （命中测试叶子优先，内层有 onTap 时内层赢出手势仲裁），
/// 非编辑模式下内层 onTap 置 null，点击即由本组件接管。
/// 卡片展开转场的控制器。
///
/// 让卡片以外的入口（如左滑「详细」按钮）复用同一条
/// 「从卡片矩形连续展开成整页」的转场，而不是另走一条普通路由，
/// 保证同一个卡片的两种进入方式视觉一致。
class CardTransitionController {
  _CardTransitionSourceState? _state;

  /// 是否已挂载到仍在树上的卡片（未挂载时 [open] 无副作用）
  bool get isAttached => _state != null;

  /// 触发展开目标页（等价于点击卡片）
  void open() => _state?.open();

  void _attach(_CardTransitionSourceState state) => _state = state;

  void _detach(_CardTransitionSourceState state) {
    if (identical(_state, state)) _state = null;
  }
}

class CardTransitionSource extends StatefulWidget {
  const CardTransitionSource({
    super.key,
    required this.child,
    required this.sourceBuilder,
    required this.pageBuilder,
    this.onResult,
    this.onTap,
    this.controller,
  });

  /// 真实可见卡片（含卡片底色与描边）；转场展开期间被隐藏。
  final Widget child;

  /// 卡片内容（不含卡片底色材质），容器内首帧绘制；
  /// 布局必须与卡片内部一致，否则首帧会跳变。
  final WidgetBuilder sourceBuilder;

  /// 目标页面。
  final WidgetBuilder pageBuilder;

  /// 路由 pop 结果回调（详情页删除成功 pop(true) 刷新列表等）。
  final void Function(Object?)? onResult;

  /// 覆盖「点击卡片」的默认行为（默认 = 展开 [pageBuilder]）。
  ///
  /// 传 null 走默认展开；传入时由调用方自行导航，
  /// 例如定时任务页把点击改为直接打开实时日志。
  final VoidCallback? onTap;

  /// 外部触发同一条展开转场（滑动按钮等）。
  final CardTransitionController? controller;

  @override
  State<CardTransitionSource> createState() => _CardTransitionSourceState();
}

class _CardTransitionSourceState extends State<CardTransitionSource> {
  final GlobalKey _key = GlobalKey();
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
  }

  @override
  void didUpdateWidget(covariant CardTransitionSource oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    super.dispose();
  }

  void open() {
    if (!mounted || _opening) return;

    final RenderBox? box =
        _key.currentContext?.findRenderObject() as RenderBox?;
    final Rect? rect =
        (box != null && box.hasSize)
            ? box.localToGlobal(Offset.zero) & box.size
            : null;

    // 卡片内容快照：隐藏真实卡片前构建，与卡片内部布局保持一致。
    final Widget sourceChild = widget.sourceBuilder(context);

    HapticFeedback.lightImpact();
    setState(() => _opening = true);

    Navigator.of(context)
        .push(
          ContainerPageRoute(
            builder: (context) => widget.pageBuilder(context),
            // 布局未完成时退化为普通容器转场（无精确来源，不画源内容）
            sourceRect: rect,
            sourceChild: rect == null ? null : sourceChild,
            sourceRadius: 18,
            sourceHighlightOpacity: 0.06,
          ),
        )
        .then((value) {
          widget.onResult?.call(value);
        })
        .whenComplete(() {
          if (mounted) {
            setState(() => _opening = false);
          }
        });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: _key,
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap ?? open,
      child: IgnorePointer(
        ignoring: _opening,
        child: Opacity(opacity: _opening ? 0 : 1, child: widget.child),
      ),
    );
  }
}
