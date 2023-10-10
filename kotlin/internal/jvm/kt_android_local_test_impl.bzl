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
    "//kotlin/internal:defs.bzl",
    _TOOLCHAIN_TYPE = "TOOLCHAIN_TYPE",
)
load(
    "//kotlin/internal/jvm:impl.bzl",
    _write_launcher_action_exposed = "write_launcher_action_exposed",
)
load(
    "//kotlin/internal/jvm:kt_android_library_impl.bzl",
    _kt_android_produce_jar_actions = "kt_android_produce_jar_actions",
)
load(
    ":android_resources.bzl",
    _process_resources_for_android_local_test = "process_resources_for_android_local_test",
)
load("@rules_android//rules:java.bzl", _java = "java")
load("@rules_android//rules:utils.bzl", _get_android_sdk = "get_android_sdk", _get_android_toolchain = "get_android_toolchain", _utils = "utils")
load("@rules_android//rules:intellij.bzl", _intellij = "intellij")
load("@rules_android//rules:common.bzl", _common = "common")

_SPLIT_STRINGS = [
    "src/test/java/",
    "src/test/kotlin/",
    "javatests/",
    "kotlin/",
    "java/",
    "test/",
]

def kt_android_local_test_impl(ctx):
    # Android resource processing
    java_package = _java.resolve_package_from_label(ctx.label, ctx.attr.custom_package)

    resources_ctx = _process_resources_for_android_local_test(ctx, java_package)
    resources_apk = resources_ctx.resources_apk
    resources_jar = resources_ctx.class_jar
    processed_manifest = resources_ctx.processed_manifest
    resources_zip = resources_ctx.validation_result

    # Generate properties file telling Robolectric from where to load resources.
    test_config_file = ctx.actions.declare_file("_robolectric/" + ctx.label.name + "_test_config.properties")
    ctx.actions.write(
        test_config_file,
        content = """android_merged_manifest={android_merged_manifest}
android_merged_resources={android_merged_resources}
android_merged_assets={android_merged_assets}
android_custom_package={android_custom_package}
android_resource_apk={android_resource_apk}
        """.format(
            android_merged_manifest = processed_manifest.short_path,
            android_merged_resources = "jar:file:{}!/res".format(resources_zip.short_path),
            android_merged_assets = "jar:file:{}!/assets".format(resources_zip.short_path),
            android_custom_package = java_package,
            android_resource_apk = resources_apk.short_path,
        ),
    )

    outputs = struct(jar = ctx.outputs.jar, srcjar = ctx.outputs.srcjar)

    # Setup the compile action.
    providers = _kt_android_produce_jar_actions(
        ctx,
        "kt_jvm_test",
        outputs,
        resources_ctx.r_java,
        extra_resources = {"com/android/tools/test_config.properties": test_config_file},
    )

    # Create test run action
    runtime_jars = depset(
        ctx.files._bazel_test_runner + [resources_jar] + [_get_android_sdk(ctx).android_jar],
        transitive = [providers.java.transitive_runtime_jars],
    )
    coverage_runfiles = []
    if ctx.configuration.coverage_enabled:
        jacocorunner = ctx.toolchains[_TOOLCHAIN_TYPE].jacocorunner
        coverage_runfiles = jacocorunner.files.to_list()

    test_class = ctx.attr.test_class

    # If no test_class, do a best-effort attempt to infer one.
    if not bool(ctx.attr.test_class):
        for file in ctx.files.srcs:
            package_relative_path = file.path.replace(ctx.label.package + "/", "")
            if package_relative_path.split(".")[0] == ctx.attr.name:
                for splitter in _SPLIT_STRINGS:
                    elements = file.short_path.split(splitter, 1)
                    if len(elements) == 2:
                        test_class = elements[1].split(".")[0].replace("/", ".")
                        break

    coverage_metadata = _write_launcher_action_exposed(
        ctx,
        runtime_jars,
        main_class = ctx.attr.main_class,
        jvm_flags = [
            "-ea",
            "-Dbazel.test_suite=%s" % test_class,
            "-Drobolectric.offline=true",
            "-Drobolectric-deps.properties=" + _get_android_all_jars_properties_file(ctx).short_path,
            "-Duse_framework_manifest_parser=true",
            "-Dorg.robolectric.packagesToNotAcquire=com.google.testing.junit.runner.util",
        ] + ctx.attr.jvm_flags,
    )

    # TODO Add the rest of the missing fields to further improve IDE experience
    android_ide_info = _intellij.make_android_ide_info(
        ctx,
        java_package = _java.resolve_package_from_label(ctx.label, ctx.attr.custom_package),
        manifest = ctx.file.manifest,
        defines_resources = resources_ctx.r_java != None,
        merged_manifest = resources_ctx.processed_manifest,
        resources_apk = resources_ctx.resources_apk,
        r_jar = _utils.only(resources_ctx.r_java.outputs.jars) if resources_ctx.r_java else None,
        java_info = providers.java,
        signed_apk = None,  # signed_apk, always empty for aar_import
        apks_under_test = [],  # apks_under_test, always empty for aar_import
        native_libs = dict(),  # nativelibs, always empty for aar_import
        idlclass = _get_android_toolchain(ctx).idlclass.files_to_run,
        host_javabase = _common.get_host_javabase(ctx),
    )

    files = [ctx.outputs.jar]
    if providers.java.outputs.jdeps:
        files.append(providers.java.outputs.jdeps)

    return struct(
        # Mirrors https://github.com/bazelbuild/rules_android/blob/e83f77ab3ec60c8cab239ee4b4012bf691da2e57/rules/android_library/impl.bzl#L483-L496
        android = _intellij.make_legacy_android_provider(android_ide_info),
        java = struct(
            annotation_processing = providers.java.annotation_processing,
            outputs = providers.java.outputs,
            source_jars = depset(providers.java.source_jars),
            transitive_deps = providers.java.transitive_compile_time_jars,
            transitive_runtime_deps = providers.java.transitive_runtime_jars,
            transitive_source_jars = providers.java.transitive_source_jars,
        ),
        kt = providers.kt,
        providers = [
            android_ide_info,
            providers.java,
            providers.kt,
            providers.instrumented_files,
            DefaultInfo(
                files = depset(files),
                runfiles = ctx.runfiles(
                    # Explicitly include data files, otherwise they appear to be missing
                    # Include resources apk required by Robolectric
                    files = ctx.files.data + [resources_apk, processed_manifest, resources_zip],
                    transitive_files = depset(
                        order = "default",
                        transitive = [runtime_jars, depset(coverage_runfiles), depset(coverage_metadata)],
                        direct = ctx.files._java_runtime,
                    ),
                    # continue to use collect_default until proper transitive data collecting is
                    # implemented.
                    collect_default = True,
                ),
            ),
            testing.TestEnvironment(environment = ctx.attr.env),
        ],
    )

def _get_android_all_jars_properties_file(ctx):
    runfiles = ctx.runfiles(collect_data = True).files.to_list()
    for run_file in runfiles:
        if run_file.basename == "robolectric-deps.properties":
            return run_file
    fail("'robolectric-deps.properties' not found in the deps of the rule.")
