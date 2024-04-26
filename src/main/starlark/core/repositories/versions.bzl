# All versions for development and release
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")

version = provider(
    fields = {
        "url_templates": "list of string templates with the placeholder {version}",
        "version": "the version in the form \\D+.\\D+.\\D+(.*)",
        "sha256": "sha256 checksum for the version being downloaded.",
        "strip_prefix_template": "string template with the placeholder {version}.",
    },
)

def _use_repository(name, version, rule, **kwargs):
    http_archive_arguments = dict(kwargs)
    http_archive_arguments["sha256"] = version.sha256
    http_archive_arguments["urls"] = [u.format(version = version.version) for u in version.url_templates]
    if (hasattr(version, "strip_prefix_template")):
        http_archive_arguments["strip_prefix"] = version.strip_prefix_template.format(version = version.version)

    maybe(rule, name = name, **http_archive_arguments)

versions = struct(
    RULES_NODEJS_VERSION = "5.5.3",
    RULES_NODEJS_SHA = "f10a3a12894fc3c9bf578ee5a5691769f6805c4be84359681a785a0c12e8d2b6",
    BAZEL_TOOLCHAINS_VERSION = "4.1.0",
    BAZEL_TOOLCHAINS_SHA = "179ec02f809e86abf56356d8898c8bd74069f1bd7c56044050c2cd3d79d0e024",
    # IMPORTANT! rules_kotlin does not use the bazel_skylib unittest in production
    # This means the bazel_skylib_workspace call is skipped, as it only registers the unittest
    # toolchains. However, if a new workspace dependency is introduced, this precondition will fail.
    # Why skip it? Because it would introduce a 3rd function call to rules kotlin setup:
    # 1. Download archive
    # 2. Download dependencies and Configure rules
    # --> 3. Configure dependencies <--
    SKYLIB_VERSION = "1.2.1",
    SKYLIB_SHA = "f7be3474d42aae265405a592bb7da8e171919d74c16f082a5457840f06054728",
    PROTOBUF_VERSION = "3.11.3",
    PROTOBUF_SHA = "cf754718b0aa945b00550ed7962ddc167167bd922b842199eeb6505e6f344852",
    RULES_JVM_EXTERNAL_TAG = "4.4.2",
    RULES_JVM_EXTERNAL_SHA = "735602f50813eb2ea93ca3f5e43b1959bd80b213b836a07a62a29d757670b77b",
    RULES_PROTO = version(
        version = "5.3.0-21.7",
        sha256 = "dc3fb206a2cb3441b485eb1e423165b231235a1ea9b031b4433cf7bc1fa460dd",
        strip_prefix_template = "rules_proto-{version}",
        url_templates = [
            "https://github.com/bazelbuild/rules_proto/archive/refs/tags/{version}.tar.gz",
        ],
    ),
    IO_BAZEL_STARDOC = version(
        version = "0.5.6",
        sha256 = "dfbc364aaec143df5e6c52faf1f1166775a5b4408243f445f44b661cfdc3134f",
        url_templates = [
            "https://mirror.bazel.build/github.com/bazelbuild/stardoc/releases/download/{version}/stardoc-{version}.tar.gz",
            "https://github.com/bazelbuild/stardoc/releases/download/{version}/stardoc-{version}.tar.gz",
        ],
    ),
    BAZEL_JAVA_LAUNCHER_VERSION = "5.0.0",
    PINTEREST_KTLINT = version(
        version = "0.49.1",
        url_templates = [
            "https://github.com/pinterest/ktlint/releases/download/{version}/ktlint",
        ],
        sha256 = "2b3f6f674a944d25bb8d283c3539947bbe86074793012909a55de4b771f74bcc",
    ),
    KOTLIN_CURRENT_COMPILER_RELEASE = version(
        version = "2.0.0",
        url_templates = [
            "https://github.com/JetBrains/kotlin/releases/download/v{version}/kotlin-compiler-{version}.zip",
        ],
        sha256 = "ef578730976154fd2c5968d75af8c2703b3de84a78dffe913f670326e149da3b",
    ),
    KSP_CURRENT_COMPILER_PLUGIN_RELEASE = version(
        version = "2.0.0-1.0.21",
        url_templates = [
            "https://github.com/google/ksp/releases/download/{version}/artifacts.zip",
        ],
        sha256 = "84100aed5b63effa992ce6574b3ba47d2dbb78529752daa4c181e203117ba7de",
    ),
    ANDROID = version(
        version = "a5e11f139ae25d93832e2604e1588bc97708d7e8",
        url_templates = [
            "https://github.com/Bencodes/rules_android/archive/{version}.tar.gz",
        ],
        sha256 = "5eb59039c1a591cb6d72ba01c5c33adf66fc7afca8dfcac1e4107829416b0929",
    ),
    # To update: https://github.com/bazelbuild/bazel-toolchains#latest-bazel-and-latest-ubuntu-1604-container
    RBE = struct(
        # This tarball intentionally does not have a SHA256 because the upstream URL can change without notice
        # For more context: https://github.com/bazelbuild/bazel-toolchains/blob/0c1f7c3c5f9e63f1e0ee91738b964937eea2d3e0/WORKSPACE#L28-L32
        URLS = ["https://storage.googleapis.com/rbe-toolchain/bazel-configs/rbe-ubuntu1604/latest/rbe_default.tar"],
    ),
    PKG = version(
        version = "0.7.0",
        url_templates = [
            "https://github.com/bazelbuild/rules_pkg/releases/download/{version}/rules_pkg-{version}.tar.gz",
        ],
        sha256 = "8a298e832762eda1830597d64fe7db58178aa84cd5926d76d5b744d6558941c2",
    ),
    # needed for rules_pkg and java
    RULES_PYTHON = version(
        version = "0.20.0",
        strip_prefix_template = "rules_python-{version}",
        url_templates = [
            "https://github.com/bazelbuild/rules_python/archive/refs/tags/{version}.tar.gz",
        ],
        sha256 = "a644da969b6824cc87f8fe7b18101a8a6c57da5db39caa6566ec6109f37d2141",
    ),
    RULES_LICENSE = version(
        version = "0.0.3",
        url_templates = [
            "https://mirror.bazel.build/github.com/bazelbuild/rules_license/releases/download/{version}/rules_license-{version}.tar.gz",
            "https://github.com/bazelbuild/rules_license/releases/download/{version}/rules_license-{version}.tar.gz",
        ],
        sha256 = None,
    ),
    use_repository = _use_repository,
)
