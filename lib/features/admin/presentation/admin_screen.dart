import 'package:alisten/features/admin/application/admin_session.dart';
import 'package:alisten/features/admin/presentation/admin_home.dart';
import 'package:alisten/features/admin/presentation/admin_token_page.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AdminScreen extends ConsumerWidget {
  const AdminScreen({
    required this.onNotice,
    required this.onExit,
    required this.onOpenRoom,
    super.key,
  });

  final void Function(ToastKind kind, String text) onNotice;
  final VoidCallback onExit;
  final void Function(String roomRef) onOpenRoom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 会话结束时关闭后台页面之上的所有面板和对话框，包括应用级的邀请、分享确认
    // 面板：逐个甄别要求每个面板都带标记，漏掉一个就会留在 token 页上。被关掉的
    // 邀请或分享可以重新打开链接或重新分享。
    ref.listen(adminSessionProvider.select((session) => session.active), (
      _,
      active,
    ) {
      final page = ModalRoute.of(context);
      if (active || page == null || !page.isActive || page.isCurrent) return;
      Navigator.of(context).popUntil((route) => route == page);
    });
    final (:active, :epoch) = ref.watch(
      adminSessionProvider.select(
        (session) => (active: session.active, epoch: session.epoch),
      ),
    );
    // 换 key 才能连同输入框的撤销历史一起丢弃已输入的 token。
    if (!active) return AdminTokenPage(key: ValueKey(epoch));
    return AdminHome(
      onNotice: onNotice,
      onExit: onExit,
      onOpenRoom: onOpenRoom,
    );
  }
}
