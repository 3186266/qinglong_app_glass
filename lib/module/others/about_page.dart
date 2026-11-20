import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qinglong_app/base/ql_app_bar.dart';
import 'package:qinglong_app/base/single_account_page.dart';
import 'package:qinglong_app/base/theme.dart';
import 'package:qinglong_app/base/ui/app_corner.dart';
import 'package:qinglong_app/base/ui/cyber/cyber_background.dart';
import 'package:qinglong_app/base/ui/container_page_route.dart';
import 'package:qinglong_app/base/ui/confirm_dialog.dart';
import 'package:qinglong_app/base/ui/lazy_load_state.dart';
import 'package:qinglong_app/base/ui/other_page_card.dart';
import 'package:qinglong_app/base/ui/settings_widgets.dart';
import 'package:qinglong_app/module/home/system_bean.dart';
import 'package:qinglong_app/module/others/update/panel_upgrade_page.dart';
import 'package:qinglong_app/utils/extension.dart';

import '../../main.dart';

class AboutPage extends ConsumerStatefulWidget {
  const AboutPage({super.key});

  @override
  ConsumerState createState() => _AboutPageState();
}

class _AboutPageState extends ConsumerState<AboutPage>
    with LazyLoadState<AboutPage> {
  String desc = "";
  String versionCode = "";

  @override
  void initState() {
    super.initState();
    getInfo();
  }

  @override
  Widget build(BuildContext context) {
    final bool isCyber = ref.read(themeProvider).themeMode == modeCyber;
    SystemBean? systemBean;

    try {
      systemBean = getIt<SystemBean>(
        instanceName:
            (SingleAccountPageState.of(context)?.index ?? 0).toString(),
      );
    } catch (e) {
      systemBean = SystemBean(version: "2.10.13", fromAutoGet: false);
    }
    final Widget scaffold = Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor:
          isCyber
              ? Colors.transparent
              : ref.watch(themeProvider).themeColor.bg2Color(),
      appBar: QlAppBar(canBack: true, title: "关于软件"),
      body: SingleChildScrollView(
        child: SizedBox(
          width: MediaQuery.of(context).size.width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: MediaQuery.of(context).size.height / 25),
              Center(
                child: ClipPath(
                  clipper: ShapeBorderClipper(
                    shape: appCornerBorder(radius: 18),
                  ),
                  child: Image.asset("assets/images/ql.png", height: 60),
                ),
              ),
              const SizedBox(height: 15),
              Center(
                child: Text(
                  "青龙客户端",
                  style: TextStyle(
                    fontWeight: FontWeight(ref.watch(textWeightProvider)),
                    color: ref.watch(themeProvider).themeColor.titleColor(),
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Center(
                child: Text(
                  "基于青龙开源项目打造的第三方${getPlatformName()}客户端",
                  style: TextStyle(
                    color: ref.watch(themeProvider).themeColor.descColor(),
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 30),
              OtherPageCard.continuous(
                child: Column(
                  children: [
                    // 版本行只做展示：已移除「点击检测新版安装包」，
                    // 客户端不再做任何 App 自更新检查
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 15,
                        right: 15,
                        top: 10,
                        bottom: 10,
                      ),
                      child: Row(
                        children: [
                          Text(
                            "版本",
                            style: TextStyle(
                              color:
                                  ref
                                      .watch(themeProvider)
                                      .themeColor
                                      .titleColor(),
                              fontSize: 16,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            "$desc ($versionCode)",
                            style: TextStyle(
                              color:
                                  ref
                                      .watch(themeProvider)
                                      .themeColor
                                      .descColor(),
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(indent: 15, height: 1),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(18),
                          bottomRight: Radius.circular(18),
                        ),
                        onTap: () {
                          _checkUpdate();
                        },
                        child: Padding(
                          padding: const EdgeInsets.only(
                            left: 15,
                            right: 15,
                            bottom: 10,
                            top: 10,
                          ),
                          child: Row(
                            children: [
                              Text(
                                "青龙服务端",
                                style: TextStyle(
                                  color:
                                      ref
                                          .watch(themeProvider)
                                          .themeColor
                                          .titleColor(),
                                  fontSize: 16,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                "${systemBean.version}",
                                style: TextStyle(
                                  color:
                                      ref
                                          .watch(themeProvider)
                                          .themeColor
                                          .descColor(),
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              const SectionHeader(
                title: "主要改进",
                padding: EdgeInsets.symmetric(horizontal: 30),
              ),
              const SizedBox(height: 10),
              OtherPageCard.continuous(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 15,
                ),
                child: Text(
                  "基于 ayoulx/qinglong-app 二次开发：\n"
                  "· 三种主题模式（赛博 / Apple / 白色），切换含全局颜色过渡动画\n"
                  "· 底部液态玻璃导航栏 + 顶部大胶囊 Tab\n"
                  "· 胶囊高光卡片设计，统一 18px 圆角与毛玻璃视觉（可开关纯色模式）\n"
                  "· 多账号 HTTP 缓存隔离，防止跨账号数据泄漏\n"
                  "· 仪表盘对齐 Web 端（7 日趋势 / Top5 统计 / 实时运行态 / 系统资源）\n"
                  "· 全局字号 + 字重调节（400~700 四档）\n"
                  "· 日志/详情页长按复制启用 iOS 风格文本选择放大镜\n"
                  "· 京东助手独立模块（独立登录 + Cookie 校验）\n"
                  "· 安卓小白条 + 状态栏沉浸适配（兼容澎湃 OS）\n"
                  "· Flutter 3.44.4 全面升级\n",
                  style: TextStyle(
                    color: ref.watch(themeProvider).themeColor.titleColor(),
                    fontSize: 13,
                    height: 1.6,
                  ),
                ),
              ),
              const SizedBox(height: 30),
              Center(
                child: Text(
                  "APP不会收集任何关于您的信息,使用前请仔细阅读用户协议",
                  style: TextStyle(
                    color: ref.watch(themeProvider).themeColor.descColor(),
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 15),
            ],
          ),
        ),
      ),
    );
    return isCyber ? CyberBackground(child: scaffold) : scaffold;
  }

  void getInfo() async {
    String version = "3.0.8";
    versionCode = "308";
    desc = version;
    setState(() {});
  }

  @override
  void onLazyLoad() {}

  void _checkUpdate() async {
    var response = await SingleAccountPageState.ofApi(context).checkUpdate();
    if (!mounted) return;
    if (response.success) {
      if (response.bean?.hasNewVersion ?? false) {
        // 2.24.0 起面板升级任务化（下载暂存→校验依赖→重启应用，失败可回退）；
        // 旧版 ql update 流程曾因依赖未装完导致面板起不来，应用内升级只对 2.24.0+ 开放
        final String index =
            (SingleAccountPageState.of(context)?.index ?? 0).toString();
        final bool upgradeSupported =
            getIt<SystemBean>(instanceName: index).isUpperVersion2_24_0();

        final String content =
            upgradeSupported
                ? "${response.bean?.lastLog ?? ''}\n\n"
                    "将采用 2.24.0+ 安全升级流程：自动下载校验并准备依赖后，"
                    "由你确认重启面板应用更新；升级过程不影响环境变量、任务、脚本等数据。"
                : "${response.bean?.lastLog ?? ''}\n\n"
                    "当前面板版本低于 2.24.0，暂不支持应用内安全升级"
                    "（旧版更新流程易出现依赖未装完导致面板无法启动）。\n"
                    "请先在服务器/网页端手动升级面板到 2.24.0 及以上。";

        final dynamic confirmed = await showConfirmDialog(
          context,
          title: "青龙服务端发现新版本 ${response.bean?.lastVersion}",
          content: content,
          confirmLabel: upgradeSupported ? "立即更新" : "知道了",
          cancelLabel: upgradeSupported ? "稍后再说" : "关闭",
        );

        if (confirmed == true && upgradeSupported && mounted) {
          Navigator.of(context).push(
            ContainerPageRoute(
              builder:
                  (context) => PanelUpgradePage(
                    targetVersion: response.bean?.lastVersion,
                  ),
            ),
          );
        }
      } else {
        "已经是新版本".toast();
      }
    }
  }
}

String getPlatformName() {
  if (Platform.isAndroid) {
    return "Android";
  }
  return "iOS";
}
