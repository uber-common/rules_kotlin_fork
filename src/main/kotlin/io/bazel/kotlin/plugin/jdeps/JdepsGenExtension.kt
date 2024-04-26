package io.bazel.kotlin.plugin.jdeps

import com.intellij.openapi.project.Project
import com.intellij.psi.PsiElement
import org.jetbrains.kotlin.analyzer.AnalysisResult
import org.jetbrains.kotlin.config.CompilerConfiguration
import org.jetbrains.kotlin.container.StorageComponentContainer
import org.jetbrains.kotlin.container.useInstance
import org.jetbrains.kotlin.descriptors.ClassDescriptor
import org.jetbrains.kotlin.descriptors.DeclarationDescriptor
import org.jetbrains.kotlin.descriptors.DeclarationDescriptorWithSource
import org.jetbrains.kotlin.descriptors.FunctionDescriptor
import org.jetbrains.kotlin.descriptors.ModuleDescriptor
import org.jetbrains.kotlin.descriptors.ParameterDescriptor
import org.jetbrains.kotlin.descriptors.PropertyDescriptor
import org.jetbrains.kotlin.descriptors.SourceElement
import org.jetbrains.kotlin.descriptors.impl.LocalVariableDescriptor
import org.jetbrains.kotlin.extensions.StorageComponentContainerContributor
import org.jetbrains.kotlin.load.java.descriptors.JavaMethodDescriptor
import org.jetbrains.kotlin.load.java.descriptors.JavaPropertyDescriptor
import org.jetbrains.kotlin.load.java.lazy.descriptors.LazyJavaClassDescriptor
import org.jetbrains.kotlin.load.java.sources.JavaSourceElement
import org.jetbrains.kotlin.load.java.structure.impl.classFiles.BinaryJavaClass
import org.jetbrains.kotlin.load.java.structure.impl.classFiles.BinaryJavaField
import org.jetbrains.kotlin.load.kotlin.KotlinJvmBinarySourceElement
import org.jetbrains.kotlin.load.kotlin.VirtualFileKotlinClass
import org.jetbrains.kotlin.load.kotlin.getContainingKotlinJvmBinaryClass
import org.jetbrains.kotlin.platform.TargetPlatform
import org.jetbrains.kotlin.psi.KtDeclaration
import org.jetbrains.kotlin.psi.KtFile
import org.jetbrains.kotlin.resolve.BindingTrace
import org.jetbrains.kotlin.resolve.FunctionImportedFromObject
import org.jetbrains.kotlin.resolve.PropertyImportedFromObject
import org.jetbrains.kotlin.resolve.calls.checkers.CallChecker
import org.jetbrains.kotlin.resolve.calls.checkers.CallCheckerContext
import org.jetbrains.kotlin.resolve.calls.model.ResolvedCall
import org.jetbrains.kotlin.resolve.calls.util.FakeCallableDescriptorForObject
import org.jetbrains.kotlin.resolve.checkers.DeclarationChecker
import org.jetbrains.kotlin.resolve.checkers.DeclarationCheckerContext
import org.jetbrains.kotlin.resolve.jvm.extensions.AnalysisHandlerExtension
import org.jetbrains.kotlin.types.KotlinType
import org.jetbrains.kotlin.types.TypeConstructor
import org.jetbrains.kotlin.types.typeUtil.supertypes

/**
 * Kotlin compiler extension that tracks classes (and corresponding classpath jars) needed to
 * compile current kotlin target. Tracked data should include all classes whose changes could
 * affect target's compilation out : direct class dependencies (i.e. external classes directly
 * used), but also their superclass, interfaces, etc.
 * The primary use of this extension is to improve Kotlin module compilation avoidance in build
 * systems (like Buck).
 *
 * Tracking of classes and their ancestors is done via modules and class
 * descriptors that got generated during analysis/resolve phase of Kotlin compilation.
 *
 * Note: annotation processors dependencies may need to be tracked separately (and may not need
 * per-class ABI change tracking)
 *
 * @param project the current compilation project
 * @param configuration the current compilation configuration
 */
