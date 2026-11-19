
import 'package:flutter/widgets.dart';

import '../tree_node.dart';

/// Defines the data used to display a [TreeNode].
///
/// Used by [TreeView] to display a [TreeNode].
///
/// This object allows the creation of key, label and icon to display
/// a node on the [TreeView] widget. The key and label properties are
/// required. The key is needed for events that occur on the generated
/// [TreeNode]. It should always be unique.
class ScriptData {
  final String key;

  final String title;
  final String type;

  final bool expanded;

  final List<ScriptData> children;

  final String parent;

  /// 文件/目录创建时间（毫秒时间戳）。
  ///
  /// 由青龙 `/api/scripts` 的 `createTime` 字段（服务端取 `birthtime`）提供，
  /// 用于「按时间排序」。老版本面板或底层文件系统不支持 birthtime 时为 0，
  /// 此时排序会回退到按名称。
  final int createTime;

  /// 文件大小（字节）。目录无此字段，为 null。
  final int? size;

  ScriptData({
    required this.key,
    required this.title,
    required this.type,
    this.children = const [],
    this.expanded = false,
    this.parent = "",
    this.createTime = 0,
    this.size,
  });

  static ScriptData jsonConversion(Map<String, dynamic> json) {
    return ScriptData.fromMap(json);
  }

  /// Creates a [ScriptData] from a `Map<String, dynamic>` map. The map
  /// should contain a "label" value. If the key value is
  /// missing, it generates a unique key.
  /// If the expanded value, if present, can be any 'truthful'
  /// value. Excepted values include: 1, yes, true and their
  /// associated string values.
  static ScriptData fromMap(Map<String, dynamic> map) {
    String? key = map['key'];
    String? title = map['title'];

    String? parent = map['parent'];
    List<ScriptData> children = [];

    // if (map['icon'] != null) {
    // int _iconData = int.parse(map['icon']);
    // if (map['icon'].runtimeType == String) {
    //   _iconData = int.parse(map['icon']);
    // } else if (map['icon'].runtimeType == double) {
    //   _iconData = (map['icon'] as double).toInt();
    // } else {
    //   _iconData = map['icon'];
    // }
    // _icon = const IconData(_iconData);
    // }
    if (map['children'] != null) {
      List<Map<String, dynamic>> childrenMap = List.from(map['children']);
      children = childrenMap.map((Map<String, dynamic> child) => ScriptData.fromMap(child)).toList();
    }
    String? type = map['type'];

    if (type == null || type.isEmpty) {
      if (children.isNotEmpty) {
        type = "directory";
      } else {
        type = "file";
      }
    }

    return ScriptData(
      key: '$key',
      title: title ?? "",
      type: type,
      expanded: false,
      parent: parent ?? "",
      children: children,
      createTime: _readInt(map['createTime']),
      size: map['size'] == null ? null : _readInt(map['size']),
    );
  }

  /// 宽松解析服务端返回的数字字段：兼容 int / double / 数字字符串，
  /// 无法解析时返回 0（而不是抛异常），避免单个脏字段整棵树解析失败。
  static int _readInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  /// Creates a copy of this object but with the given fields
  /// replaced with the new values.
  ScriptData copyWith({
    String? key,
    String? title,
    String? type,
    List<ScriptData>? children,
    bool? expanded,
    String? parent,
    IconData? icon,
    Color? iconColor,
    Color? selectedIconColor,
    int? createTime,
    int? size,
  }) =>
      ScriptData(
        key: key ?? this.key,
        title: title ?? this.title,
        type: type ?? this.type,
        expanded: expanded ?? this.expanded,
        parent: parent ?? this.parent,
        children: children ?? this.children,
        createTime: createTime ?? this.createTime,
        size: size ?? this.size,
      );

  /// 是否携带可用的创建时间（用于判断「按时间排序」是否真的有效）
  bool get hasCreateTime => createTime > 0;

  /// Whether this object has children [ScriptData].
  bool get isParent => type == "directory";

  @override
  String toString() {
    return "";
  }

  @override
  int get hashCode {
    return Object.hash(
      key,
      title,
      expanded,
      parent,
      children,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other.runtimeType != runtimeType) return false;
    return other is ScriptData &&
        other.key == key &&
        other.title == title &&
        other.expanded == expanded &&
        other.parent == parent &&
        other.children.length == children.length;
  }
}
