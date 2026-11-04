import 'package:flutter/widgets.dart';

/// 判断连续动画此刻是否值得出帧。
///
/// 被其他页面盖住时也要停：转场途中和半透明页面之下 TickerMode 仍开启。定时器
/// 不会像 Ticker 那样随引擎停止出帧而停下，应用在后台时须自行停止。
///
/// 输入法显示时系统每帧都要合成键盘和本应用，连续重绘会争抢 GPU，导致键盘升降
/// 和打字掉帧。键盘高度从窗口读取：两栏布局的左栏移除了 `MediaQuery` 的
/// `viewInsets`，在那里看不到键盘。
mixin VisibleFrames<T extends StatefulWidget>
    on State<T>, WidgetsBindingObserver {
  bool _visible = false;
  bool _onScreen = false;
  bool _keyboardUp = false;
  bool _animationsRemoved = false;

  bool get onScreen => _onScreen;
  bool get keyboardUp => _keyboardUp;
  bool get animationsRemoved => _animationsRemoved;

  void visibleFramesChanged();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible =
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.isCurrentOf(context) ?? true);
    _animationsRemoved = MediaQuery.disableAnimationsOf(context);
    _refresh(alwaysNotify: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _refresh();

  @override
  void didChangeMetrics() => _refresh();

  void _refresh({bool alwaysNotify = false}) {
    if (!mounted) return;
    final onScreen = _visible && WidgetsBinding.instance.framesEnabled;
    final keyboardUp = View.of(context).viewInsets.bottom > 0;
    if (!alwaysNotify && onScreen == _onScreen && keyboardUp == _keyboardUp) {
      return;
    }
    _onScreen = onScreen;
    _keyboardUp = keyboardUp;
    visibleFramesChanged();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
