/// singcast-cli returns: {"tag": string, "type": string}
class ProxyGroupItem {
  final String tag;
  final String type;

  ProxyGroupItem({required this.tag, this.type = ''});

  factory ProxyGroupItem.fromJson(Map<String, dynamic> json) => ProxyGroupItem(
    tag: json['tag'] as String? ?? '',
    type: json['type'] as String? ?? '',
  );
}

/// singcast-cli returns:
/// {"tag": string, "type": string, "selectable": bool, "selected": string,
///  "items": [ProxyGroupItem, ...]}
class ProxyGroup {
  final String tag;
  final String type;
  final bool selectable;
  final String selected;
  final List<ProxyGroupItem> items;

  ProxyGroup({
    required this.tag,
    this.type = '',
    this.selectable = false,
    this.selected = '',
    this.items = const [],
  });

  factory ProxyGroup.fromJson(Map<String, dynamic> json) => ProxyGroup(
    tag: json['tag'] as String? ?? '',
    type: json['type'] as String? ?? '',
    selectable: json['selectable'] as bool? ?? false,
    selected: json['selected'] as String? ?? '',
    items:
        (json['items'] as List?)
            ?.map((e) => ProxyGroupItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
  );
}
