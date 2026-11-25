const String spLoginHistory = "loginHistory";
const String spTokenBeanList = "spTokenBeanList";
const String spAccountCount = "spAccountCount";

/// 上次退出时正在使用的账号（业务键 "host|alias"，见 AccountPersistKey）
///
/// 存身份而不是槽位下标：账号排序 / 删除后槽位会变，按 host(+alias)
/// 重新定位才能准确还原用户关闭前看到的那个容器。
const String spLastActiveAccount = "spLastActiveAccount";
const String spVIP = "spvip";
const String spVIPLOGO = "spviplogo";
const String spVIPLOGOChangeReminder = "spVIPLOGOChangeReminder";
const String spOpenAuth = "spOpenAuth";
const String spPoetToken = "spPoetToken";

const typeNormal = 0;
const typeVIP = 10;
const typeSVIP = 12531;

const String spEnvBackTime = "envBackTime";
const String spSubscribeBackTime = "subscribeBackTime";
const String spConfigBackTime = "configBackTime";
const String spICloud = "spICloud";
const String spShowLine = "spShowLine";
const String spUseWebCodeEditor = "spUseWebCodeEditor";
const String spAutoShowLog = "spAutoShowLog";
const String spVersioCodeHistory = "spVersioCodeHistory";
const String spLocalBackUpFileExperiedTime = "spLocalBackUpFileExperiedTime";
const String spThemeStyle = "spThemeStyle";
const String spThemeFollowSystem = "spThemeFollowSystem";
const String spTextScaleFactor = "spTextScaleFactor";
// 全局字体粗细（int：400/500/600/700，全局单一值，不分赛博/主题版）
const String spTextFontWeight = "spTextFontWeight";
// 赛博模式自定义字体颜色（与主题版独立，两主题颜色互斥）
const String spCyberPrimaryTextColor = "spCyberPrimaryTextColor";
const String spCyberSecondaryTextColor = "spCyberSecondaryTextColor";
// 非赛博模式（主题版）自定义字体颜色
const String spThemePrimaryTextColor = "spThemePrimaryTextColor";
const String spThemeSecondaryTextColor = "spThemeSecondaryTextColor";
const String spLogAutoJump2Bottom = "spLogAutoJump2Bottom";
// 页面转场动画（bool，默认 false=容器展开：从点击卡片展开/返回收回原处）
// true = 经典右侧滑入（CupertinoPageRoute）
const String spClassicPageTransition = "spClassicPageTransition";
const String spAndroidKeyboardError = "spAndroidKeyboardError";
const String spSingleInstance = "spSingleInstance";

/// 脚本管理列表排列方式（int）
///
/// 0 = 按名称（A→Z，目录始终在前，与青龙网页端默认一致）
/// 1 = 按时间（新→旧）
/// 2 = 按时间（旧→新）
const String spScriptSortMode = "spScriptSortMode";

/// 毛玻璃效果开关（bool，默认 true=开启）
///
/// true  = 透明背景 + BackdropFilter 高斯模糊（毛玻璃）
/// false = 纯色背景（不透明），不使用 BackdropFilter（GPU 零开销）
/// 用户可在「系统设置 → 通用功能 → 毛玻璃效果」中开关。
const String spBlurEffect = "spBlurEffect";

// ==== WebDAV 云备份（青龙 2.x 客户端，方案见 docs/云备份方案.md）====
const String spWebDavUrl =
    "spWebDavUrl"; // 服务器地址，如 https://dav.jianguoyun.com/dav/
const String spWebDavUser = "spWebDavUser"; // 账号
const String spWebDavPassword = "spWebDavPassword"; // 应用密码（坚果云为专用应用密码）
const String spWebDavDir = "spWebDavDir"; // 远程目录，默认 /qinglong_app_backup
const String spWebDavEncryptPass = "spWebDavEncryptPass"; // 备份加密口令
const String spWebDavAuto = "spWebDavAuto"; // 自动备份开关，默认关
const String spWebDavLastBackTime = "spWebDavLastBackTime"; // 上次手动备份时间
const String spWebDavLastAutoBackTime =
    "spWebDavLastAutoBackTime"; // 上次自动备份时间（防抖用，ISO 时间）

// 脚本/配置「下载」上一次用户选择的保存目录（iOS 保存面板的起始位置）
const String spLastSaveDirectory = "spLastSaveDirectory";
