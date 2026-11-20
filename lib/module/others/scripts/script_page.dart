import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qinglong_app/base/http/http.dart';
import 'package:qinglong_app/base/ql_app_bar.dart';
import 'package:qinglong_app/base/routes.dart';
import 'package:qinglong_app/base/single_account_page.dart';
import 'package:qinglong_app/base/sp_const.dart';
import 'package:qinglong_app/base/theme.dart';
import 'package:qinglong_app/base/ui/cyber/cyber_background.dart';
import 'package:qinglong_app/base/ui/floating_search_bar_area.dart';
import 'package:qinglong_app/base/ui/lazy_load_state.dart';
import 'package:qinglong_app/base/ui/loading_widget.dart';
import 'package:qinglong_app/base/ui/sort_nav_button.dart';
import 'package:qinglong_app/base/ui/sort_triangle.dart';
import 'package:qinglong_app/base/ui/tree/models/script_data.dart';
import 'package:qinglong_app/module/others/scripts/folder_add_page.dart';
import 'package:qinglong_app/module/others/scripts/script_upload_local_page.dart';
import 'package:qinglong_app/module/others/scripts/script_upload_page.dart';
import 'package:qinglong_app/utils/extension.dart';
import 'package:qinglong_app/utils/sp_utils.dart';

import '../../../base/cupertino_sheet.dart';
import '../../../base/ui/tree/tree_view.dart';
import '../../../base/ui/tree/tree_view_controller.dart';
import '../../../main.dart';
import '../../home/system_bean.dart';
import '../../../base/ui/container_page_route.dart';

import 'package:qinglong_app/base/ui/content_entrance.dart';
import 'package:qinglong_app/base/ui/confirm_dialog.dart';

/// 脚本列表的排列方式（index 与 [spScriptSortMode] 存的整数一一对应）
enum ScriptSortMode {
  /// 按名称：目录恒定在前，同级按 A→Z（与青龙网页端默认一致）
  name,

  /// 按时间：新 → 旧
  timeDesc,

  /// 按时间：旧 → 新
  timeAsc,
}

class ScriptPage extends ConsumerStatefulWidget {
  const ScriptPage({super.key});

  @override
  ConsumerState<ScriptPage> createState() => _ScriptPageState();
}

