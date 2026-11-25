import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qinglong_app/base/commit_button.dart';
import 'package:path/path.dart' as p;
import 'package:qinglong_app/base/http/http.dart';
import 'package:qinglong_app/base/ql_app_bar.dart';
import 'package:qinglong_app/base/single_account_page.dart';
import 'package:qinglong_app/base/theme.dart';
import 'package:qinglong_app/base/ui/lazy_load_state.dart';
import 'package:qinglong_app/base/upload_script_widget.dart';
import 'package:qinglong_app/module/others/scripts/script_upload_page.dart';
import 'package:qinglong_app/module/subscribe/add_subscribe_page.dart';
import 'package:qinglong_app/module/task/random_cron/random_cron_config.dart';
import 'package:qinglong_app/module/task/random_cron/random_cron_sheet.dart';
import 'package:qinglong_app/module/task/task_bean.dart';
import 'package:qinglong_app/utils/extension.dart';
import 'package:qinglong_app/utils/utils.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/config_detail_page.dart';

class AddTaskPage extends ConsumerStatefulWidget {
  final TaskBean? taskBean;
  final bool hideUploadFile;

  const AddTaskPage({super.key, this.taskBean, required this.hideUploadFile});

  @override
  ConsumerState<AddTaskPage> createState() => _AddTaskPageState();
}

