import QtQuick
import qs.Commons

// Sits over a slider and turns the mouse wheel into scrolling the panel.
// Omarchy's PanelSlider changes its value on every wheel notch and reports
// it as released, so scrolling the panel past a slider would quietly change
// that setting on the headphones. Clicks and drags still reach the slider.
MouseArea {
  anchors.fill: parent
  acceptedButtons: Qt.NoButton

  function scrollView() {
    for (var item = parent; item; item = item.parent) {
      if (item.contentY !== undefined && item.contentHeight !== undefined && item.originY !== undefined)
        return item
    }
    return null
  }

  onWheel: function(wheel) {
    var view = scrollView()
    if (!view) return
    // A touchpad reports pixels; a mouse wheel reports notches of 120.
    var dy = wheel.pixelDelta.y !== 0 ? wheel.pixelDelta.y : wheel.angleDelta.y / 120 * Style.space(60)
    var top = view.originY
    var bottom = view.originY + Math.max(0, view.contentHeight - view.height)
    view.contentY = Math.max(top, Math.min(bottom, view.contentY - dy))
  }
}
