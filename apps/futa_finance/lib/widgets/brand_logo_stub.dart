// Non-Web 向け stub。実体は brand_logo_web.dart 側にある。
// Android/iOS では呼ばれない（kIsWeb 分岐）が、ビルドを通すために必要。

import 'package:flutter/widgets.dart';

Widget buildWebImage(String url, double size) => const SizedBox.shrink();