class _AddTaskPageState extends ConsumerState<AddTaskPage>
    with LazyLoadState<AddTaskPage> {
  late TaskBean taskBean;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _commandController = TextEditingController();
  final TextEditingController _cronController = TextEditingController();

  FocusNode focusNode = FocusNode();

  /// 随机定时配置：enabled 时每次保存都会按配置重新生成 cron
  RandomCronConfig _randomConfig = RandomCronConfig();

  /// 当前面板槽位（决定随机配置与分组槽位存在哪个命名空间下）
  int _panelIndex = 0;

  @override
  void initState() {
    super.initState();
    if (widget.taskBean != null) {
      taskBean = widget.taskBean!;
      _nameController.text = taskBean.name ?? "";
      _commandController.text = taskBean.command ?? "";
      _cronController.text = taskBean.schedule ?? "";
    } else {
      taskBean = TaskBean();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: QlAppBar(
        canBack: true,
        actions: [
          CommitButton(
            onTap: () {
              submit();
            },
          ),
        ],
        title:
            (taskBean.sId == null || taskBean.sId!.isEmpty) ? "新增任务" : "编辑任务",
      ),
      body: SingleChildScrollView(
        primary: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 15),
                  const TitleWidget("名称", required: true),
                  const SizedBox(height: 10),
                  TextField(
                    focusNode: focusNode,
                    controller: _nameController,
                    maxLines: 3,
                    minLines: 1,
                    textAlignVertical: TextAlignVertical.center,
                    decoration: const InputDecoration(hintText: "请输入名称"),
                    autofocus: false,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 15),
                  const TitleWidget("命令", required: true),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _commandController,
                    maxLines: 4,
                    minLines: 1,
                    decoration: const InputDecoration(hintText: "请输入命令"),
                    autofocus: false,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 15),
                  const TitleWidget("定时规则", required: true),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _cronController,
                          minLines: 1,
                          textAlignVertical: TextAlignVertical.center,
                          decoration: const InputDecoration(
                            hintText: "可选，多个命令用换行分隔",
                          ),
                          autofocus: false,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildRandomButton(),
                    ],
                  ),
                  if (_randomConfig.enabled) ...[
                    const SizedBox(height: 8),
                    _buildRandomSummary(),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () async {
                          try {
                            var cron = _cronController.text.replaceAll(" ", "_");
                            await launchUrl(
                              Uri.tryParse("https://crontab.guru/#$cron")!,
                            );
                          } catch (_) {}
                        },
                        child: Text(
                          "在线测试",
                          style: TextStyle(
                            fontSize: 12,
                            color: ref.watch(themeProvider).primaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),
                  Visibility(
                    visible: !widget.hideUploadFile,
                    child: UploadScriptWidget(
                      key: fileKey,
                      nameCallBack: (name) async {
                        _nameController.text = name ?? "";
                        if (name == null || name.isEmpty) {
                          _commandController.text = "";
                          _cronController.text = "";
                        } else {
                          String command =
                              "task ${fileKey.currentState?.scriptPath}${(fileKey.currentState != null && fileKey.currentState!.scriptPath.isNotEmpty) ? p.separator : ""}${fileKey.currentState?.getFileName()}";

                          _commandController.text = command;

                          String data =
                              await fileKey.currentState?.file
                                  ?.readAsString() ??
                              "";

                          _cronController.text =
                              ScriptUploadPageState.getCronString(data, name) ??
                              "";
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  GlobalKey<UploadScriptWidgetState> fileKey = GlobalKey();

  /// 「随机」入口：放在 cron 输入框右侧（与参考布局一致）
  Widget _buildRandomButton() {
    final Color accent = ref.watch(themeProvider).primaryColor;
    return GestureDetector(
      onTap: _openRandomCron,
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: accent.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.shuffle, size: 15, color: accent),
            const SizedBox(width: 4),
            Text(
              "随机",
              style: TextStyle(fontSize: 13, color: accent),
            ),
          ],
        ),
      ),
    );
  }

  /// 已启用随机定时时的摘要行：配置 + 重新随机 + 关闭
  Widget _buildRandomSummary() {
    final Color accent = ref.watch(themeProvider).primaryColor;
    final Color desc = ref.watch(themeProvider).themeColor.descColor();
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(CupertinoIcons.sparkles, size: 13, color: accent),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _randomConfig.summary,
              style: TextStyle(fontSize: 11, height: 1.4, color: desc),
            ),
          ),
          GestureDetector(
            onTap: () => _regenerate(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(
                "重新随机",
                style: TextStyle(fontSize: 11, color: accent),
              ),
            ),
          ),
          GestureDetector(
            onTap: () {
              setState(() => _randomConfig.enabled = false);
              RandomCronGenerator.clearConfig(
                _panelIndex,
                _nameController.text,
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Icon(CupertinoIcons.xmark, size: 13, color: desc),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openRandomCron() async {
    hideKeyboardFocus();
    final RandomCronConfig? result = await showRandomCronSheet(
      context,
      _randomConfig,
    );
    if (result == null || !mounted) return;
    setState(() => _randomConfig = result);
    // 应用后立刻生成一次填进输入框，让用户能先看到结果再决定保存
    _regenerate();
  }

  /// 按当前配置重新生成 cron 并写入输入框
  void _regenerate({bool toast = true}) {
    if (!_randomConfig.enabled) return;
    final String cron = RandomCronGenerator.generate(
      _randomConfig,
      panelIndex: _panelIndex,
      taskName: _nameController.text,
    );
    _cronController.text = cron;
    if (toast) "已随机生成：$cron".toast();
  }

  void submit() async {
    if (_nameController.text.isEmpty) {
      "任务名称不能为空".toast();
      return;
    }
    if (_commandController.text.isEmpty) {
      "命令不能为空".toast();
      return;
    }
    // 随机定时：每次保存都重新洗一次牌（与面板上的说明一致）
    if (_randomConfig.enabled) {
      _regenerate(toast: false);
    }
    if (_cronController.text.isEmpty) {
      "定时规则不能为空".toast();
      return;
    }

    commitReal();
  }

  void commitReal() async {
    try {
      hideKeyboardFocus();
      if (fileKey.currentState != null && fileKey.currentState!.file != null) {
        String content = await fileKey.currentState!.file!.readAsString();
        if (!mounted) return;
        HttpResponse<NullResponse> responseS =
            await SingleAccountPageState.ofApi(context).addScript(
              fileKey.currentState?.getFileName() ??
                  _commandController.text.split(" ").last,
              fileKey.currentState?.scriptPath ?? "",
              content,
            );
        if (!responseS.success) {
          responseS.message?.toast();
          return;
        }
      }

      taskBean.name = _nameController.text;
      taskBean.command = _commandController.text.trim();
      taskBean.schedule = _cronController.text.trim();

      await EasyLoading.show(status: "提交中");
      if (!mounted) return;
      HttpResponse<NullResponse> response = await SingleAccountPageState.ofApi(
        context,
      ).addTask(
        _nameController.text,
        _commandController.text.trim(),
        _cronController.text.trim(),
        id: taskBean.id,
        nId: taskBean.nId,
      );
      await EasyLoading.dismiss();
      if (!mounted) return;
      if (response.success) {
        // 记住随机配置，下次编辑同一任务能回填（关掉随机则清掉）
        if (_randomConfig.enabled) {
          RandomCronGenerator.saveConfig(
            _panelIndex,
            _nameController.text,
            _randomConfig,
          );
        } else {
          RandomCronGenerator.clearConfig(_panelIndex, _nameController.text);
        }
        (widget.taskBean?.sId == null) ? "新增成功" : "修改成功".toast();
        ref
            .read(
              SingleAccountPageState.ofTaskProvider(context)(
                getProviderName(context),
              ),
            )
            .updateBean(context, taskBean);
        Navigator.of(context).pop();
      } else {
        response.message?.toast();
      }
    } catch (e) {
      e.toString().toast();
      EasyLoading.dismiss();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _commandController.dispose();
    _cronController.dispose();
    focusNode.dispose();
    super.dispose();
  }

  @override
  void onLazyLoad() {
    // 面板槽位在此读取（initState 里拿不到 InheritedWidget）
    _panelIndex = SingleAccountPageState.of(context)?.index ?? 0;
    // 回填该任务上次保存的随机定时配置
    _randomConfig = RandomCronGenerator.loadConfig(
      _panelIndex,
      _nameController.text,
    );
    setState(() {});
    if (widget.hideUploadFile) {
      focusNode.requestFocus();
    }
  }
}
