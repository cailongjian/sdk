// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:async_helper/async_helper.dart';
import 'analysis_helper.dart';
import 'api_dynamic_test.dart' as api;

// TODO(johnniwinther): Remove unneeded dynamic accesses.
const Map<String, List<String>> allowedList = {
  'pkg/compiler/lib/src/closure.dart': null,
  'pkg/compiler/lib/src/common/tasks.dart': null,
  'pkg/compiler/lib/src/compiler.dart': null,
  'pkg/compiler/lib/src/constant_system_dart.dart': null,
  'pkg/compiler/lib/src/constants/constructors.dart': null,
  'pkg/compiler/lib/src/constants/expressions.dart': null,
  'pkg/compiler/lib/src/constants/values.dart': null,
  'pkg/compiler/lib/src/dart2js.dart': null,
  'pkg/compiler/lib/src/deferred_load.dart': null,
  'pkg/compiler/lib/src/diagnostics/messages.dart': null,
  'pkg/compiler/lib/src/diagnostics/source_span.dart': null,
  'pkg/compiler/lib/src/elements/entities.dart': null,
  'pkg/compiler/lib/src/elements/names.dart': null,
  'pkg/compiler/lib/src/elements/types.dart': null,
  'pkg/compiler/lib/src/hash/sha1.dart': null,
  'pkg/compiler/lib/src/helpers/debug_collection.dart': null,
  'pkg/compiler/lib/src/helpers/expensive_map.dart': null,
  'pkg/compiler/lib/src/helpers/expensive_set.dart': null,
  'pkg/compiler/lib/src/helpers/trace.dart': null,
  'pkg/compiler/lib/src/helpers/track_map.dart': null,
  'pkg/compiler/lib/src/inferrer/inferrer_engine.dart': null,
  'pkg/compiler/lib/src/inferrer/locals_handler.dart': null,
  'pkg/compiler/lib/src/inferrer/node_tracer.dart': null,
  'pkg/compiler/lib/src/inferrer/type_graph_dump.dart': null,
  'pkg/compiler/lib/src/inferrer/type_graph_nodes.dart': null,
  'pkg/compiler/lib/src/inferrer/typemasks/container_type_mask.dart': null,
  'pkg/compiler/lib/src/inferrer/typemasks/dictionary_type_mask.dart': null,
  'pkg/compiler/lib/src/inferrer/typemasks/forwarding_type_mask.dart': null,
  'pkg/compiler/lib/src/inferrer/typemasks/map_type_mask.dart': null,
  'pkg/compiler/lib/src/inferrer/typemasks/type_mask.dart': null,
  'pkg/compiler/lib/src/inferrer/typemasks/union_type_mask.dart': null,
  'pkg/compiler/lib/src/inferrer/typemasks/value_type_mask.dart': null,
  'pkg/compiler/lib/src/io/position_information.dart': null,
  'pkg/compiler/lib/src/io/source_information.dart': null,
  'pkg/compiler/lib/src/js/js.dart': null,
  'pkg/compiler/lib/src/js/rewrite_async.dart': null,
  'pkg/compiler/lib/src/js_backend/checked_mode_helpers.dart': null,
  'pkg/compiler/lib/src/js_backend/constant_system_javascript.dart': null,
  'pkg/compiler/lib/src/js_backend/namer_names.dart': null,
  'pkg/compiler/lib/src/js_backend/native_data.dart': null,
  'pkg/compiler/lib/src/js_emitter/full_emitter/emitter.dart': null,
  'pkg/compiler/lib/src/js_emitter/program_builder/program_builder.dart': null,
  'pkg/compiler/lib/src/js_emitter/startup_emitter/fragment_emitter.dart': null,
  'pkg/compiler/lib/src/js_model/closure.dart': null,
  'pkg/compiler/lib/src/js_model/js_strategy.dart': null,
  'pkg/compiler/lib/src/native/behavior.dart': null,
  'pkg/compiler/lib/src/native/enqueue.dart': null,
  'pkg/compiler/lib/src/native/js.dart': null,
  'pkg/compiler/lib/src/source_file_provider.dart': null,
  'pkg/compiler/lib/src/ssa/builder_kernel.dart': null,
  'pkg/compiler/lib/src/ssa/interceptor_simplifier.dart': null,
  'pkg/compiler/lib/src/ssa/nodes.dart': null,
  'pkg/compiler/lib/src/ssa/optimize.dart': null,
  'pkg/compiler/lib/src/ssa/types.dart': null,
  'pkg/compiler/lib/src/ssa/validate.dart': null,
  'pkg/compiler/lib/src/ssa/value_range_analyzer.dart': null,
  'pkg/compiler/lib/src/ssa/value_set.dart': null,
  'pkg/compiler/lib/src/ssa/variable_allocator.dart': null,
  'pkg/compiler/lib/src/universe/feature.dart': null,
  'pkg/compiler/lib/src/universe/function_set.dart': null,
  'pkg/compiler/lib/src/universe/member_usage.dart': null,
  'pkg/compiler/lib/src/universe/resolution_world_builder.dart': null,
  'pkg/compiler/lib/src/universe/side_effects.dart': null,
  'pkg/compiler/lib/src/universe/use.dart': null,
  'pkg/compiler/lib/src/universe/world_builder.dart': null,
  'pkg/compiler/lib/src/util/enumset.dart': null,
  'pkg/compiler/lib/src/util/maplet.dart': null,
  'pkg/compiler/lib/src/util/setlet.dart': null,
  'pkg/compiler/lib/src/util/util.dart': null,
  'pkg/front_end/lib/src/base/libraries_specification.dart': null,
  'pkg/front_end/lib/src/fasta/builder/function_type_builder.dart': null,
  'pkg/front_end/lib/src/fasta/colors.dart': null,
  'pkg/front_end/lib/src/fasta/crash.dart': null,
  'pkg/front_end/lib/src/fasta/dill/dill_member_builder.dart': null,
  'pkg/front_end/lib/src/fasta/kernel/body_builder.dart': null,
  'pkg/front_end/lib/src/fasta/kernel/expression_generator.dart': null,
  'pkg/front_end/lib/src/fasta/kernel/kernel_class_builder.dart': null,
  'pkg/front_end/lib/src/fasta/kernel/kernel_function_type_alias_builder.dart':
      null,
  'pkg/front_end/lib/src/fasta/kernel/kernel_function_type_builder.dart': null,
  'pkg/front_end/lib/src/fasta/kernel/kernel_library_builder.dart': null,
  'pkg/front_end/lib/src/fasta/kernel/kernel_procedure_builder.dart': null,
  'pkg/front_end/lib/src/fasta/scanner/string_canonicalizer.dart': null,
  'pkg/front_end/lib/src/fasta/scanner/token.dart': null,
  'pkg/front_end/lib/src/fasta/source/diet_listener.dart': null,
  'pkg/front_end/lib/src/fasta/source/outline_builder.dart': null,
  'pkg/front_end/lib/src/fasta/util/link.dart': null,
  'pkg/front_end/lib/src/fasta/util/link_implementation.dart': null,
  'pkg/js_ast/lib/src/builder.dart': null,
  'pkg/js_ast/lib/src/template.dart': null,
  'pkg/kernel/lib/ast.dart': null,
  'pkg/kernel/lib/clone.dart': null,
  'pkg/kernel/lib/import_table.dart': null,
  'pkg/kernel/lib/kernel.dart': null,
  'pkg/kernel/lib/text/ast_to_text.dart': null,
  'third_party/pkg/dart2js_info/lib/json_info_codec.dart': null,
  'third_party/pkg/dart2js_info/lib/src/measurements.dart': null,
  'third_party/pkg/dart2js_info/lib/src/util.dart': null,
  'third_party/pkg/source_span/lib/src/file.dart': null,
  'third_party/pkg/source_span/lib/src/span_mixin.dart': null,
};

main(List<String> args) {
  asyncTest(() async {
    Map<String, List<String>> allowed = {};
    allowed.addAll(api.allowedList);
    allowed.addAll(allowedList);
    await run(Uri.parse('package:compiler/src/dart2js.dart'),
        allowedList: allowed, verbose: args.contains('-v'));
  });
}
