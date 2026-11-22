import 'dart:convert';

import 'package:qinglong_app/utils/extension.dart';
import 'package:qinglong_app/utils/sp_utils.dart';

import 'sp_const.dart';
import 'userinfo_viewmodel.dart';

class MultiAccountUserInfoViewModel {
  static int maxAccount = 1; //1代表普通用户, 5代表付费用户

  List<TokenBean> tokenBeans = [];
  List<UserInfoBean> historyAccounts = [];

  static void payedVIP(int type) {
    if (SpUtil.getInt(spVIP, defValue: typeNormal) == typeSVIP) return;

    SpUtil.putInt(spVIP, type);

    int count = 1;
    if (type == typeNormal) {
      count = 1;
    } else if (type == typeVIP) {
      count = 3;
    } else if (type == typeSVIP) {
      count = 5;
    }
    SpUtil.putInt(spAccountCount, count);
  }

  static void updateMaxAccount(int count) {

    SpUtil.putInt(spAccountCount, count);
  }

  MultiAccountUserInfoViewModel() {
    try {
      List<dynamic>? tempTokenList = jsonDecode(SpUtil.getString(spTokenBeanList, defValue: '[]'));

      if (tempTokenList != null && tempTokenList.isNotEmpty) {
        for (Map<String, dynamic> value in tempTokenList) {
          //把token里的空数据拿出
          var bean = TokenBean.fromJson(value);
          if (bean.host == null && bean.token == null) continue;
          tokenBeans.add(TokenBean.fromJson(value));
        }
      }

      List<dynamic>? tempList = jsonDecode(SpUtil.getString(spLoginHistory, defValue: '[]'));

      if (tempList != null && tempList.isNotEmpty) {
        for (Map<String, dynamic> value in tempList) {
          historyAccounts.add(UserInfoBean.fromJson(value));
        }
      }
    } catch (e) {
      e.toString().toast2();
    }
  }

  void initVipState() {
    int vipType = SpUtil.getInt(spVIP, defValue: typeNormal);

    if (vipType == typeNormal) {
      maxAccount = 1;
    } else if (vipType == typeVIP) {
      maxAccount = 3;
    } else {
      maxAccount = SpUtil.getInt(spAccountCount, defValue: 5);
    }
  }

  void save2HistoryAccount(UserInfoBean userInfoBean) {
    //如果已经存在host，那就更�?

    historyAccounts.removeWhere((element) => element.host == userInfoBean.host);

    historyAccounts.insert(
      0,
      userInfoBean,
    );

    SpUtil.putString(spLoginHistory, jsonEncode(historyAccounts));
  }

  void removeHistoryAccount(String? host) {
    if (host == null || host.isEmpty) return;

    historyAccounts.removeWhere((element) => element.host == host);

    SpUtil.putString(spLoginHistory, jsonEncode(historyAccounts));
  }

  void updateToken(int index, String? host, String? token, bool useSecretLogined, String? alias) {
    if (host == null) return;

    if (MultiAccountUserInfoViewModel.maxAccount == 1) {
      tokenBeans.clear();
      tokenBeans.add(
        TokenBean(
          token: token,
          host: host,
          useSecretLogined: useSecretLogined,
          alias: alias,
        ),
      );
    } else {
      if (tokenBeans.length <= index) {
        tokenBeans.add(
          TokenBean(
            token: token,
            host: host,
            useSecretLogined: useSecretLogined,
            alias: alias,
          ),
        );
      } else {
        tokenBeans[index].token = token;
        tokenBeans[index].useSecretLogined = useSecretLogined;
        tokenBeans[index].alias = alias;
        tokenBeans[index].host = host;
      }
    }
    SpUtil.putString(spTokenBeanList, jsonEncode(tokenBeans));
  }

  void removeTokenBean(int index) {
    tokenBeans[index].token = null;
    tokenBeans[index].host = null;
    tokenBeans[index].alias = null;
    tokenBeans[index].useSecretLogined = false;
    SpUtil.putString(spTokenBeanList, jsonEncode(tokenBeans));
  }

  /// 更新指定账号的别名，同时持久化到 tokenBeans 和 historyAccounts。
  /// 仅按 host 匹配更新别名，不改变 historyAccounts 的顺序。
  /// 用于「修改名称」场景，确保两份存储同步，避免重启后丢失。
  void updateAliasForHost(String? host, String? alias) {
    if (host == null || host.isEmpty) return;

    bool tokenChanged = false;
    for (var bean in tokenBeans) {
      if (bean.host == host) {
        bean.alias = alias;
        tokenChanged = true;
      }
    }
    if (tokenChanged) {
      SpUtil.putString(spTokenBeanList, jsonEncode(tokenBeans));
    }

    bool historyChanged = false;
    for (var bean in historyAccounts) {
      if (bean.host == host) {
        bean.alias = alias;
        historyChanged = true;
      }
    }
    if (historyChanged) {
      SpUtil.putString(spLoginHistory, jsonEncode(historyAccounts));
    }
  }

  void resetTokenBeans(List<TokenBean> bean) {
    SpUtil.putString(spTokenBeanList, jsonEncode(bean));
    tokenBeans.clear();
    tokenBeans.addAll(bean);
  }

  // ------------------------------------------------------------------
  // 记忆上次使用的账号容器
  //
  // 存 host + alias 组成的业务键，而不是槽位下标：账号排序、删除后
  // 下标会整体位移，只有按身份重新定位才能准确还原"关闭前是哪个账号"。
  // 多个账号登录同一面板（host 相同）时用 alias 区分；alias 为空则视为
  // 同一个账号（青龙同 host 不同账号 = 不同面板用户，属于极少见组合）。
  // ------------------------------------------------------------------

  /// 生成账号业务键
  static String accountKeyOf(String? host, String? alias) {
    final String h = (host ?? "").trim();
    if (h.isEmpty) return "";
    return "$h|${(alias ?? "").trim()}";
  }

  /// 记录当前正在使用的账号
  void saveLastActiveAccount(String? host, String? alias) {
    final String key = accountKeyOf(host, alias);
    if (key.isEmpty) return;
    SpUtil.putString(spLastActiveAccount, key);
  }

  String get lastActiveAccountKey =>
      SpUtil.getString(spLastActiveAccount, defValue: "");

  /// 把上次使用的账号键转成当前槽位下标；
  /// 找不到（账号被删）返回 null，调用方自行兜底。
  ///
  /// 两级匹配：先精确匹配 host+alias，再退化为仅匹配 host
  /// （用户重启前改过别名时仍能还原到同一面板）。
  int? lastActiveSlotIndex() {
    final String key = lastActiveAccountKey;
    if (key.isEmpty) return null;
    final int sep = key.indexOf("|");
    final String host = sep >= 0 ? key.substring(0, sep) : key;
    final String alias = sep >= 0 ? key.substring(sep + 1) : "";
    if (host.isEmpty) return null;

    int? hostOnly;
    for (int i = 0; i < tokenBeans.length; i++) {
      final TokenBean bean = tokenBeans[i];
      if ((bean.host ?? "").isEmpty) continue;
      if (bean.host != host) continue;
      if ((bean.alias ?? "").trim() == alias) return i;
      hostOnly ??= i;
    }
    return hostOnly;
  }

  /// 当前槽位下标对应的业务键（用于写回）
  String? accountKeyAt(int index) {
    if (index < 0 || index >= tokenBeans.length) return null;
    final TokenBean bean = tokenBeans[index];
    if ((bean.host ?? "").isEmpty) return null;
    return accountKeyOf(bean.host, bean.alias);
  }
}
