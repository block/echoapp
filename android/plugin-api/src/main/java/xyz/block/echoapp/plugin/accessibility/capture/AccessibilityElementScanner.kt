package xyz.block.echoapp.plugin.accessibility.capture

import android.view.View
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.core.view.isVisible
import xyz.block.echoapp.plugin.accessibility.AccessibilityElement
import xyz.block.echoapp.plugin.accessibility.Rect
import radiography.ExperimentalRadiographyComposeApi
import radiography.ScanScopes
import radiography.ScannableView
import radiography.ScannableView.ComposeView

/** Responsible for capturing [AccessibilityElement]s of the app's UI. */
fun interface AccessibilityElementScanner {
  fun scan(view: View): List<AccessibilityElement>
}

/**
 * The default implementation of [AccessibilityElementScanner].
 *
 * Uses [Radiography](https://github.com/block/radiography) to scan the UI's structure.
 */
@OptIn(ExperimentalRadiographyComposeApi::class)
object RadiographyAccessibilityElementScanner : AccessibilityElementScanner {
  override fun scan(view: View): List<AccessibilityElement> {
    if (!view.isVisible) return emptyList()
    val scope = ScanScopes.singleViewScope(view)
    val firstView = scope.findRoots().firstOrNull() ?: return emptyList()
    return collectA11yElementsRecursively(firstView, view.width, view.height)
        .sortedWith(
            compareByDescending<AccessibilityElement> { it.frame.height }
                .thenByDescending { it.frame.width },
        )
  }

  private fun collectA11yElementsRecursively(
      view: ScannableView,
      windowWidth: Int,
      windowHeight: Int,
  ): List<AccessibilityElement> {
    return buildList {
      if (view is ComposeView) {
        val viewAccessibilityElement: AccessibilityElement? =
            tryGetComposeViewElement(view, windowWidth, windowHeight)

        if (viewAccessibilityElement != null) {
          val shouldMergeChildrenProperties =
              view.semanticsConfigurations.any { it.isMergingSemanticsOfDescendants == true }

          if (shouldMergeChildrenProperties) {
            val mergedElement =
                mergeChildrenPropertiesIntoElementRecursively(
                    view,
                    viewAccessibilityElement,
                    windowWidth,
                    windowHeight,
                )
            mergedElement.let(::add)
            return@buildList
          }
          viewAccessibilityElement.let(::add)
        }
      }
      view.children.forEach { child ->
        addAll(
            collectA11yElementsRecursively(child, windowWidth, windowHeight),
        )
      }
    }
  }

  private fun mergeChildrenPropertiesIntoElementRecursively(
      view: ScannableView,
      viewAccessibilityElement: AccessibilityElement,
      windowWidth: Int,
      windowHeight: Int,
  ): AccessibilityElement {
    var mergedElement = viewAccessibilityElement
    view.children.forEach { child ->
      if (child is ComposeView) {
        val childAccessibilityElement = tryGetComposeViewElement(child, windowWidth, windowHeight)
        if (childAccessibilityElement != null) {
          mergedElement =
              AccessibilityElement(
                  description =
                      "${viewAccessibilityElement.description} ${childAccessibilityElement.description}",
                  identifier = viewAccessibilityElement.identifier,
                  hint = "${viewAccessibilityElement.hint} ${childAccessibilityElement.hint}",
                  userInputLabels =
                      viewAccessibilityElement.userInputLabels.orEmpty() +
                          childAccessibilityElement.userInputLabels.orEmpty(),
                  customActions =
                      viewAccessibilityElement.customActions +
                          childAccessibilityElement.customActions,
                  frame = viewAccessibilityElement.frame,
              )
        }
        mergedElement =
            mergeChildrenPropertiesIntoElementRecursively(
                view = child,
                viewAccessibilityElement = mergedElement,
                windowWidth = windowWidth,
                windowHeight = windowHeight,
            )
      }
    }
    return mergedElement
  }

  private fun tryGetComposeViewElement(
      view: ComposeView,
      windowWidth: Int,
      windowHeight: Int,
  ): AccessibilityElement? {
    if (view.width == windowWidth ||
        view.height == windowHeight ||
        view.semanticsNodes.isEmpty() ||
        view.semanticsConfigurations.isEmpty()) {
      return null
    }
    val semantics = view.semanticsNodes.first()
    val semanticsConfigurations = view.semanticsConfigurations.flatten()

    val contentDescription =
        semanticsConfigurations
            .find { it.key == SemanticsProperties.ContentDescription }
            ?.value
            ?.toString() ?: "NONE"
    val userInputLabels =
        view.semanticsConfigurations
            .flatten()
            .filter {
              it.key in
                  listOf(
                      SemanticsProperties.Role,
                      SemanticsProperties.Text,
                      SemanticsProperties.EditableText,
                      SemanticsProperties.Selected,
                      SemanticsActions.OnClick,
                      SemanticsActions.OnLongClick,
                  )
            }
            .map { "${it.key.name} -- ${it.value}" }

    val actions =
        view.semanticsConfigurations
            .flatten()
            .filter {
              it.key in
                  listOf(
                      SemanticsActions.OnClick,
                      SemanticsActions.OnLongClick,
                  )
            }
            .map { "${it.key.name} -- ${it.value}" }

    // this calculation is needed to convert to Echo desktop xy coordinate system
    val bounds = semantics.boundsInWindow
    val rect =
        Rect(
            x = bounds.right - (bounds.width / 2),
            y = bounds.bottom - (bounds.height / 2),
            width = bounds.width,
            height = bounds.height,
        )

    return AccessibilityElement(
        description = view.displayName,
        identifier = semantics.id.toString(),
        hint = contentDescription,
        userInputLabels = userInputLabels,
        customActions = actions,
        frame = rect,
    )
  }
}
