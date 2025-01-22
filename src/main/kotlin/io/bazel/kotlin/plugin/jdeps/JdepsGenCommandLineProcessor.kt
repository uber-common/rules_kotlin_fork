package io.bazel.kotlin.plugin.jdeps

import org.jetbrains.kotlin.compiler.plugin.AbstractCliOption
import org.jetbrains.kotlin.compiler.plugin.CliOption
import org.jetbrains.kotlin.compiler.plugin.CliOptionProcessingException
import org.jetbrains.kotlin.compiler.plugin.CommandLineProcessor
import org.jetbrains.kotlin.config.CompilerConfiguration
import org.jetbrains.kotlin.config.CompilerConfigurationKey

@OptIn(org.jetbrains.kotlin.compiler.plugin.ExperimentalCompilerApi::class)
class JdepsGenCommandLineProcessor : CommandLineProcessor {
  companion object {
    val COMPILER_PLUGIN_ID = "io.bazel.kotlin.plugin.jdeps.JDepsGen"

    val OUTPUT_JDEPS_FILE_OPTION: CliOption =
      CliOption("output", "<path>", "Output path for generated jdeps", required = true)
    val TARGET_LABEL_OPTION: CliOption =
      CliOption("target_label", "<String>", "Label of target being analyzed", required = true)
    val DIRECT_DEPENDENCIES_OPTION: CliOption =
      CliOption(
        "direct_dependencies",
        "<List>",
        "List of targets direct dependencies",
        required = false,
        allowMultipleOccurrences = true,
      )
    val STRICT_KOTLIN_DEPS_OPTION: CliOption =
      CliOption("strict_kotlin_deps", "<String>", "Report strict deps violations", required = true)
    val TRACK_CLASS_USAGE_OPTION: CliOption =
      CliOption("track_class_usage", "<String>", "Whether to track class usage", required = true)
    val TRACK_RESOURCE_USAGE_OPTION: CliOption =
      CliOption("track_resource_usage", "<String>", "Whether to track resource usage", required = true)
  }

  override val pluginId: String
    get() = COMPILER_PLUGIN_ID
  override val pluginOptions: Collection<AbstractCliOption>
    get() = listOf(OUTPUT_JDEPS_FILE_OPTION, TARGET_LABEL_OPTION, DIRECT_DEPENDENCIES_OPTION, STRICT_KOTLIN_DEPS_OPTION, TRACK_CLASS_USAGE_OPTION, TRACK_RESOURCE_USAGE_OPTION)

  override fun processOption(
    option: AbstractCliOption,
    value: String,
    configuration: CompilerConfiguration,
  ) {
    when (option) {
      OUTPUT_JDEPS_FILE_OPTION -> configuration.put(JdepsGenConfigurationKeys.OUTPUT_JDEPS, value)
      TARGET_LABEL_OPTION -> configuration.put(JdepsGenConfigurationKeys.TARGET_LABEL, value)
      DIRECT_DEPENDENCIES_OPTION -> configuration.appendList(JdepsGenConfigurationKeys.DIRECT_DEPENDENCIES, value)
      STRICT_KOTLIN_DEPS_OPTION -> configuration.put(JdepsGenConfigurationKeys.STRICT_KOTLIN_DEPS, value)
      TRACK_CLASS_USAGE_OPTION -> configuration.put(JdepsGenConfigurationKeys.TRACK_CLASS_USAGE, value)
      TRACK_RESOURCE_USAGE_OPTION -> configuration.put(JdepsGenConfigurationKeys.TRACK_RESOURCE_USAGE, value)
      else -> throw CliOptionProcessingException("Unknown option: ${option.optionName}")
    }
  }

  override fun <T> CompilerConfiguration.appendList(
    option: CompilerConfigurationKey<List<T>>,
    value: T,
  ) {
    val paths = getList(option).toMutableList()
    paths.add(value)
    put(option, paths)
  }

  override fun <T> CompilerConfiguration.appendList(
    option: CompilerConfigurationKey<List<T>>,
    values: List<T>,
  ) {
    val paths = getList(option).toMutableList()
    paths.addAll(values)
    put(option, paths)
  }
}
