// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library fasta.util.relativize;

// TODO(ahe): Move more advanced version from dart2js here.

String relativizeUri(Uri uri, {Uri base}) {
  if (uri == null) return null;
  base ??= Uri.base;
  String result = "$uri";
  return result.startsWith("$base") ? result.substring("$base".length) : result;
}
