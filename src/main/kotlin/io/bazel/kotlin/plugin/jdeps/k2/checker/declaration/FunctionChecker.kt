package io.bazel.kotlin.plugin.jdeps.k2.checker.declaration

import io.bazel.kotlin.plugin.jdeps.k2.ClassUsageRecorder
import org.jetbrains.kotlin.diagnostics.DiagnosticReporter
import org.jetbrains.kotlin.fir.analysis.checkers.MppCheckerKind
import org.jetbrains.kotlin.fir.analysis.checkers.context.CheckerContext
import org.jetbrains.kotlin.fir.analysis.checkers.declaration.FirFunctionChecker
import org.jetbrains.kotlin.fir.declarations.FirFunction

internal class FunctionChecker(
  private val classUsageRecorder: ClassUsageRecorder,
) : FirFunctionChecker(MppCheckerKind.Common) {
  /**
   * Tracks the value parameters of a function declaration. Return type & type parameters are
   * tracked in [CallableChecker].
   */
  override fun check(
    declaration: FirFunction,
    context: CheckerContext,
    reporter: DiagnosticReporter,
  ) {
    // function parameters
    declaration.valueParameters.forEach { valueParam ->
      valueParam.returnTypeRef.let { classUsageRecorder.recordTypeRef(it, context) }
    }
  }
}
