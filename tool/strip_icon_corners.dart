// One-off maintenance script: cleans up assets/images/logo.png so the
// corners are fully transparent instead of carrying a faint black fringe
// from the anti-aliased edge, letting Android apply its own icon mask/shape.
// Run with: dart run tool/strip_icon_corners.dart
import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final path = 'assets/images/logo.png';
  final bytes = File(path).readAsBytesSync();
  final src = img.decodePng(bytes)!;
  final w = src.width, h = src.height;
  final out = img.Image(width: w, height: h, numChannels: 4);

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = src.getPixel(x, y);
      // Snap any partially-transparent edge pixel to fully transparent —
      // avoids a half-black fringe from the old baked-in corner color.
      final a = p.a.toInt() >= 250 ? 255 : 0;
      out.setPixelRgba(x, y, p.r.toInt(), p.g.toInt(), p.b.toInt(), a);
    }
  }

  File(path).writeAsBytesSync(img.encodePng(out));
  print('Done: cleaned up edge fringing in $path.');
}
