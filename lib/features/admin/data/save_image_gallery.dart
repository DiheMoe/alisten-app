import 'dart:typed_data';

import 'package:alisten/features/admin/application/image_gallery.dart';
import 'package:file_picker/file_picker.dart';

/// 桌面系统没有相册，保存就是让用户选个位置存下来。
final class SaveImageGallery implements ImageGallery {
  const SaveImageGallery();

  // 用户在保存对话框里取消不是失败。
  @override
  Future<void> saveImage(Uint8List bytes, String name) async {
    await FilePicker.saveFile(fileName: name, bytes: bytes);
  }
}
