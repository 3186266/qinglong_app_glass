import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qinglong_app/base/app_colors.dart';
import 'package:qinglong_app/base/theme.dart';
import 'package:qinglong_app/base/ui/glow_sheet.dart';
import 'package:qinglong_app/base/ui/spring_sheet.dart';

import 'random_cron_config.dart';

/// 打开随机定时配置面板；「应用」返回新配置，直接关闭返回 null。
Future<RandomCronConfig?> showRandomCronSheet(
  BuildContext context,
  RandomCronConfig initial,
) {
  return showSpringSheet<RandomCronConfig>(
    context: context,
    builder:
        (ctx) => _RandomCronSheetBody(initial: initial.copy()),
  );
}

class _RandomCronSheetBody extends ConsumerStatefulWidget {
  final RandomCronConfig initial;

  const _RandomCronSheetBody({required this.initial});

  @override
  ConsumerState<_RandomCronSheetBody> createState() =>
      _RandomCronSheetBodyState();
}

class _RandomCronSheetBodyState extends ConsumerState<_RandomCronSheetBody> {
  late RandomCronConfig config;
  late final TextEditingController groupController;
  late final TextEditingController gapController;

  @override
  void initState() {
    super.initState();
    config = widget.initial;
    groupController = TextEditingController(text: config.group);
    gapController = TextEditingController(text: config.minGapMin.toString());
  }

