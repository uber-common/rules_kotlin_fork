# Copyright 2018 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
load(
    "//kotlin/internal/jvm:compile.bzl",
    "export_only_providers",
    _compiler_toolchains = "compiler_toolchains_exposed",
    _get_kt_dep_infos = "get_kt_dep_infos",
    _jvm_deps = "jvm_deps_exposed",
    _kt_jvm_produce_output_jar_actions = "kt_jvm_produce_output_jar_actions",
)
load(
    "//kotlin/internal/jvm:associates.bzl",
    _associate_utils = "associate_utils",
)
load("@rules_android//rules:java.bzl", _java = "java")
load("@rules_android//rules:processing_pipeline.bzl", _ProviderInfo = "ProviderInfo", _processing_pipeline = "processing_pipeline")
load("@rules_android//rules/android_library:impl.bzl", _BASE_PROCESSORS = "PROCESSORS", _android_library_finalize = "finalize")
load("@rules_android//rules:utils.bzl", _get_android_sdk = "get_android_sdk", _utils = "utils")

def _process_jvm(ctx, resources_ctx, **unused_sub_ctxs):
    """Custom JvmProcessor that handles Kotlin compilation
    """
    r_java = resources_ctx.r_java
    outputs = struct(jar = ctx.outputs.lib_jar, srcjar = ctx.outputs.lib_src_jar)
    providers = kt_android_produce_jar_actions(ctx, "kt_jvm_library", outputs, r_java)

    return _ProviderInfo(
        name = "jvm_ctx",
        value = struct(
            java_info = providers.java,
            kt_info = providers.kt,
            providers = [
                providers.kt,
                providers.java,
            ],
        ),
    )

def _finalize(ctx, jvm_ctx, **unused_ctxs):
    # Call into rules_android for it's finalization logic
    android_struct = _android_library_finalize(ctx = ctx, jvm_ctx = jvm_ctx, **unused_ctxs)

    # Mirror the resulting provider but stick the legacy `kt` provider into the
    # rule result so that Intellij knows to treat our KT targets as Kotlin.
    return struct(
        kt = jvm_ctx.kt_info,
        android = android_struct.android,
        java = android_struct.java,
        providers = android_struct.providers,
    )

PROCESSORS = _processing_pipeline.replace(
    _BASE_PROCESSORS,
    JvmProcessor = _process_jvm,
)

_PROCESSING_PIPELINE = _processing_pipeline.make_processing_pipeline(
    processors = PROCESSORS,
    finalize = _finalize,
)

def kt_android_library_impl(ctx):
    """The rule implementation.

    Args:
      ctx: The context.

    Returns:
      A list of providers.
    """
    java_package = _java.resolve_package_from_label(ctx.label, ctx.attr.custom_package)
    return _processing_pipeline.run(ctx, java_package, _PROCESSING_PIPELINE)

def _get_android_sdk_jar(ctx):
    android_jar = _get_android_sdk(ctx).android_jar
    return JavaInfo(output_jar = android_jar, compile_jar = android_jar, neverlink = True)

def _get_android_resource_class_jars(targets):
    """Encapsulates compiler dependency metadata."""

    android_compile_dependencies = []

    # Collect R.class jar files from direct dependencies
    for d in targets:
        if AndroidLibraryResourceClassJarProvider in d:
            jars = d[AndroidLibraryResourceClassJarProvider].jars
            if jars:
                android_compile_dependencies.extend([
                    JavaInfo(output_jar = jar, compile_jar = jar, neverlink = True)
                    for jar in _utils.list_or_depset_to_list(jars)
                ])

    return android_compile_dependencies

def kt_android_produce_jar_actions(
        ctx,
        rule_kind,
        outputs,
        rClass = None,
        extra_resources = {}):
    """Setup The actions to compile a jar and if any resources or resource_jars were provided to merge these in with the
    compilation output.

    Returns:
        see `kt_jvm_compile_action`.
    """
    toolchains = _compiler_toolchains(ctx)
    associates = _associate_utils.get_associates(ctx)

    # Collect the android compile dependencies
    android_dep_infos = [_get_android_sdk_jar(ctx)]
    if rClass:
        android_dep_infos.append(rClass)
    android_dep_infos.extend(_get_android_resource_class_jars(ctx.attr.deps + ctx.attr.associates))
    android_dep_infos.extend(_get_kt_dep_infos(toolchains, associates.targets, deps = ctx.attr.deps))
    compile_deps = _jvm_deps(ctx, android_dep_infos, ctx.attr.runtime_deps)

    # Setup the compile action.
    return _kt_jvm_produce_output_jar_actions(
        ctx,
        rule_kind = rule_kind,
        compile_deps = compile_deps,
        outputs = outputs,
        extra_resources = extra_resources,
    ) if ctx.attr.srcs else export_only_providers(
        ctx = ctx,
        actions = ctx.actions,
        outputs = outputs,
        attr = ctx.attr,
    )
