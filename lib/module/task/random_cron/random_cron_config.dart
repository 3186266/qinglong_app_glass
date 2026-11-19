import 'dart:convert';
import 'dart:math';

import 'package:qinglong_app/utils/sp_utils.dart';

/// 随机定时的档位（对应编辑页上的「随机 / 额外随机」）
enum RandomCronMode {
  /// 随机：每个时间段内随机挑小时，分钟在组内按最小间隔错开
  random,

  /// 额外随机：在随机结果上再叠加分钟抖动，不容易被"整点规律"看出来
  extraRandom,
}

/// 随机定时的一个时间段：在 [startHour] 点到 [endHour] 点之间跑 [runCount] 次。
class CronTimeSegment {
  int startHour;
  int endHour;
  int runCount;

  CronTimeSegment({
    this.startHour = 9,
    this.endHour = 23,
    this.runCount = 1,
  });

  CronTimeSegment copy() => CronTimeSegment(
    startHour: startHour,
    endHour: endHour,
    runCount: runCount,
  );

  Map<String, dynamic> toJson() => {
    'start': startHour,
    'end': endHour,
    'count': runCount,
  };

  static CronTimeSegment fromJson(Map<String, dynamic> json) => CronTimeSegment(
    startHour: (json['start'] as num?)?.toInt() ?? 9,
    endHour: (json['end'] as num?)?.toInt() ?? 23,
    runCount: (json['count'] as num?)?.toInt() ?? 1,
  );
}

/// 随机定时配置。
///
/// 设计约定：cron 只有 5 段，分钟与小时是"笛卡尔积"关系
/// （`10,40 9,14 * * *` 实际是 4 次而不是 2 次），所以这里统一让
/// **分钟只取一个值**、小时取多个值，保证实际运行次数 = 各段 runCount 之和。
class RandomCronConfig {
  bool enabled;
  RandomCronMode mode;

  /// 时间段列表（至少一个）
  List<CronTimeSegment> segments;

  /// 分组名：同组任务的分钟会按 [minGapMin] 依次错开，避免同时打面板
  String group;

  /// 最小间隔（分钟）
  int minGapMin;

  RandomCronConfig({
    this.enabled = false,
    this.mode = RandomCronMode.random,
    List<CronTimeSegment>? segments,
    this.group = '',
    this.minGapMin = 30,
  }) : segments = segments ?? [CronTimeSegment()];

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'mode': mode.index,
    'group': group,
    'gap': minGapMin,
    'segments': segments.map((e) => e.toJson()).toList(),
  };

  static RandomCronConfig fromJson(Map<String, dynamic> json) {
    final List<dynamic> raw = (json['segments'] as List<dynamic>?) ?? const [];
    return RandomCronConfig(
      enabled: json['enabled'] as bool? ?? false,
      mode:
          (json['mode'] as num?)?.toInt() == RandomCronMode.extraRandom.index
              ? RandomCronMode.extraRandom
              : RandomCronMode.random,
      group: json['group'] as String? ?? '',
      minGapMin: (json['gap'] as num?)?.toInt() ?? 30,
      segments:
          raw.isEmpty
              ? [CronTimeSegment()]
              : raw
                  .map((e) => CronTimeSegment.fromJson(e as Map<String, dynamic>))
                  .toList(),
    );
  }

  RandomCronConfig copy() => RandomCronConfig(
    enabled: enabled,
    mode: mode,
    group: group,
    minGapMin: minGapMin,
    segments: segments.map((e) => e.copy()).toList(),
  );

  /// 单行摘要，给编辑页在输入框下方显示
  String get summary {
    final String segs =
        segments
            .map(
              (s) =>
                  '${_two(s.startHour)}-${_two(s.endHour)} 时 ${s.runCount} 次',
            )
            .join('、');
    final String modeName =
        mode == RandomCronMode.extraRandom ? '额外随机' : '随机';
    final String gap = group.trim().isEmpty ? '' : ' · 分组 ${group.trim()} 错开 $minGapMin 分';
    return '$modeName · $segs$gap';
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
}

