import 'package:flutter/widgets.dart';

abstract final class AlistenRadii {
  static const double sm = 12;
  static const double md = 20;
  static const double lg = 28;
  static const double joined = 6;
  static const double pill = 999;
}

abstract final class AlistenSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
  static const double page = lg;
}

/// 图标统一用 Rounded 变体，尺寸只取这三档，各处笔画粗细才一致。
abstract final class AlistenSizes {
  static const double iconSm = 20;
  static const double icon = 24;
  static const double iconLg = 28;

  /// 触控区域的下限，与控件绘制尺寸无关。
  static const double minTouchTarget = 48;
  static const double largeTouchTarget = 56;
  static const double ring = 2;
  static const double iconButton = 44;

  /// 播放/暂停是唯一超出图标三档尺寸的控件。
  static const double playControl = 72;
  static const double playIcon = 36;
  static const double avatar = 32;
  static const double listAvatar = 40;
  static const double profileAvatar = 64;
  static const double rowCover = 52;
  static const double hairline = 1;
  static const double inlineIcon = 16;
  static const double memberTag = 18;

  /// 13 px 文字旁三位数计数的宽度，未计入字体缩放；计数在此范围内变化时不会
  /// 挤动旁边的内容。
  static const double countWidth = 28;

  /// 三个带图标的短选项所需宽度，未计入字体缩放。
  static const double threeChoiceWidth = 252;

  /// 两个不带图标的短选项所需宽度，未计入字体缩放。
  static const double twoChoiceWidth = 208;

  /// 绘制尺寸，小于触控区域。
  static const double rowAction = 36;
  static const double featureCover = 96;
  static const double cardCover = 136;
  static const double pageCover = 184;

  /// 不含四周白边。
  static const double qrCode = 200;
  static const double chipHeight = 36;
  static const Size toggleTrack = Size(52, 32);
  static const double toggleInset = 3;
  static const double sliderTrack = 6;
  static const double sliderThumb = 16;
  static const double sliderThumbHeld = 22;
  static const double sliderFallbackWidth = 200;
  static const double progressTrack = 4;
  static const Size sheetHandle = Size(36, 4);
  static const double emptyBadge = 72;
  static const double refreshPull = 96;
  static const double refreshHold = 64;
  static const double sheetMaxWidth = 560;
  static const double toastMaxWidth = 480;
  static const double contentMaxWidth = 640;
  static const double sidePanelWidth = 400;
}

/// 按下反馈只用缩小和变淡，不用水波纹。
abstract final class AlistenPress {
  static const double scale = 0.96;
  static const double opacity = 0.82;
  static const double disabledOpacity = 0.4;
}

abstract final class AlistenTint {
  static const double fill = 0.16;
  static const double stroke = 0.35;
  static const double glow = 0.4;
}

abstract final class AlistenDurations {
  static const press = Duration(milliseconds: 120);
  static const short = Duration(milliseconds: 200);
  static const medium = Duration(milliseconds: 300);
  static const layout = Duration(milliseconds: 400);
  static const track = Duration(milliseconds: 450);
  static const bounce = Duration(milliseconds: 420);
  static const pageEnter = Duration(milliseconds: 350);
  static const pageExit = Duration(milliseconds: 300);
  static const lyricState = Duration(milliseconds: 400);
  static const lyricBlur = Duration(milliseconds: 120);
  static const theme = Duration(milliseconds: 600);
  static const backdrop = Duration(milliseconds: 800);
  static const toast = Duration(seconds: 3);
  static const longToast = Duration(seconds: 6);
  static const auroraLoop = Duration(seconds: 24);

  static Duration of(BuildContext context, Duration duration) {
    return MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
  }
}

abstract final class AlistenCurves {
  static const Curve standard = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
  static const Curve emphasized = Curves.easeInOutCubicEmphasized;
  static const Curve bounce = Curves.easeOutBack;
}

/// 内置的 Plus Jakarta Sans 只覆盖拉丁字母和数字，中文回退到系统字体。
abstract final class AlistenTypography {
  static const family = 'PlusJakartaSans';

  static final largeTitle = _style(
    32,
    FontWeight.w700,
    height: 1.15,
    letterSpacing: -0.8,
  );

  static final title = _style(
    22,
    FontWeight.w600,
    height: 1.25,
    letterSpacing: -0.3,
  );

  /// 分区标题：比正文略大，用次要色。只有页面主标题用大号粗体。
  static final section = _style(
    16,
    FontWeight.w600,
    height: 1.3,
    letterSpacing: -0.1,
  );

  static final body = _style(15, FontWeight.w500, height: 1.4);

  static final bodyStrong = _style(15, FontWeight.w600, height: 1.35);

  static final secondary = _style(13, FontWeight.w500, height: 1.35);

  static final caption = _style(
    11,
    FontWeight.w600,
    height: 1.3,
    letterSpacing: 0.1,
  );

  static final lyric = _style(
    26,
    FontWeight.w700,
    height: 1.3,
    letterSpacing: -0.3,
  );

  static final lyricTranslation = _style(15, FontWeight.w600, height: 1.3);

  static final timecode = _style(
    13,
    FontWeight.w600,
    height: 1.3,
    tabularFigures: true,
  );

  /// 排版会把行高取整，不能直接用字号乘行高；需要预知行高的布局应使用它。
  static double lineHeight(TextStyle style, TextScaler scaler) {
    final painter = TextPainter(
      text: TextSpan(text: ' ', style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final height = painter.height;
    painter.dispose();
    return height;
  }

  /// 内置字体是可变字体，字重轴必须随字重一起改变，不能只改 `fontWeight`。
  static TextStyle weighted(TextStyle style, FontWeight weight) {
    return style.copyWith(
      fontWeight: weight,
      fontVariations: [FontVariation.weight(weight.value.toDouble())],
    );
  }

  static TextStyle _style(
    double size,
    FontWeight weight, {
    required double height,
    double letterSpacing = 0,
    bool tabularFigures = false,
  }) {
    return weighted(
      TextStyle(
        fontFamily: family,
        fontSize: size,
        height: height,
        letterSpacing: letterSpacing,
        leadingDistribution: TextLeadingDistribution.even,
        fontFeatures: tabularFigures
            ? const [FontFeature.tabularFigures()]
            : null,
      ),
      weight,
    );
  }
}