class _ScriptPageState extends ConsumerState<ScriptPage>
    with LazyLoadState<ScriptPage> {
  List<ScriptData> list = [];

  String? path;

  ScrollController controller = ScrollController();
  TextEditingController searchText = TextEditingController();
  Timer? _searchDebounce;

  bool buttonshow = false;

  /// 当前排列方式，默认按名称
  ScriptSortMode _sortMode = ScriptSortMode.name;

  void scrollToTop() {
    controller.animateTo(
      0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.linear,
    );
  }

  @override
  void initState() {
    super.initState();
    // 恢复上次选择的排列方式，非法值回落到按名称
    final int savedMode = SpUtil.getInt(spScriptSortMode, defValue: 0);
    _sortMode = ScriptSortMode.values.firstWhere(
      (mode) => mode.index == savedMode,
      orElse: () => ScriptSortMode.name,
    );
    controller.addListener(floatingButtonVisibility);
    searchText.addListener(() {
      _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 300), () {
        _applySearch();
      });
    });
  }

  void floatingButtonVisibility() {
    double y = controller.offset;
    if (y > 500) {
      if (buttonshow == true) return;
      setState(() {
        buttonshow = true;
      });
    } else {
      if (buttonshow == false) return;
      setState(() {
        buttonshow = false;
      });
    }
  }

  late TreeViewController _treeViewController;

  @override
  Widget build(BuildContext context) {
    final bool isCyber = ref.read(themeProvider).themeMode == modeCyber;
    final scaffold = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanDown: (_) {
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        // 赛博模式下背景设为透明，让 CyberBackground 的渐变透出；苹果模式用主题默认背景
        backgroundColor: isCyber ? Colors.transparent : null,
        floatingActionButton: Visibility(
          visible: buttonshow,
          child: FloatingActionButton(
            mini: true,
            onPressed: () {
              scrollToTop();
            },
            elevation: 2,
            child: const Icon(CupertinoIcons.up_arrow),
          ),
        ),
        appBar: QlAppBar(
          canBack: true,
          backCall: () {
            Navigator.of(context).pop();
          },
          title: "脚本管理",
          actions: [
            // 与定时任务 / 环境变量页同一套排序入口：文字随当前方式变化，
            // 三角表示时间方向（名称模式为空心双三角）
            SortNavButton(
              label: _sortLabel,
              state: _sortState,
              activeColor: sortActiveColor(context),
              inactiveColor: sortInactiveColor(
                ref.read(themeProvider).themeMode,
              ),
              onTap: _cycleSortMode,
            ),
            const SizedBox(width: 6),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                showMoreOperate(context, [
                  CupertinoSheer(
                    title: "新增文件",
                    onTap: () {
                      addScript();
                    },
                  ),
                  CupertinoSheer(
                    title: "上传脚本",
                    onTap: () {
                      uploadLocalScript();
                    },
                  ),
                  addDivider(),
                  CupertinoSheer(
                    title: "新增文件夹",
                    onTap: () {
                      SystemBean? systemBean;
                      try {
                        systemBean = getIt<SystemBean>(
                          instanceName:
                              (SingleAccountPageState.of(context)?.index ?? 0)
                                  .toString(),
                        );
                      } catch (e) {
                        systemBean = SystemBean(
                          version: "2.10.13",
                          fromAutoGet: false,
                        );
                      }
                      if (!systemBean.isUpperVersion2_14_5()) {
                        "该功能仅支持v2.14.5及以上版本".toast();
                        return;
                      }
                      addFloder();
                    },
                  ),
                ]);
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 15),
                child: Center(child: Icon(CupertinoIcons.add, size: 24)),
              ),
            ),
          ],
        ),
        body:
            list.isEmpty
                ? const Center(child: LoadingWidget())
                // 数据到位后内容柔和进场（首次挂载播放一次）：淡入 + 轻微上移
                : ContentEntrance(
                  child: FloatingSearchBarArea(
                    controller: searchText,
                    listView: RefreshIndicator(
                      color: Theme.of(context).primaryColor,
                      onRefresh: () async {
                        await loadData();
                        return Future.value();
                      },
                      child: TreeView(
                        // 顶部间距 64 = 搜索框区域(10+44) + 间距10，放在列表内部（滚动时被内容填充，无背景色块）
                        padding: const EdgeInsets.only(top: 64),
                        controller: _treeViewController,
                        onExpansionChanged: (key, state) {
                          ScriptData? node = _treeViewController.getNode(key);
                          if (node != null) {
                            List<ScriptData> updated = _treeViewController
                                .updateNode(
                                  key,
                                  node.copyWith(expanded: !node.expanded),
                                );
                            setState(() {
                              _treeViewController = _treeViewController
                                  .copyWith(children: updated);
                            });
                          }
                        },
                        onDeleteSelfClick: (ScriptData data) {
                          showConfirmDialog(
                            context,
                            title: '确认删除',
                            content: '确认删除吗',
                            danger: true,
                          ).then((confirmed) {
                            if (confirmed != true) return;
                            deleteFold(data);
                          });
                        },
                        onNodeTap: (key) {
                          ScriptData? selectedNode = _treeViewController
                              .getNode(key);
                          String? path = selectedNode?.parent;
                          if (path == null || path.isEmpty) {
                            // For root-level files, extract path from key (e.g., "repo/file.js" -> "repo")
                            String nodeKey = selectedNode?.key ?? "";
                            int lastSlash = nodeKey.lastIndexOf('/');
                            if (lastSlash > 0) {
                              path = nodeKey.substring(0, lastSlash);
                            }
                          }
                          Navigator.of(context)
                              .pushNamed(
                                Routes.routeScriptDetail,
                                arguments: {
                                  "title": selectedNode?.title,
                                  "path": path,
                                },
                              )
                              .then((value) {
                                if (value != null && value == true) {
                                  loadData();
                                }
                              });
                        },
                      ),
                    ),
                  ),
                ),
      ),
    );
    return isCyber ? CyberBackground(child: scaffold) : scaffold;
  }

  Future<void> loadData() async {
    HttpResponse<List<ScriptData>> response =
        await SingleAccountPageState.ofApi(context).scripts();

    if (response.success) {
      if (response.bean == null || response.bean!.isEmpty) {
        "暂无数据".toast();
      }
      list.clear();
      response.bean?.removeWhere(
        (element) =>
            element.title == "node_modules" ||
            element.title == "__pycache__" ||
            element.title == ".git" ||
            element.title.endsWith(".pyc"),
      );
      _filterCacheFiles(response.bean);
      list.addAll(response.bean ?? []);
      _rebuildTree();
    } else {
      response.message?.toast();
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    searchText.dispose();
    controller.dispose();
    super.dispose();
  }

  /// 递归过滤子目录中的 __pycache__、.git 和 .pyc 文件
  void _filterCacheFiles(List<ScriptData>? items) {
    if (items == null || items.isEmpty) return;
    items.removeWhere(
      (element) =>
          element.title == "__pycache__" ||
          element.title == ".git" ||
          element.title.endsWith(".pyc"),
    );
    for (var item in items) {
      _filterCacheFiles(item.children);
    }
  }

  /// 应用搜索过滤
  void _applySearch() {
    _rebuildTree();
  }

  /// 汇总「排序 + 搜索过滤」并重建树控制器。
  ///
  /// 所有会改变列表内容的操作（加载、搜索、切换排列方式）都走这里，
  /// 避免出现「加载后没排序」「排序后把搜索过滤丢了」这类状态不一致。
  void _rebuildTree() {
    final List<ScriptData> sorted = _sortTree(list, _sortMode);
    final String query = searchText.text.trim().toLowerCase();
    final List<ScriptData> visible =
        query.isEmpty ? sorted : _filterTree(sorted, query);
    _treeViewController = TreeViewController(children: visible);
    if (mounted) {
      setState(() {});
    }
  }

  /// 递归排序整棵树：目录恒定排在文件之前，同级内按所选方式排序。
  ///
  /// 时间模式下 createTime 缺失（老版本面板不返回）的节点排在后面，
  /// 并以文件名兜底，保证排序结果稳定可预期。
  List<ScriptData> _sortTree(List<ScriptData> nodes, ScriptSortMode mode) {
    final List<ScriptData> result =
        nodes
            .map(
              (node) =>
                  node.children.isEmpty
                      ? node
                      : node.copyWith(
                        children: _sortTree(node.children, mode),
                      ),
            )
            .toList();

    result.sort((a, b) {
      if (a.isParent != b.isParent) return a.isParent ? -1 : 1;
      if (mode != ScriptSortMode.name) {
        final int byTime =
            mode == ScriptSortMode.timeDesc
                ? b.createTime.compareTo(a.createTime)
                : a.createTime.compareTo(b.createTime);
        if (byTime != 0) return byTime;
      }
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return result;
  }

  /// 整棵树里是否存在可用的创建时间
  bool _anyCreateTime(List<ScriptData> nodes) {
    for (final node in nodes) {
      if (node.hasCreateTime) return true;
      if (node.children.isNotEmpty && _anyCreateTime(node.children)) {
        return true;
      }
    }
    return false;
  }

  /// 排序按钮文字：直观反映当前是「名称」还是「时间」
  String get _sortLabel =>
      _sortMode == ScriptSortMode.name ? "名称" : "时间";

  /// 排序按钮三角状态：名称模式无方向，时间模式区分新→旧 / 旧→新
  SortState get _sortState {
    switch (_sortMode) {
      case ScriptSortMode.name:
        return SortState.none;
      case ScriptSortMode.timeDesc:
        return SortState.desc;
      case ScriptSortMode.timeAsc:
        return SortState.asc;
    }
  }

  /// 单按钮循环切换：名称 → 时间(新→旧) → 时间(旧→新) → 名称
  void _cycleSortMode() {
    final ScriptSortMode next =
        switch (_sortMode) {
          ScriptSortMode.name => ScriptSortMode.timeDesc,
          ScriptSortMode.timeDesc => ScriptSortMode.timeAsc,
          ScriptSortMode.timeAsc => ScriptSortMode.name,
        };
    _sortMode = next;
    SpUtil.putInt(spScriptSortMode, next.index);
    if (next != ScriptSortMode.name && !_anyCreateTime(list)) {
      "当前面板未返回文件时间，时间排列无效，已回退为按名称".toast();
      _sortMode = ScriptSortMode.name;
      SpUtil.putInt(spScriptSortMode, ScriptSortMode.name.index);
    }
    _rebuildTree();
  }

  /// 递归过滤树节点：保留标题匹配的文件，以及包含匹配子节点的目录
  List<ScriptData> _filterTree(List<ScriptData> nodes, String query) {
    List<ScriptData> result = [];
    for (var node in nodes) {
      bool titleMatches = node.title.toLowerCase().contains(query);
      if (node.isParent) {
        List<ScriptData> filteredChildren = _filterTree(node.children, query);
        if (titleMatches || filteredChildren.isNotEmpty) {
          result.add(node.copyWith(children: filteredChildren, expanded: true));
        }
      } else {
        if (titleMatches) {
          result.add(node);
        }
      }
    }
    return result;
  }

  @override
  void onLazyLoad() {
    loadData();
  }

  String scriptPath = "";

  void addScript() {
    Navigator.of(context)
        .push(
          ContainerPageRoute(builder: (context) => const ScriptUploadPage()),
        )
        .then((value) {
          if (value != null && value == true) {
            loadData();
          }
        });
  }

  /// 从手机本地选择脚本文件上传（可多选，走面板 multipart 上传接口）
  void uploadLocalScript() {
    Navigator.of(context)
        .push(
          ContainerPageRoute(
            builder: (context) => const ScriptUploadLocalPage(),
          ),
        )
        .then((value) {
          if (value != null && value == true) {
            loadData();
          }
        });
  }

  void addFloder() {
    Navigator.of(context)
        .push(ContainerPageRoute(builder: (context) => const FloderAddPage()))
        .then((value) {
          if (value != null && value == true) {
            loadData();
          }
        });
  }

  void deleteFold(ScriptData item) async {
    SystemBean? systemBean;

    try {
      systemBean = getIt<SystemBean>(
        instanceName:
            (SingleAccountPageState.of(context)?.index ?? 0).toString(),
      );
    } catch (e) {
      systemBean = SystemBean(version: "2.10.13", fromAutoGet: false);
    }
    if ((item.children.isNotEmpty) && !systemBean.isUpperVersion2_14_5()) {
      "该功能仅支持v2.14.5及以上版本".toast();
      return;
    }

    EasyLoading.show(status: "删除中...");
    HttpResponse<NullResponse> temp;
    if (item.type == "directory") {
      temp = await SingleAccountPageState.ofApi(
        context,
      ).delScriptFold(item.title, item.parent);
    } else {
      if (!context.mounted) return;
      temp =
          systemBean.isUpperVersion2_14_5()
              ? await SingleAccountPageState.ofApi(
                context,
              ).delScriptNewVersion(item.title, item.parent)
              : await SingleAccountPageState.ofApi(
                context,
              ).delScript(item.title, item.parent);
    }
    EasyLoading.dismiss();
    if (temp.success) {
      "已删除".toast();
      await loadData();
    } else {
      temp.message?.toast();
    }
  }
}
