import 'dart:io';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:qinglong_app/base/commit_button.dart';
import 'package:qinglong_app/base/http/http.dart';
import 'package:qinglong_app/base/ql_app_bar.dart';
import 'package:qinglong_app/base/single_account_page.dart';
import 'package:qinglong_app/base/theme.dart';
import 'package:qinglong_app/base/ui/other_page_card.dart';
import 'package:qinglong_app/base/ui/selector_card.dart';
import 'package:qinglong_app/base/ui/tree/models/script_data.dart';
import 'package:qinglong_app/base/ui/upload_pill_button.dart';
import 'package:qinglong_app/module/subscribe/add_subscribe_page.dart';
import 'package:qinglong_app/utils/extension.dart';
import 'package:qinglong_app/utils/file_picker_utils.dart';

/// 本地脚本上传页
///
/// 入口：脚本管理右上角「+」→ 上传脚本。
/// 与「新增文件」（手写/粘贴代码）互补：这里直接选手机里的 .py/.js/.sh 等文件，
/// 走青龙 `POST /api/scripts` 的 multipart 分支（服务端 fs.rename 落盘），
/// 比把内容读成字符串再写更稳，不会因编码或体积出问题。
class ScriptUploadLocalPage extends ConsumerStatefulWidget {
  const ScriptUploadLocalPage({super.key, this.initialPath = ""});

  /// 默认目标目录（相对面板 scripts 根目录，空 = 根目录）
  final String initialPath;

  @override
  ConsumerState<ScriptUploadLocalPage> createState() =>
      _ScriptUploadLocalPageState();
}

/// 待上传的本地文件
class _LocalFile {
  _LocalFile({required this.path, required this.name, required this.size});

  final String path;
  final String name;
  final int size;
}

class _ScriptUploadLocalPageState extends ConsumerState<ScriptUploadLocalPage> {
  final List<_LocalFile> _files = [];
  List<String> _dirs = [];

