import 'dart:typed_data';

import 'package:alisten/features/admin/application/image_gallery.dart';
import 'package:gal/gal.dart';

final class GalImageGallery implements ImageGallery {
  const GalImageGallery();

  @override
  Future<void> saveImage(Uint8List bytes, String name) async {
    try {
      if (!await Gal.hasAccess() && !await Gal.requestAccess()) {
        throw const GalleryAccessDenied();
      }
      await Gal.putImageBytes(bytes, name: name);
    } on GalException catch (error) {
      if (error.type == GalExceptionType.accessDenied) {
        throw const GalleryAccessDenied();
      }
      rethrow;
    }
  }
}
