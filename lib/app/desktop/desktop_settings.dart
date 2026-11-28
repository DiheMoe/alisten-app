import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_top_bar.dart';
import 'package:alisten/shared/ui/window_chrome.dart';
import 'package:flutter/widgets.dart';

/// 桌面窗口里的设置：左边一直是分类，右边是打开的那一类。
class DesktopSettings extends StatelessWidget {
  const DesktopSettings({
    required this.location,
    required this.categories,
    required this.child,
    super.key,
  });

  final Uri location;
  final Widget categories;
  final Widget child;

  static const _categoriesWidth = 340.0;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // `/settings/<分类>` 本身没有可返回的上一页；更深的页面返回到它的分类。
    final section = location.pathSegments.length <= 2;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: _categoriesWidth,
          child: WindowChromeInset(
            rightInset: 0,
            child: MediaQuery(
              data: media.copyWith(
                size: Size(_categoriesWidth, media.size.height),
              ),
              child: SidebarPage(active: true, child: categories),
            ),
          ),
        ),
        const SizedBox(width: AlistenSpacing.xs),
        Expanded(
          // 页面按自己这一块的大小排版，而不是整个窗口。
          child: LayoutBuilder(
            builder: (context, constraints) => MediaQuery(
              data: media.copyWith(size: constraints.biggest),
              child: ClipRect(
                child: SidebarPage(active: section, child: child),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