class JdepsGenExtension(
  configuration: CompilerConfiguration,
) : BaseJdepsGenExtension(configuration),
  AnalysisHandlerExtension,
  StorageComponentContainerContributor {

  companion object {

    /**
     * Returns the path of the jar archive file corresponding to the provided descriptor.
     *
     * @descriptor the descriptor, typically obtained from compilation analyze phase
     * @return the path corresponding to the JAR where this class was loaded from, or null.
     */
    fun getClassCanonicalPath(descriptor: DeclarationDescriptorWithSource): String? {
      return when (val sourceElement: SourceElement = descriptor.source) {
        is JavaSourceElement ->
          if (sourceElement.javaElement is BinaryJavaClass) {
            (sourceElement.javaElement as BinaryJavaClass).virtualFile.canonicalPath
          } else if (sourceElement.javaElement is BinaryJavaField) {
            val containingClass = (sourceElement.javaElement as BinaryJavaField).containingClass
            if (containingClass is BinaryJavaClass) {
              containingClass.virtualFile.canonicalPath
            } else {
              null
            }
          } else {
            // Ignore Java source local to this module.
            null
          }
        is KotlinJvmBinarySourceElement ->
          (sourceElement.binaryClass as VirtualFileKotlinClass).file.canonicalPath
        else -> null
      }
    }

    fun getClassCanonicalPath(typeConstructor: TypeConstructor): String? {
      return (typeConstructor.declarationDescriptor as? DeclarationDescriptorWithSource)?.let {
        getClassCanonicalPath(
          it,
        )
      }
    }

    fun getResourceName(descriptor: DeclarationDescriptorWithSource): String? {
      if (descriptor.containingDeclaration is LazyJavaClassDescriptor) {
        val fqName: String? = (descriptor.containingDeclaration as LazyJavaClassDescriptor)?.jClass?.fqName?.asString()
        if (fqName != null) {
          if (fqName.indexOf(".R.") > 0 || fqName.indexOf("R.") == 0) {
            return fqName + "." + descriptor.name.asString()
          }
        }
      }
      return null
    }
  }

  private val explicitClassesCanonicalPaths = mutableSetOf<String>()
  private val implicitClassesCanonicalPaths = mutableSetOf<String>()
  private val usedResources = mutableSetOf<String>()

  override fun registerModuleComponents(
    container: StorageComponentContainer,
    platform: TargetPlatform,
    moduleDescriptor: ModuleDescriptor,
  ) {
    container.useInstance(
      ClasspathCollectingChecker(explicitClassesCanonicalPaths, implicitClassesCanonicalPaths, usedResources),
    )
  }

  class ClasspathCollectingChecker(
    private val explicitClassesCanonicalPaths: MutableSet<String>,
    private val implicitClassesCanonicalPaths: MutableSet<String>,
    private val usedResources: MutableSet<String>,
  ) : CallChecker, DeclarationChecker {

    override fun check(
      resolvedCall: ResolvedCall<*>,
      reportOn: PsiElement,
      context: CallCheckerContext,
    ) {
      when (val resultingDescriptor = resolvedCall.resultingDescriptor) {
        is FunctionImportedFromObject -> {
          collectTypeReferences(resultingDescriptor.containingObject.defaultType)
        }
        is PropertyImportedFromObject -> {
          collectTypeReferences(resultingDescriptor.containingObject.defaultType)
        }
        is JavaMethodDescriptor -> {
          getClassCanonicalPath(
            (resultingDescriptor.containingDeclaration as ClassDescriptor).typeConstructor,
          )?.let { explicitClassesCanonicalPaths.add(it) }
        }
        is FunctionDescriptor -> {
          resultingDescriptor.returnType?.let {
            collectTypeReferences(it, isExplicit = false, collectTypeArguments = false)
          }
          resultingDescriptor.valueParameters.forEach { valueParameter ->
            collectTypeReferences(valueParameter.type, isExplicit = false)
          }
          val virtualFileClass =
            resultingDescriptor.getContainingKotlinJvmBinaryClass() as? VirtualFileKotlinClass
              ?: return
          explicitClassesCanonicalPaths.add(virtualFileClass.file.path)
        }
        is ParameterDescriptor -> {
          getClassCanonicalPath(resultingDescriptor)?.let { explicitClassesCanonicalPaths.add(it) }
        }
        is FakeCallableDescriptorForObject -> {
          collectTypeReferences(resultingDescriptor.type)
        }
        is JavaPropertyDescriptor -> {
          getClassCanonicalPath(resultingDescriptor)?.let { explicitClassesCanonicalPaths.add(it) }
          getResourceName(resultingDescriptor)?.let { usedResources.add(it) }
        }
        is PropertyDescriptor -> {
          when (resultingDescriptor.containingDeclaration) {
            is ClassDescriptor -> collectTypeReferences(
              (resultingDescriptor.containingDeclaration as ClassDescriptor).defaultType,
            )
            else -> {
              val virtualFileClass =
                (resultingDescriptor).getContainingKotlinJvmBinaryClass() as? VirtualFileKotlinClass
                  ?: return
              explicitClassesCanonicalPaths.add(virtualFileClass.file.path)
            }
          }
          collectTypeReferences(resultingDescriptor.type, isExplicit = false)
        }
        else -> return
      }
    }

    override fun check(
      declaration: KtDeclaration,
      descriptor: DeclarationDescriptor,
      context: DeclarationCheckerContext,
    ) {
      when (descriptor) {
        is ClassDescriptor -> {
          descriptor.typeConstructor.supertypes.forEach {
            collectTypeReferences(it)
          }
        }
        is FunctionDescriptor -> {
          descriptor.returnType?.let { collectTypeReferences(it) }
          descriptor.valueParameters.forEach { valueParameter ->
            collectTypeReferences(valueParameter.type)
          }
          descriptor.annotations.forEach { annotation ->
            collectTypeReferences(annotation.type)
          }
          descriptor.extensionReceiverParameter?.value?.type?.let {
            collectTypeReferences(it)
          }
        }
        is PropertyDescriptor -> {
          collectTypeReferences(descriptor.type)
          descriptor.annotations.forEach { annotation ->
            collectTypeReferences(annotation.type)
          }
          descriptor.backingField?.annotations?.forEach { annotation ->
            collectTypeReferences(annotation.type)
          }
        }
        is LocalVariableDescriptor -> {
          collectTypeReferences(descriptor.type)
        }
      }
    }

    /**
     * Records direct and indirect references for a given type. Direct references are explicitly
     * used in the code, e.g: a type declaration or a generic type declaration. Indirect references
     * are other types required for compilation such as supertypes and interfaces of those explicit
     * types.
     */
    private fun collectTypeReferences(
      kotlinType: KotlinType,
      isExplicit: Boolean = true,
      collectTypeArguments: Boolean = true,
      visitedKotlinTypes: MutableSet<Pair<KotlinType, Boolean>> = mutableSetOf(),
    ) {
      val kotlintTypeAndIsExplicit = Pair(kotlinType, isExplicit)
      if (!visitedKotlinTypes.contains(kotlintTypeAndIsExplicit)) {
        visitedKotlinTypes.add(kotlintTypeAndIsExplicit)

        if (isExplicit) {
          getClassCanonicalPath(kotlinType.constructor)?.let {
            explicitClassesCanonicalPaths.add(it)
          }
        } else {
          getClassCanonicalPath(kotlinType.constructor)?.let {
            implicitClassesCanonicalPaths.add(it)
          }
        }

        kotlinType.supertypes().forEach { supertype ->
          collectTypeReferences(
            supertype,
            isExplicit = false,
            collectTypeArguments = collectTypeArguments,
            visitedKotlinTypes,
          )
        }

        if (collectTypeArguments) {
          kotlinType.arguments.map { it.type }.forEach { typeArgument ->
            collectTypeReferences(
              typeArgument,
              isExplicit = isExplicit,
              collectTypeArguments = true,
              visitedKotlinTypes = visitedKotlinTypes,
            )
          }
        }
      }
    }
  }

  override fun analysisCompleted(
    project: Project,
    module: ModuleDescriptor,
    bindingTrace: BindingTrace,
    files: Collection<KtFile>,
  ): AnalysisResult? {
    onAnalysisCompleted(explicitClassesCanonicalPaths, implicitClassesCanonicalPaths)

    return super.analysisCompleted(project, module, bindingTrace, files)
  }
}
