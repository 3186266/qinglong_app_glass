import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qinglong_app/base/app_colors.dart';
import 'package:qinglong_app/base/http/http.dart';
import 'package:qinglong_app/base/single_account_page.dart';
import 'package:qinglong_app/base/theme.dart';
import 'package:qinglong_app/base/ui/capsule_glow_card.dart';
import 'package:qinglong_app/base/ui/container_page_route.dart';
import 'package:qinglong_app/base/ui/loading_widget.dart';
import 'package:qinglong_app/module/others/task_log/task_log_bean.dart';
import 'package:qinglong_app/module/task/intime_log/intime_history_log_page.dart';

/// 实时日志页的「历史日志」Tab。
///
/// 数据源是面板的 /logs 目录树（与「任务日志」列表同源），
/// 这里按当前任务的脚本路径算出目录名，只展示该任务自己的历史日志文件。
class TaskHistoryLogTab extends ConsumerStatefulWidget {
  final String cronId;
  final String taskName;
  final String? command;

  const TaskHistoryLogTab({
    super.key,
    required this.cronId,
    required this.taskName,
    this.command,
  });

  @override
  ConsumerState<TaskHistoryLogTab> createState() => _TaskHistoryLogTabState();
}

class _LogFileEntry {
  /// 日志所在目录（/logs 下的目录名）
  final String dir;

  /// 日志文件名（如 2026-11-20.log）
  final String file;

  const _LogFileEntry(this.dir, this.file);
}

class _TaskHistoryLogTabState extends ConsumerState<TaskHistoryLogTab> {
  bool loading = true;
  String? error;
  List<_LogFileEntry> files = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => loadData());
  }

  /// 由脚本命令推导 /logs 下的目录名，规则与详情页「日志历史」入口一致：
  /// `task scripts/xx.py` -> `scripts_xx`
  String get _logDirKey {
    final String raw = widget.command?.trim() ?? "";
    if (raw.isEmpty) return "";
    return raw.replaceAll("task ", "").replaceAll("/", "_").split(".").first;
  }

  Future<void> loadData() async {
    final String key = _logDirKey;
    if (key.isEmpty) {
      setState(() {
        loading = false;
        error = "该任务没有脚本路径，无法定位日志目录";
      });
      return;
    }

    final HttpResponse<List<TaskLogBean>> response =
        await SingleAccountPageState.ofApi(context).taskLog();
    if (!mounted) return;

    if (!response.success) {
      setState(() {
        loading = false;
        error = response.message ?? "日志列表加载失败";
      });
      return;
    }

    final List<TaskLogBean> all = response.bean ?? [];
    // 优先精确匹配目录名；面板对子目录可能追加层级，退化为包含匹配
    List<TaskLogBean> dirs =
        all
            .where((e) => (e.isDir ?? false) && e.name == key)
            .toList();
    if (dirs.isEmpty) {
      dirs =
          all
              .where(
                (e) =>
                    (e.isDir ?? false) &&
                    (e.name ?? "").replaceAll("_", "").contains(
                      key.replaceAll("_", ""),
                    ),
              )
              .toList();
    }

    final List<_LogFileEntry> result = [];
    for (final TaskLogBean dir in dirs) {
      final String dirName = dir.name ?? "";
      for (final String f in dir.files ?? const <String>[]) {
        if (f.isNotEmpty) result.add(_LogFileEntry(dirName, f));
      }
      for (final Children c in dir.children ?? const <Children>[]) {
        final String name = c.title ?? c.value ?? "";
        if (name.isNotEmpty) result.add(_LogFileEntry(dirName, name));
      }
    }
    // 文件名一般带日期，倒序即「新的在前」
    result.sort((a, b) => b.file.compareTo(a.file));

    setState(() {
      loading = false;
      files = result;
      error = result.isEmpty ? "该任务还没有历史日志" : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isCyber = ref.read(themeProvider).themeMode == modeCyber;
    final Color accent =
        isCyber ? CyberColors.cyan : ref.watch(themeProvider).primaryColor;
    final Color titleColor =
        isCyber ? CyberColors.titleWhite : ref.watch(themeProvider).themeColor.titleColor();
    final Color descColor =
        isCyber ? CyberColors.idleGray : ref.watch(themeProvider).themeColor.descColor();

    if (loading) {
      return const Center(child: LoadingWidget());
    }

    if (files.isEmpty) {
      return _emptyView(
        isCyber: isCyber,
        accent: accent,
        titleColor: titleColor,
        descColor: descColor,
      );
    }

    return RefreshIndicator(
      onRefresh: loadData,
      child: ListView.builder(
        padding: EdgeInsets.only(
          top: 8,
          bottom: MediaQuery.of(context).viewPadding.bottom + 24,
        ),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: files.length,
        itemBuilder: (context, index) {
          final _LogFileEntry item = files[index];
          return CapsuleGlowCard.continuous(
            isCyber: isCyber,
            isPinned: false,
            newPinnedStyle: true,
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 9),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () {
                  Navigator.of(context)
                      .push(
                        ContainerPageRoute(
                          builder:
                              (context) => InTimeHistoryLogPage(
                                path: item.dir,
                                title: item.file,
                                // 已知任务 id：日志页可直接运行/暂停该任务
                                cronId: widget.cronId,
                                cronName: widget.taskName,
                              ),
                        ),
                      )
                      .then((value) {
                        // 详情页里删掉日志后会 pop(true)，回来刷新列表
                        if (value == true) loadData();
                      });
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        CupertinoIcons.doc_text,
                        size: 17,
                        color: accent.withValues(alpha: 0.9),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.file,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                color: titleColor,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              item.dir,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: descColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        CupertinoIcons.right_chevron,
                        size: 15,
                        color: descColor,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _emptyView({
    required bool isCyber,
    required Color accent,
    required Color titleColor,
    required Color descColor,
  }) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.18),
        Icon(
          CupertinoIcons.tray,
          size: 42,
          color: descColor.withValues(alpha: 0.5),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            error ?? "暂无历史日志",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: descColor),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: GestureDetector(
            onTap: () {
              setState(() => loading = true);
              loadData();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: accent.withValues(alpha: 0.4)),
              ),
              child: Text(
                "刷新",
                style: TextStyle(fontSize: 13, color: accent),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              "历史日志按脚本路径归类，仅脚本任务（命令形如 task xxx.py）会产生目录",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                height: 1.5,
                color: descColor.withValues(alpha: 0.8),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