  late String _path = widget.initialPath;
  bool _loadingDirs = true;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDirs());
  }

  /// 拉一次脚本树，把所有目录收集出来供选择（根目录由 SelectorCard 单独占一行）
  Future<void> _loadDirs() async {
    try {
      final HttpResponse<List<ScriptData>> res = await SingleAccountPageState.ofApi(
        context,
      ).scripts();
      final Set<String> dirs = <String>{};
      if (res.success && res.bean != null) {
        for (final ScriptData node in res.bean!) {
          _collectDirs(node, "", dirs);
        }
      }
      if (!mounted) return;
      setState(() {
        _dirs = dirs.toList()..sort();
        _loadingDirs = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingDirs = false);
    }
  }

  /// 递归收集目录的完整相对路径
  void _collectDirs(ScriptData node, String parent, Set<String> out) {
    final String full = parent.isEmpty ? node.title : "$parent/${node.title}";
    if (node.type == "directory") {
      out.add(full);
      for (final ScriptData child in node.children) {
        _collectDirs(child, full, out);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color titleColor = ref.watch(themeProvider).themeColor.titleColor();
    final Color descColor = ref.watch(themeProvider).themeColor.descColor();

    return Scaffold(
      appBar: QlAppBar(
        title: "上传脚本",
        actions: [
          CommitButton(
            onTap: () {
              if (_uploading) return;
              _upload();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        primary: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 22),
              const TitleWidget("目标目录"),
              const SizedBox(height: 10),
              _buildDirSelector(),
              const SizedBox(height: 26),
              Row(
                children: [
                  const TitleWidget("脚本文件"),
                  const Spacer(),
                  if (_files.isNotEmpty)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap:
                          _uploading
                              ? null
                              : () => setState(() => _files.clear()),
                      child: Text(
                        "清空",
                        style: TextStyle(fontSize: 13, color: descColor),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              OtherPageCard(
                margin: EdgeInsets.zero,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_files.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        child: Text(
                          "还没有选择文件，点下方按钮从本地选择",
                          style: TextStyle(fontSize: 13, color: descColor),
                        ),
                      )
                    else
                      ..._files.map(
                        (f) => Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildFileRow(f, titleColor, descColor),
                            if (f != _files.last)
                              Divider(
                                height: 1,
                                thickness: 0.5,
                                color: descColor.withValues(alpha: 0.2),
                              ),
                          ],
                        ),
                      ),
                    if (_files.isNotEmpty)
                      Divider(
                        height: 1,
                        thickness: 0.5,
                        color: descColor.withValues(alpha: 0.2),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: UploadPillButton(
                        label: "选择文件",
                        onTap: () {
                          if (_uploading) return;
                          _pickFiles();
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text(
                "支持一次选择多个文件；同名文件会被覆盖（面板会先备份到 bak 目录）。"
                "脚本默认按文件名落盘，扩展名请保留，否则无法用 task 命令调用。",
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: descColor.withValues(alpha: 0.85),
                ),
              ),
              SizedBox(height: 30 + MediaQuery.of(context).padding.bottom),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDirSelector() {
    if (_loadingDirs) {
      return OtherPageCard(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
        child: Text(
          "正在加载目录...",
          style: TextStyle(
            fontSize: 13,
            color: ref.watch(themeProvider).themeColor.descColor(),
          ),
        ),
      );
    }
    return OtherPageCard(
      margin: EdgeInsets.zero,
      padding: EdgeInsets.zero,
      child: SelectorCard(
        title: _path.isEmpty ? "根目录" : _path,
        subtitle: "上传到该目录下",
        items: [
          SelectorCardItem(
            title: "根目录",
            selected: _path.isEmpty,
            onTap: () {
              setState(() => _path = "");
            },
          ),
          ..._dirs.map(
            (e) => SelectorCardItem(
              title: e,
              selected: _path == e,
              onTap: () {
                setState(() => _path = e);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileRow(_LocalFile f, Color titleColor, Color descColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Image.asset(_iconFor(f.name), width: 30, height: 30, fit: BoxFit.contain),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  f.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, color: titleColor),
                ),
                const SizedBox(height: 3),
                Text(
                  _sizeText(f.size),
                  style: TextStyle(fontSize: 12, color: descColor),
                ),
              ],
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap:
                _uploading
                    ? null
                    : () {
                      setState(() => _files.remove(f));
                    },
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(CupertinoIcons.clear, size: 18, color: descColor),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFiles() async {
    final List<FilePickerResult> picked = await FilePickerUtils.pickFiles();
    if (picked.isEmpty || !mounted) return;

    final List<_LocalFile> added = [];
    for (final FilePickerResult item in picked) {
      final String? path = item.path;
      if (path == null || path.isEmpty) continue;
      if (_files.any((e) => e.path == path)) continue;
      String name = item.name ?? "";
      if (name.isEmpty) name = p.basename(path);
      int size = 0;
      try {
        size = File(path).lengthSync();
      } catch (_) {}
      added.add(_LocalFile(path: path, name: name, size: size));
    }

    if (added.isEmpty) {
      "没有可上传的文件".toast();
      return;
    }
    setState(() => _files.addAll(added));
  }

  Future<void> _upload() async {
    if (_files.isEmpty) {
      "请先选择要上传的脚本文件".toast();
      return;
    }
    setState(() => _uploading = true);

    final api = SingleAccountPageState.ofApi(context);
    final List<_LocalFile> targets = List<_LocalFile>.from(_files);
    int ok = 0;
    int fail = 0;
    String? firstError;

    for (int i = 0; i < targets.length; i++) {
      final _LocalFile f = targets[i];
      EasyLoading.showProgress(0, status: "上传中 ${i + 1}/${targets.length}");
      final HttpResponse<NullResponse> res = await api.uploadScriptFile(
        f.path,
        filename: f.name,
        path: _path,
        onSendProgress: (sent, total) {
          if (total <= 0) return;
          EasyLoading.showProgress(
            (sent / total).clamp(0.0, 1.0),
            status: "上传中 ${i + 1}/${targets.length}",
          );
        },
      );
      if (res.success) {
        ok++;
      } else {
        fail++;
        firstError ??= res.message;
      }
    }

    EasyLoading.dismiss();
    if (!mounted) return;
    setState(() => _uploading = false);

    if (ok == 0) {
      (firstError == null || firstError.isEmpty ? "上传失败" : firstError).toast();
      return;
    }
    if (fail == 0) {
      "已上传 $ok 个脚本".toast();
    } else {
      "成功 $ok 个，失败 $fail 个${firstError == null ? "" : "：$firstError"}".toast();
    }
    Navigator.of(context).pop(true);
  }

  String _sizeText(int bytes) {
    if (bytes <= 0) return "未知大小";
    const List<String> suffixes = ["B", "KB", "MB", "GB"];
    final int i = (log(bytes) / log(1024)).floor().clamp(0, suffixes.length - 1);
    return "${(bytes / pow(1024, i)).toStringAsFixed(i == 0 ? 0 : 1)} ${suffixes[i]}";
  }

  String _iconFor(String name) {
    final String lower = name.toLowerCase();
    if (lower.endsWith(".py")) return "assets/images/py.png";
    if (lower.endsWith(".js")) return "assets/images/js.png";
    if (lower.endsWith(".ts")) return "assets/images/ts.png";
    if (lower.endsWith(".json")) return "assets/images/json.png";
    if (lower.endsWith(".sh")) return "assets/images/shell.png";
    return "assets/images/other.png";
  }
}
