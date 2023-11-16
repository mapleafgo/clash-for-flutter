import 'package:clash_for_flutter/app/enum/type_enum.dart';
import 'package:clash_for_flutter/app/pages/profiles/profiles_controller.dart';
import 'package:clash_for_flutter/app/utils/utils.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:timeago/timeago.dart' as timeago;

class SelectableCard extends StatelessWidget {
  final bool selected;
  final ProfileShow profile;
  final bool isLoading;
  final VoidCallback onTap;
  final VoidCallback onUpdate;
  final VoidCallback onEdit;
  final VoidCallback onChangeName;
  final VoidCallback onRemove;

  const SelectableCard({
    super.key,
    required this.profile,
    this.selected = false,
    this.isLoading = false,
    required this.onTap,
    required this.onUpdate,
    required this.onEdit,
    required this.onChangeName,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: const BorderRadius.all(Radius.circular(10)),
      onTap: () {
        onTap();
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: selected ? Theme.of(context).colorScheme.primary : null,
        ),
        child: Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  brightness: Theme.of(context).brightness,
                  onSurface: selected ? Colors.white : null,
                  primary: selected ? Colors.orange : null,
                ),
            textSelectionTheme: TextSelectionThemeData(
              selectionColor: selected ? Colors.white : null,
            ),
          ),
          child: Builder(
            builder: (ctx) {
              List<Widget> list = [
                Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Text(
                      profile.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(ctx).textSelectionTheme.selectionColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4, left: 8),
                        child: Text(
                          maxLines: 1,
                          profile.type.value,
                          style: Theme.of(ctx)
                              .textTheme
                              .titleSmall
                              ?.copyWith(color: Theme.of(ctx).textSelectionTheme.selectionColor),
                        ),
                      ),
                    ),
                    Text(
                      timeago.format(profile.lastUpdate, locale: "zh_cn"),
                      style: Theme.of(ctx)
                          .textTheme
                          .titleMedium
                          ?.copyWith(color: Theme.of(ctx).textSelectionTheme.selectionColor),
                    ),
                  ],
                )
              ];

              List<Widget> expireRow = [];
              if (profile.expire != null) {
                expireRow.add(Text(
                  DateFormat("yyyy/MM/dd HH:mm").format(profile.expire!),
                  style: Theme.of(ctx)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: Theme.of(ctx).textSelectionTheme.selectionColor),
                ));
              }
              if (profile.use != null && profile.total != null) {
                list.addAll([
                  const SizedBox(height: 16.0),
                  LinearProgressIndicator(value: profile.use! / profile.total!),
                ]);
                expireRow.add(const SizedBox());
                expireRow.add(Text(
                  '${dataformat(profile.use!)}/${dataformat(profile.total!)}',
                  style: Theme.of(ctx)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: Theme.of(ctx).textSelectionTheme.selectionColor),
                ));
              }

              if (expireRow.isNotEmpty) {
                list.add(const SizedBox(height: 8.0));
                list.add(Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: expireRow,
                ));
              }

              var btnList = [
                IconButton(
                  tooltip: "修改名称",
                  icon: Icon(Icons.edit_note_outlined, color: Theme.of(ctx).textSelectionTheme.selectionColor),
                  onPressed: () => onChangeName(),
                ),
                IconButton(
                  tooltip: "修改源",
                  icon: Icon(Icons.code_outlined, color: Theme.of(ctx).textSelectionTheme.selectionColor),
                  onPressed: () => onEdit(),
                ),
                IconButton(
                  tooltip: "移除",
                  icon: Icon(Icons.delete_outline_outlined, color: Theme.of(ctx).textSelectionTheme.selectionColor),
                  onPressed: () => onRemove(),
                ),
              ];
              if (profile.type == ProfileType.URL) {
                btnList.insert(
                    0,
                    IconButton(
                      tooltip: "更新",
                      icon: Icon(Icons.refresh_rounded, color: Theme.of(ctx).textSelectionTheme.selectionColor),
                      onPressed: () => onUpdate(),
                    ));
              }

              return Container(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    ...list,
                    const SizedBox(height: 3.0),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: isLoading
                          ? [const SizedBox(width: 20, height: 20, child: CircularProgressIndicator())]
                          : btnList,
                    ),
                    // 添加蒙层及进度条
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
