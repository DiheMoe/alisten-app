import 'package:flutter/widgets.dart';

class CoverImages extends InheritedWidget {
  const CoverImages({required this.resolve, required super.child, super.key});

  final ImageProvider Function(String url) resolve;

  static ImageProvider of(BuildContext context, String url) {
    final images = context.dependOnInheritedWidgetOfExactType<CoverImages>();
    return images == null ? NetworkImage(url) : images.resolve(url);
  }

  @override
  bool updateShouldNotify(CoverImages oldWidget) =>
      resolve != oldWidget.resolve;
}
