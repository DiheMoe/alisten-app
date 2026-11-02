import 'package:flutter/widgets.dart';

class AvatarImages extends InheritedWidget {
  const AvatarImages({required this.resolve, required super.child, super.key});

  final ImageProvider Function(String url) resolve;

  static ImageProvider of(BuildContext context, String url) {
    final images = context.dependOnInheritedWidgetOfExactType<AvatarImages>();
    return images == null ? NetworkImage(url) : images.resolve(url);
  }

  @override
  bool updateShouldNotify(AvatarImages oldWidget) =>
      resolve != oldWidget.resolve;
}
