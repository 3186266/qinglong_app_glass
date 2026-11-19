import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:qinglong_app/base/base_viewmodel.dart';
import 'package:qinglong_app/base/http/http.dart';
import 'package:qinglong_app/base/single_account_page.dart';
import 'package:qinglong_app/main.dart';
import 'package:qinglong_app/module/env/env_bean.dart';
import 'package:qinglong_app/utils/extension.dart';
import 'package:qinglong_app/utils/icloud_utils.dart';
import 'package:qinglong_app/utils/remote_list_cache.dart';
import 'package:qinglong_app/utils/webdav_backup_utils.dart';

class EnvViewModel extends BaseViewModel {
  static const String allStr = "全部";
  static const String disabledStr = "已禁用";
  static const String enabledStr = "已启用";
  List<EnvBean> list = [];
  List<EnvBean> disabledList = [];
  List<EnvBean> enabledList = [];

  @override
  void retry(BuildContext context, {bool showLoading = true}) {
    loadData(context, showLoading);
  }

  Future<void> loadData(BuildContext context, [isLoading = true]) async {
    final String? cacheKey = _cacheKey(context);
    bool hydrated = false;

    if (isLoading && list.isEmpty) {
      // 首屏先用上次成功的本地快照渲染，避免整屏转圈等一次远程往返；
      // 紧接着照常发起网络请求，结果回来后覆盖（stale-while-revalidate）。
      final List<EnvBean>? cached =
          cacheKey == null
              ? null
              : RemoteListCache.decodeList<EnvBean>(
                await RemoteListCache.read(cacheKey),
                EnvBean.fromJson,
              );

      if (!context.mounted) return;

      if (cached != null && list.isEmpty) {
        _applyList(cached);
        hydrated = true;
        success();
      } else {
        loading(notify: true);
      }
    }

    HttpResponse<List<EnvBean>> result = await SingleAccountPageState.ofApi(
      context,
    ).envs("");

    if (!context.mounted) return;

    if (result.success && result.bean != null) {
      _applyList(result.bean!);
      notifyICloud(context, list);
      success();
      _persist(cacheKey, list);
    } else if (hydrated && list.isNotEmpty) {
      // 已经有快照兜底时，网络失败不该把列表清空成错误页，只提示一下
      failToast(result.message, notify: true);
    } else {
      list.clear();
      disabledList.clear();
      enabledList.clear();
      failed(result.message, notify: true);
    }
  }

  /// 首屏快照分区 key：账号槽位 + 面板域名 + 资源名，避免换号后串数据
  String? _cacheKey(BuildContext context) {
    try {
      return RemoteListCache.buildKey(
        SingleAccountPageState.ofIndex(context),
        SingleAccountPageState.ofUserInfo(context).host,
        'envs',
      );
    } catch (_) {
      return null;
    }
  }

  /// 列表 + 三个分区一次性落位
  void _applyList(List<EnvBean> data) {
    list
      ..clear()
      ..addAll(data);
    disabledList
      ..clear()
      ..addAll(list.where((element) => element.status == 1));
    enabledList
      ..clear()
      ..addAll(list.where((element) => element.status == 0));
  }

  /// 落盘快照：编码可能耗时（大列表几十 ms），放到微任务里先让 UI 上屏
  void _persist(String? cacheKey, List<EnvBean> data) {
    if (cacheKey == null || data.isEmpty) return;
    final String key = cacheKey;
    final List<EnvBean> snapshot = List<EnvBean>.from(data);
    Future.microtask(() {
      final String json = RemoteListCache.encodeList<EnvBean>(
        snapshot,
        (bean) => bean.toJson(),
      );
      RemoteListCache.write(key, json);
    });
  }

  void notifyICloud(BuildContext context, List<EnvBean> list) {
    getIt<ICloudUtils>(
      instanceName: SingleAccountPageState.of(context)?.index.toString() ?? "0",
    ).asyncEnv(list);
    unawaited(
      WebDavBackupUtils.maybeAutoBackup(
        SingleAccountPageState.of(context)?.index ?? 0,
      ),
    );
  }

  Future<void> delEnvs(BuildContext context, List<String> id) async {
    HttpResponse<NullResponse> result = await SingleAccountPageState.ofApi(
      context,
    ).delEnvs(id);
    if (result.success) {
      "删除成功".toast();
      if (!context.mounted) return;
      loadData(context, false);
    } else {
      failed(result.message, notify: true);
    }
  }

  Future<void> delEnv(BuildContext context, String id) async {
    HttpResponse<NullResponse> result = await SingleAccountPageState.ofApi(
      context,
    ).delEnv(id);
    if (result.success) {
      "删除成功".toast();
      if (!context.mounted) return;
      loadData(context, false);
    } else {
      failed(result.message, notify: true);
    }
  }

  void updateEnv(BuildContext context, EnvBean result) {
    loadData(context, false);
  }

  Future<void> enableEnv(
    BuildContext context,
    List<String> sId,
    int status,
  ) async {
    if (status == 1) {
      HttpResponse<NullResponse> response = await SingleAccountPageState.ofApi(
        context,
      ).enableEnv(sId);

      if (response.success) {
        "启用成功".toast();
        if (!context.mounted) return;
        loadData(context, false);
      } else {
        failToast(response.message, notify: true);
      }
    } else {
      HttpResponse<NullResponse> response = await SingleAccountPageState.ofApi(
        context,
      ).disableEnv(sId);

      if (response.success) {
        "禁用成功".toast();
        if (!context.mounted) return;
        loadData(context, false);
      } else {
        failToast(response.message, notify: true);
      }
    }
  }

  void update(
    BuildContext context,
    String id,
    int newIndex,
    int oldIndex,
  ) async {
    await SingleAccountPageState.ofApi(context).moveEnv(id, oldIndex, newIndex);
    if (!context.mounted) return;
    loadData(context, false);
  }
}
