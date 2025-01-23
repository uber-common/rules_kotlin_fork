package io.bazel.kotlin.plugin.jdeps

import org.jetbrains.kotlin.config.CompilerConfigurationKey

object JdepsGenConfigurationKeys {
  /**
   * Output path of generated Jdeps proto file.
   */
  val OUTPUT_JDEPS: CompilerConfigurationKey<String> =
    CompilerConfigurationKey.create(
      JdepsGenCommandLineProcessor.OUTPUT_JDEPS_FILE_OPTION.description,
    )

  /**
   * Label of the Bazel target being analyzed.
   */
  val TARGET_LABEL: CompilerConfigurationKey<String> =
    CompilerConfigurationKey.create(JdepsGenCommandLineProcessor.TARGET_LABEL_OPTION.description)

  /**
   * Label of the Bazel target being analyzed.
   */
  val STRICT_KOTLIN_DEPS: CompilerConfigurationKey<String> =
    CompilerConfigurationKey.create(
      JdepsGenCommandLineProcessor.STRICT_KOTLIN_DEPS_OPTION.description,
    )

  /**
   * List of direct dependencies of the target.
   */
  val DIRECT_DEPENDENCIES: CompilerConfigurationKey<List<String>> =
    CompilerConfigurationKey.create(JdepsGenCommandLineProcessor.DIRECT_DEPENDENCIES_OPTION.description)

  /**
   * Whether used class tracking is enabled or not.
   */
  val TRACK_CLASS_USAGE: CompilerConfigurationKey<String> =
    CompilerConfigurationKey.create(JdepsGenCommandLineProcessor.TRACK_CLASS_USAGE_OPTION.description)

  /**
   * Whether used resource tracking is enabled or not.
   */
  val TRACK_RESOURCE_USAGE: CompilerConfigurationKey<String> =
    CompilerConfigurationKey.create(JdepsGenCommandLineProcessor.TRACK_RESOURCE_USAGE_OPTION.description)
}
