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
    "@bazel_skylib//rules:common_settings.bzl",
    _BuildSettingInfo = "BuildSettingInfo",
)
load(
    "@rules_android//rules:attrs.bzl",
    _attrs = "attrs",
)
load(
    "@rules_android//rules:java.bzl",
    _java = "java",
)
load(
    "@rules_android//rules:processing_pipeline.bzl",
    _ProviderInfo = "ProviderInfo",
    _processing_pipeline = "processing_pipeline",
)
load(
    "@rules_android//rules:resources.bzl",
    _resources = "resources",
)
load(
    "@rules_android//rules:utils.bzl",
    _compilation_mode = "compilation_mode",
    _get_android_sdk = "get_android_sdk",
    _get_android_toolchain = "get_android_toolchain",
    _utils = "utils",
)
load(
    "@rules_android//rules/android_local_test:impl.bzl",
    _BASE_PROCESSORS = "PROCESSORS",
    _finalize = "finalize",
)
load(
    "//kotlin/internal:defs.bzl",
    _JAVA_RUNTIME_TOOLCHAIN_TYPE = "JAVA_RUNTIME_TOOLCHAIN_TYPE",
)
load(
    "//kotlin/internal/jvm:compile.bzl",
    _compile = "compile",
    _export_only_providers = "export_only_providers",
    _kt_jvm_produce_output_jar_actions = "kt_jvm_produce_output_jar_actions",
)

JACOCOCO_CLASS = "com.google.testing.coverage.JacocoCoverageRunner"

def _process_resources(ctx, java_package, manifest_ctx, **_unused_sub_ctxs):
    # Note: This needs to be kept in sync with.
    # The main difference between this and the upstream macro is that both ctx.attr.associates and ctx.attr.deps needs to
    # be passed to `_resources.package(` in order for ALL of the resource references to get merged into a single R
    # class file.
    # https://github.com/bazelbuild/rules_android/blob/e98ee9eb79c9398a9866d073a43ecd5e97aaf896/rules/android_local_test/impl.bzl#L94-L122
    resources_ctx = _resources.package(
        ctx,
        # This entire section is being overridden so that we can pass the associates into the deps section.
        # Without this tests won't be able to reference resources of the assocate targets
        deps = ctx.attr.associates + ctx.attr.deps,
        manifest = manifest_ctx.processed_manifest,
        manifest_values = manifest_ctx.processed_manifest_values,
        manifest_merge_order = ctx.attr._manifest_merge_order[_BuildSettingInfo].value,
        resource_files = ctx.files.resource_files,
        assets = ctx.files.assets,
        assets_dir = ctx.attr.assets_dir,
        resource_configs = ctx.attr.resource_configuration_filters,
        densities = ctx.attr.densities,
        nocompress_extensions = ctx.attr.nocompress_extensions,
        compilation_mode = _compilation_mode.get(ctx),
        java_package = java_package,
        shrink_resources = _attrs.tristate.no,
        aapt = _get_android_toolchain(ctx).aapt2.files_to_run,
        android_jar = _get_android_sdk(ctx).android_jar,
        busybox = _get_android_toolchain(ctx).android_resources_busybox.files_to_run,
        host_javabase = ctx.attr._host_javabase,
        # TODO(b/140582167): Throwing on resource conflict need to be rolled
        # out to android_local_test.
        should_throw_on_conflict = False,
    )

    return _ProviderInfo(
        name = "resources_ctx",
        value = resources_ctx,
    )

def _process_jvm(ctx, resources_ctx, **unused_sub_ctxs):
    """Custom JvmProcessor that handles Kotlin compilation
    """
    outputs = struct(jar = ctx.outputs.jar, srcjar = ctx.actions.declare_file(ctx.label.name + "-src.jar"))

    deps = getattr(ctx.attr, "deps", [])
    associates = getattr(ctx.attr, "associates", [])
    runtime_deps = getattr(ctx.attr, "runtime_deps", [])
    _compile.verify_associates_not_duplicated_in_deps(deps = deps, associates = associates)

    compile_deps = _compile.jvm_deps(
        ctx,
        toolchains = _compile.compiler_toolchains(ctx),
        deps = (
            [_get_android_sdk_jar(ctx)] +
            [_compile.java_info(_get_android_toolchain(ctx).testsupport)] +
            ([resources_ctx.r_java] if resources_ctx.r_java else []) +
            [_compile.java_info(d) for d in associates] +
            [_compile.java_info(d) for d in deps]
        ),
        associates = [_compile.java_info(d) for d in associates],
        runtime_deps = [_compile.java_info(d) for d in runtime_deps],
    )

    # Setup the compile action.
    providers = _kt_jvm_produce_output_jar_actions(
        ctx,
        rule_kind = "kt_jvm_test",
        compile_deps = compile_deps,
        outputs = outputs,
    )
    java_info = java_common.add_constraints(providers.java, "android")

    provider_deps = (
        ctx.attr._implicit_classpath +
        associates +
        deps +
        [_get_android_toolchain(ctx).testsupport]
    )

    if ctx.configuration.coverage_enabled:
        provider_deps.append(_get_android_toolchain(ctx).jacocorunner)
        java_start_class = JACOCOCO_CLASS
        coverage_start_class = ctx.attr.main_class
    else:
        java_start_class = ctx.attr.main_class
        coverage_start_class = None

    # Create test run action
    runfiles = depset(
        [resources_ctx.class_jar] + [_get_android_sdk(ctx).android_jar, ctx.file.robolectric_properties_file],
        transitive = [providers.java.transitive_runtime_jars],
    ).to_list()

    # Append the security manager override
    jvm_flags = []
    java_runtime = ctx.toolchains[_JAVA_RUNTIME_TOOLCHAIN_TYPE].java_runtime
    if java_runtime.version >= 17:
        jvm_flags.append("-Djava.security.manager=allow")

    return _ProviderInfo(
        name = "jvm_ctx",
        value = struct(
            java_info = java_info,
            providers = [
                providers.kt,
                java_info,
            ],
            deps = provider_deps,
            java_start_class = java_start_class,
            coverage_start_class = coverage_start_class,
            android_properties_file = ctx.file.robolectric_properties_file.short_path,
            additional_jvm_flags = jvm_flags,
        ),
        runfiles = ctx.runfiles(
            files = runfiles,
            collect_default = True,
        ),
    )

PROCESSORS = _processing_pipeline.replace(
    _BASE_PROCESSORS,
    ResourceProcessor = _process_resources,
    JvmProcessor = _process_jvm,
)

_PROCESSING_PIPELINE = _processing_pipeline.make_processing_pipeline(
    processors = PROCESSORS,
    finalize = _finalize,
)

def kt_android_local_test_impl(ctx):
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
