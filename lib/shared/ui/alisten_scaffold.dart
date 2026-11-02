import 'dart:math' as math;

import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// 页面延伸到系统栏之下。[topBar] 和 [bottomBar] 自行处理所在边缘的安全区，
/// 因此 [body] 在有栏的一侧不再获得安全区内边距。
///
/// [bottomBar] 始终贴底：键盘先盖住它，高过它之后才上推 [body]，否则 [body]
/// 底部的输入框会随底栏升降来回跳动。被键盘完全盖住的底栏不接收触摸、焦点和
/// 语义。
class AlistenScaffold extends StatelessWidget {
  const AlistenScaffold({
    required this.body,
    this.topBar,
    this.bottomBar,
    this.background,
    this.resizeToAvoidBottomInset = true,
    this.contentMaxWidth = AlistenSizes.contentMaxWidth,
    super.key,
  });

  final Widget body;

  final Widget? topBar;
  final Widget? bottomBar;
  final Widget? background;
  final bool resizeToAvoidBottomInset;
  final double contentMaxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final media = MediaQuery.of(context);
    final page = media.removeViewInsets(removeBottom: resizeToAvoidBottomInset);
    final keyboard = media.viewInsets.bottom - page.viewInsets.bottom;
    final topBar = this.topBar;
    final bottomBar = this.bottomBar;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
          ),
      // 输入框需要祖先 Material，文字颜色也取自它；透明类型不做任何绘制。
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          fit: StackFit.expand,
          children: [
            background ?? ColoredBox(color: theme.colorScheme.surface),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = math.min(constraints.maxWidth, contentMaxWidth);
                final content = _clearOfMargins(
                  page,
                  (constraints.maxWidth - width) / 2,
                );
                return Center(
                  child: SizedBox(
                    width: width,
                    child: MediaQuery(
                      data: content,
                      child: CustomMultiChildLayout(
                        delegate: _PageLayout(keyboard: keyboard),
                        children: [
                          if (topBar != null)
                            LayoutId(id: _Part.topBar, child: topBar),
                          LayoutId(
                            id: _Part.body,
                            child: MediaQuery(
                              data: content.removePadding(
                                removeTop: topBar != null,
                                removeBottom: bottomBar != null,
                              ),
                              child: DefaultTextStyle.merge(
                                style: TextStyle(
                                  color: AlistenColors.of(context).onGlass,
                                ),
                                child: body,
                              ),
                            ),
                          ),
                          if (bottomBar != null)
                            LayoutId(
                              id: _Part.bottomBar,
                              child: _UnderKeyboard(
                                keyboard: keyboard,
                                // 键盘升起时 `padding` 和去掉键盘后的
                                // `viewPadding` 都会扣掉被盖住的部分，
                                // 底栏会变矮下移，所以底部安全区取原始值。
                                child: MediaQuery(
                                  data: content.copyWith(
                                    padding: content.padding.copyWith(
                                      bottom: media.viewPadding.bottom,
                                    ),
                                  ),
                                  child: SafeArea(top: false, child: bottomBar),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

enum _Part { topBar, body, bottomBar }

class _PageLayout extends MultiChildLayoutDelegate {
  _PageLayout({required this.keyboard});

  final double keyboard;

  @override
  void performLayout(Size size) {
    final loose = BoxConstraints(maxWidth: size.width);
    double centred(Size child) => (size.width - child.width) / 2;
    var top = 0.0;
    if (hasChild(_Part.topBar)) {
      final bar = layoutChild(_Part.topBar, loose);
      positionChild(_Part.topBar, Offset(centred(bar), 0));
      top = bar.height;
    }
    var bottom = 0.0;
    if (hasChild(_Part.bottomBar)) {
      final bar = layoutChild(_Part.bottomBar, loose);
      positionChild(
        _Part.bottomBar,
        Offset(centred(bar), size.height - bar.height),
      );
      bottom = bar.height;
    }
    final height = math.max(
      0.0,
      size.height - top - math.max(bottom, keyboard),
    );
    final body = layoutChild(
      _Part.body,
      loose.copyWith(minHeight: height, maxHeight: height),
    );
    positionChild(_Part.body, Offset(centred(body), top));
  }

  @override
  bool shouldRelayout(_PageLayout oldDelegate) {
    return keyboard != oldDelegate.keyboard;
  }
}

class _UnderKeyboard extends StatefulWidget {
  const _UnderKeyboard({required this.keyboard, required this.child});

  final double keyboard;
  final Widget child;

  @override
  State<_UnderKeyboard> createState() => _UnderKeyboardState();
}

class _UnderKeyboardState extends State<_UnderKeyboard> {
  final _focus = FocusNode(
    debugLabel: 'under keyboard',
    canRequestFocus: false,
    skipTraversal: true,
  );

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      includeSemantics: false,
      child: _UnderKeyboardBox(
        keyboard: widget.keyboard,
        focus: _focus,
        child: widget.child,
      ),
    );
  }
}

class _UnderKeyboardBox extends SingleChildRenderObjectWidget {
  const _UnderKeyboardBox({
    required this.keyboard,
    required this.focus,
    required super.child,
  });

  final double keyboard;
  final FocusNode focus;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderUnderKeyboard(keyboard, focus);
  }

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderUnderKeyboard).keyboard = keyboard;
  }
}

// 底栏高度排版后才知道，是否被键盘盖满只能在这里判断，无法在构建时使用
// `IgnorePointer`、`ExcludeSemantics` 和 `ExcludeFocus`。焦点管理器会把焦点
// 改动推迟到本帧之后生效，因此可以在排版中修改。
class _RenderUnderKeyboard extends RenderProxyBox {
  _RenderUnderKeyboard(this._keyboard, this._focus);

  final FocusNode _focus;

  double _keyboard;
  set keyboard(double value) {
    if (value == _keyboard) return;
    final wasCovered = _covered;
    _keyboard = value;
    if (_covered != wasCovered) _coveredChanged();
  }

  bool get _covered => hasSize && _keyboard > 0 && _keyboard >= size.height;

  void _coveredChanged() {
    markNeedsSemanticsUpdate();
    _focus.descendantsAreFocusable = !_covered;
  }

  @override
  void performLayout() {
    final wasCovered = _covered;
    super.performLayout();
    if (_covered != wasCovered) _coveredChanged();
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    return !_covered && super.hitTest(result, position: position);
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (!_covered) super.visitChildrenForSemantics(visitor);
  }
}

// 居中留出的两侧边距已容纳刘海和圆角，左右安全区扣除 [margin]。
MediaQueryData _clearOfMargins(MediaQueryData data, double margin) {
  if (margin <= 0) return data;
  EdgeInsets less(EdgeInsets insets) => insets.copyWith(
    left: math.max(0.0, insets.left - margin),
    right: math.max(0.0, insets.right - margin),
  );
  return data.copyWith(
    padding: less(data.padding),
    viewPadding: less(data.viewPadding),
  );
}
