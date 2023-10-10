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
    _JAVA_RUNTIME_TOOLCHAIN_TYPE = "JAVA_RUNTIME_TOOLCHAIN_TYPE",
    _JAVA_TOOLCHAIN_TYPE = "JAVA_TOOLCHAIN_TYPE",
    _KtJvmInfo = "KtJvmInfo",
    _TOOLCHAIN_TYPE = "TOOLCHAIN_TYPE",
)
load(
    "//kotlin/internal/jvm:jvm.bzl",
    _kt_android_local_test_runnable_common_attr_exposed = "runnable_common_attr_exposed",
    _kt_lib_common_outputs_exposed = "common_outputs_exposed",
)
load(
    "//kotlin/internal/jvm:kt_android_local_test_impl.bzl",
    _kt_android_local_test_impl = "kt_android_local_test_impl",
)
load("//kotlin/internal/utils:utils.bzl", _utils = "utils")
load("@rules_android//rules/android_local_test:attrs.bzl", _BASE_ATTRS = "ATTRS")

_ATTRS = _utils.add_dicts(_BASE_ATTRS, _kt_android_local_test_runnable_common_attr_exposed, {
    "_bazel_test_runner": attr.label(
        default = Label("@bazel_tools//tools/jdk:TestRunner_deploy.jar"),
        allow_files = True,
    ),
    "test_class": attr.string(
        doc = "The Java class to be loaded by the test runner.",
        default = "",
    ),
    "main_class": attr.string(default = "com.google.testing.junit.runner.BazelTestRunner"),
    "env": attr.string_dict(
        doc = "Specifies additional environment variables to set when the target is executed by bazel test.",
        default = {},
    ),
    "_lcov_merger": attr.label(
        default = Label("@bazel_tools//tools/test/CoverageOutputGenerator/java/com/google/devtools/coverageoutputgenerator:Main"),
    ),
})

kt_android_local_test = rule(
    doc = """Setup a simple kt_android_local_test.

    **Notes:**
    * The kotlin test library is not added implicitly, it is available with the label
    `@com_github_jetbrains_kotlin//:kotlin-test`.
    """,
    attrs = _ATTRS,
    outputs = _kt_lib_common_outputs_exposed,
    executable = True,
    test = True,
    provides = [
        _KtJvmInfo,
        JavaInfo,
        AndroidIdeInfo,
    ],
    toolchains = [
        "@rules_android//toolchains/android:toolchain_type",
        _TOOLCHAIN_TYPE,
        _JAVA_TOOLCHAIN_TYPE,
        _JAVA_RUNTIME_TOOLCHAIN_TYPE,
    ],
    fragments = ["android", "java"],  # Required fragments of the target configuration
    host_fragments = ["java"],  # Required fragments of the host configuration
    implementation = _kt_android_local_test_impl,
)