/// 随机 cron 生成器。
///
/// 所有状态都落在 SharedPreferences：
/// - 配置按「面板 + 任务名」记忆，下次编辑同一任务能回填
/// - 分组按「面板 + 组名」记住已分配槽位数，保证同组任务依次错开
class RandomCronGenerator {
  static const String _cfgPrefix = 'spRandomCronCfg';
  static const String _slotPrefix = 'spRandomCronSlot';

  static String _cfgKey(int panelIndex, String taskName) =>
      '${_cfgPrefix}_${panelIndex}_$taskName';

  static String _slotKey(int panelIndex, String group) =>
      '${_slotPrefix}_${panelIndex}_$group';

  /// 读取某任务上次保存的随机配置（没有则返回未启用状态）
  static RandomCronConfig loadConfig(int panelIndex, String taskName) {
    final String raw = SpUtil.getString(_cfgKey(panelIndex, taskName));
    if (raw.isEmpty) return RandomCronConfig();
    try {
      return RandomCronConfig.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return RandomCronConfig();
    }
  }

  /// 记住某任务的随机配置（保存成功后调用）
  static void saveConfig(
    int panelIndex,
    String taskName,
    RandomCronConfig config,
  ) {
    if (taskName.trim().isEmpty) return;
    SpUtil.putString(
      _cfgKey(panelIndex, taskName),
      jsonEncode(config.toJson()),
    );
  }

  /// 清除某任务的随机配置（用户关掉随机定时后调用）
  static void clearConfig(int panelIndex, String taskName) {
    if (taskName.trim().isEmpty) return;
    SpUtil.remove(_cfgKey(panelIndex, taskName));
  }

  /// 按配置生成一条 cron 表达式。
  ///
  /// [panelIndex] 用于把不同面板的分组槽位隔离开，缺失时按 0 处理。
  static String generate(
    RandomCronConfig config, {
    int panelIndex = 0,
    String taskName = '',
  }) {
    final Random random = Random();
    final List<CronTimeSegment> segments =
        config.segments.isEmpty ? [CronTimeSegment()] : config.segments;

    // 分组错开：同组第 n 个任务整体顺延 n × 最小间隔（分钟），
    // 超出 60 分自动折成小时位移，因此任意间隔都能表达
    final String group = config.group.trim();
    final int gap = config.minGapMin <= 0 ? 30 : config.minGapMin;
    int slot = 0;
    if (group.isNotEmpty) {
      slot = SpUtil.getInt(_slotKey(panelIndex, group), defValue: 0);
      SpUtil.putInt(_slotKey(panelIndex, group), slot + 1);
    }
    final int offsetTotal = slot * gap;
    final int shiftHour = (offsetTotal ~/ 60) % 24;
    final int shiftMinute = offsetTotal % 60;

    // 分钟：随机一段底数，再叠加分组错开位移与抖动，最终只取一个值
    int minute = random.nextInt(60);
    if (config.mode == RandomCronMode.extraRandom) {
      minute = (minute + random.nextInt(10)) % 60;
    }
    minute = (minute + shiftMinute) % 60;

    final Set<int> hours = {};
    for (final CronTimeSegment seg in segments) {
      final int start = min(seg.startHour, seg.endHour).clamp(0, 23);
      final int end = max(seg.startHour, seg.endHour).clamp(0, 23);
      final int span = end - start + 1;
      final int count = seg.runCount.clamp(1, span);
      final List<int> pool = List<int>.generate(span, (i) => start + i)
        ..shuffle(random);
      for (final int h in pool.take(count)) {
        hours.add((h + shiftHour) % 24);
      }
    }

    final List<int> hourList = hours.toList()..sort();
    final String hourPart =
        hourList.isEmpty ? '0' : hourList.map((e) => e.toString()).join(',');
    return '${minute.toString()} $hourPart * * *';
  }

  /// 生成时把当前时间也告诉调用方，便于 toast 提示
  static String describe(String cron) => cron;
}