  @override
  void dispose() {
    groupController.dispose();
    gapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isCyber = ref.read(themeProvider).themeMode == modeCyber;
    final Color accent =
        isCyber ? CyberColors.cyan : ref.watch(themeProvider).primaryColor;
    final Color titleColor =
        isCyber ? CyberColors.titleWhite : AppleColors.textPrimary;
    final Color descColor =
        isCyber ? CyberColors.idleGray : const Color(0xFF8A8A8E);
    final Color fieldBg =
        isCyber ? const Color(0xFF1A1F26) : const Color(0xFFF5F5F7);
    final Color borderColor =
        isCyber ? const Color(0x33FFFFFF) : const Color(0xFFE5E5EA);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: GlowSheetContainer(
          isCyber: isCyber,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.82,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DragHandle(isCyber: isCyber),
                // 标题
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '随机定时',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: titleColor,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(
                            CupertinoIcons.xmark_circle_fill,
                            size: 22,
                            color: descColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _hintBox(
                          isCyber: isCyber,
                          accent: accent,
                          descColor: descColor,
                          text:
                              '保存任务时按下面的规则随机生成定时，每次保存都会重新随机。'
                              '同分组任务按最小间隔依次错开，避免同时请求面板。',
                        ),
                        const SizedBox(height: 14),
                        _label('定时类型', titleColor),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _modeChip(
                              '随机',
                              RandomCronMode.random,
                              accent: accent,
                              fieldBg: fieldBg,
                              borderColor: borderColor,
                              titleColor: titleColor,
                            ),
                            const SizedBox(width: 10),
                            _modeChip(
                              '额外随机',
                              RandomCronMode.extraRandom,
                              accent: accent,
                              fieldBg: fieldBg,
                              borderColor: borderColor,
                              titleColor: titleColor,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _label('时间段', titleColor),
                        const SizedBox(height: 8),
                        ...List.generate(
                          config.segments.length,
                          (i) => _segmentRow(
                            i,
                            accent: accent,
                            fieldBg: fieldBg,
                            borderColor: borderColor,
                            titleColor: titleColor,
                            descColor: descColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        _addSegmentButton(
                          accent: accent,
                          isCyber: isCyber,
                        ),
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _label('分组（同组错开）', titleColor),
                                  const SizedBox(height: 8),
                                  _textField(
                                    controller: groupController,
                                    hint: '选填，如：天猫、京东',
                                    icon: CupertinoIcons.person_2,
                                    fieldBg: fieldBg,
                                    borderColor: borderColor,
                                    titleColor: titleColor,
                                    descColor: descColor,
                                    onChanged: (v) => config.group = v,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _label('最小间隔', titleColor),
                                  const SizedBox(height: 8),
                                  _textField(
                                    controller: gapController,
                                    hint: '30',
                                    suffix: '分钟',
                                    keyboardType: TextInputType.number,
                                    fieldBg: fieldBg,
                                    borderColor: borderColor,
                                    titleColor: titleColor,
                                    descColor: descColor,
                                    onChanged: (v) => config.minGapMin =
                                        int.tryParse(v.trim()) ?? 30,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '说明：分钟只取一个值、小时取多个值——cron 的分钟与小时是'
                          '笛卡尔积，这样写才能保证每天实际运行次数等于上面各段次数之和。',
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.5,
                            color: descColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // 底部按钮
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: Container(
                            height: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: fieldBg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: borderColor),
                            ),
                            child: Text(
                              '取消',
                              style: TextStyle(
                                fontSize: 15,
                                color: titleColor,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            config.group = groupController.text.trim();
                            config.minGapMin =
                                int.tryParse(gapController.text.trim()) ?? 30;
                            if (config.minGapMin <= 0) config.minGapMin = 30;
                            config.enabled = true;
                            Navigator.of(context).pop(config);
                          },
                          child: Container(
                            height: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: accent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              '应用',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text, Color color) => Text(
    text,
    style: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: color,
    ),
  );

  Widget _hintBox({
    required bool isCyber,
    required Color accent,
    required Color descColor,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: isCyber ? 0.10 : 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(CupertinoIcons.info_circle, size: 15, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, height: 1.5, color: descColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeChip(
    String label,
    RandomCronMode mode, {
    required Color accent,
    required Color fieldBg,
    required Color borderColor,
    required Color titleColor,
  }) {
    final bool selected = config.mode == mode;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => config.mode = mode);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? accent : fieldBg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? accent : borderColor),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? Colors.white : titleColor,
          ),
        ),
      ),
    );
  }

  Widget _segmentRow(
    int index, {
    required Color accent,
    required Color fieldBg,
    required Color borderColor,
    required Color titleColor,
    required Color descColor,
  }) {
    final CronTimeSegment seg = config.segments[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text(
              '段${index + 1}',
              style: TextStyle(fontSize: 12, color: descColor),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                _hourDropdown(
                  seg.startHour,
                  (v) => setState(() => seg.startHour = v),
                  fieldBg: fieldBg,
                  borderColor: borderColor,
                  titleColor: titleColor,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '至',
                    style: TextStyle(fontSize: 12, color: descColor),
                  ),
                ),
                _hourDropdown(
                  seg.endHour,
                  (v) => setState(() => seg.endHour = v),
                  fieldBg: fieldBg,
                  borderColor: borderColor,
                  titleColor: titleColor,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '时',
                    style: TextStyle(fontSize: 12, color: descColor),
                  ),
                ),
                _countDropdown(
                  seg.runCount,
                  (v) => setState(() => seg.runCount = v),
                  fieldBg: fieldBg,
                  borderColor: borderColor,
                  titleColor: titleColor,
                  accent: accent,
                ),
              ],
            ),
          ),
          if (config.segments.length > 1)
            GestureDetector(
              onTap: () => setState(() => config.segments.removeAt(index)),
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(
                  CupertinoIcons.minus_circle,
                  size: 20,
                  color: descColor,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _hourDropdown(
    int value,
    ValueChanged<int> onChanged, {
    required Color fieldBg,
    required Color borderColor,
    required Color titleColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: fieldBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: value,
          isDense: true,
          iconSize: 18,
          style: TextStyle(fontSize: 13, color: titleColor),
          dropdownColor: fieldBg,
          items: List.generate(
            24,
            (i) => DropdownMenuItem<int>(
              value: i,
              child: Text(i.toString().padLeft(2, '0')),
            ),
          ),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }

  Widget _countDropdown(
    int value,
    ValueChanged<int> onChanged, {
    required Color fieldBg,
    required Color borderColor,
    required Color titleColor,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: fieldBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: value.clamp(1, 8),
          isDense: true,
          iconSize: 18,
          style: TextStyle(fontSize: 13, color: accent),
          dropdownColor: fieldBg,
          items: List.generate(
            8,
            (i) => DropdownMenuItem<int>(
              value: i + 1,
              child: Text(
                '运行${i + 1}次',
                style: TextStyle(fontSize: 13, color: accent),
              ),
            ),
          ),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }

  Widget _addSegmentButton({required Color accent, required bool isCyber}) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          if (config.segments.length < 6) {
            config.segments.add(CronTimeSegment());
          }
        });
      },
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: isCyber ? 0.10 : 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(CupertinoIcons.add, size: 15, color: accent),
            const SizedBox(width: 4),
            Text(
              '添加时间段',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    required Color fieldBg,
    required Color borderColor,
    required Color titleColor,
    required Color descColor,
    IconData? icon,
    String? suffix,
    TextInputType? keyboardType,
    ValueChanged<String>? onChanged,
  }) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: fieldBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: descColor),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              onChanged: onChanged,
              style: TextStyle(fontSize: 13, color: titleColor),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: hint,
                hintStyle: TextStyle(fontSize: 13, color: descColor),
              ),
            ),
          ),
          if (suffix != null)
            Text(
              suffix,
              style: TextStyle(fontSize: 12, color: descColor),
            ),
        ],
      ),
    );
  }
}
