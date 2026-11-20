import 'package:qinglong_app/module/others/task_log/task_log_bean.dart';

/// 今日运行记录（青龙 2.21 及更早版本的降级数据源）
///
/// 为什么需要它：
///   青龙在 2.22 才提供 /api/dashboard/successes 与 /api/dashboard/failures
///   （任务级「今日成功 N 次 / 今日失败 N 次」明细）。2.21 及更早版本的面板
///   仪表盘只返回 overview 里的汇总数字（todayRuns / todaySuccess / todayFail），
///   拿不到「具体是哪些任务」。
///
/// 但 2.21 每次执行任务都会落一个日志文件：
///   ${logPath}/${uniqPath}/${yyyy-MM-dd-HH-mm-ss-SSS}.log
/// 文件名前 10 位就是执行日期、后面是执行时刻。于是可以遍历 /api/logs 的目录树，
/// 把所有「今天」的日志按任务目录聚合，得到：
///   - 今天有哪些任务跑过
///   - 每个任务今天跑了几次
///   - 最近一次的执行时刻
/// 再配合 overview 的 todaySuccess / todayFail，就能把「今日成功 / 今日失败」
/// 两块卡片在 2.21 上也填上真实内容，而不是一句「版本过低」。
///
/// 注意：日志文件名只有时间没有退出码，单条日志的成败无法离线判定，
/// 因此这里只呈现「运行记录」，成败仍以 overview 的汇总数字为准。
class DashboardTodayRun {
  /// /logs 下的目录名，形如 `jd_bean_12`（脚本名 + _任务id）
  final String dir;

  /// 展示名：能对上定时任务就用任务名，否则用目录名
  final String name;

  /// 从目录名后缀解析出的任务 id（解析不到为 0）
  final int cronId;

  /// 今日运行次数
  final int count;

  /// 最近一次执行时刻（HH:mm:ss）
  final String lastTime;

  const DashboardTodayRun({
    required this.dir,
    required this.name,
    required this.cronId,
    required this.count,
    required this.lastTime,
  });
}

/// 今天的日期前缀，与青龙日志文件名 `yyyy-MM-dd-HH-mm-ss-SSS.log` 对齐
String todayLogDatePrefix([DateTime? now]) {
  final DateTime d = now ?? DateTime.now();
  final String m = d.month.toString().padLeft(2, '0');
  final String day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}

/// 由日志目录名解析任务 id：`jd_bean_12` -> 12
int cronIdFromLogDir(String dir) {
  final RegExpMatch? m = RegExp(r'_(\d+)$').firstMatch(dir);
  if (m == null) return 0;
  return int.tryParse(m.group(1) ?? '') ?? 0;
}

/// 日志文件名 `2026-11-20-09-12-33-123.log` -> `09:12:33`
String logTimeOf(String fileName) {
  final RegExpMatch? m = RegExp(
    r'^\d{4}-\d{2}-\d{2}-(\d{2})-(\d{2})-(\d{2})',
  ).firstMatch(fileName);
  if (m == null) return '';
  return '${m.group(1)}:${m.group(2)}:${m.group(3)}';
}

/// 把 /api/logs 的目录树聚合成今日运行记录
///
/// [namesByCronId] 传入 `{任务id: 任务名}`，用于把 `jd_bean_12` 显示成人类可读的名字。
List<DashboardTodayRun> buildTodayRuns(
  List<TaskLogBean>? dirs, {
  Map<int, String> namesByCronId = const {},
  DateTime? now,
}) {
  if (dirs == null || dirs.isEmpty) return const [];
  final String prefix = todayLogDatePrefix(now);

  final List<DashboardTodayRun> result = [];
  for (final TaskLogBean dir in dirs) {
    final String dirName = dir.name ?? '';
    if (dirName.isEmpty) continue;

    int count = 0;
    String lastTime = '';
    String lastFile = '';

    void take(String file) {
      if (file.isEmpty || !file.startsWith(prefix)) return;
      count++;
      // 文件名字典序即时间序，取最大的那个当「最近一次」
      if (file.compareTo(lastFile) > 0) {
        lastFile = file;
        lastTime = logTimeOf(file);
      }
    }

    for (final String f in dir.files ?? const <String>[]) {
      take(f);
    }
    for (final Children c in dir.children ?? const <Children>[]) {
      if ((c.type ?? '') == 'directory') continue;
      take(c.title ?? c.value ?? '');
    }

    if (count == 0) continue;

    final int id = cronIdFromLogDir(dirName);
    final String mapped = namesByCronId[id] ?? '';
    result.add(
      DashboardTodayRun(
        dir: dirName,
        name: mapped.isNotEmpty ? mapped : dirName,
        cronId: id,
        count: count,
        lastTime: lastTime,
      ),
    );
  }

  // 跑得多的排前面；同次数按最近时间倒序
  result.sort((a, b) {
    final int byCount = b.count.compareTo(a.count);
    if (byCount != 0) return byCount;
    return b.lastTime.compareTo(a.lastTime);
  });
  return result;
}
