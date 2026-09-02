import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    layerNamespacePlugin: "awcc"

    // Settings
    property string awccBinary: pluginData.awccBinary || "awcc"
    property int refreshInterval: pluginData.refreshInterval || 10
    // Proc.runCommand() keeps one entry per id and resolves entry.callback at
    // completion time, so instances sharing an id clobber each other's callback.
    // The id has to stay stable, though: the 500ms debounce below is what
    // collapses the burst of commands a slider drag produces, and a fresh id per
    // call would defeat it. Keying on the screen gives isolation per instance
    // and a bounded set of entries, where a random namespace leaked a new entry
    // and Timer into the Proc singleton on every reload.
    readonly property string commandNamespace: "awcc." + (root.parentScreen ? root.parentScreen.name : "default")

    // State
    property string currentMode: "..."
    property string toastText: ""
    property int cpuBoost: 0
    property int gpuBoost: 0
    property bool turboEnabled: false
    property int kbBrightness: pluginData.kbBrightness !== undefined ? pluginData.kbBrightness : 50
    property string kbEffect: pluginData.kbEffect || "spectrum"
    property string kbColor: pluginData.kbColor || "ff0000"

    // Device capabilities (populated from device-info)
    property var supportedFeatures: []
    property var supportedThermalModes: []
    property var supportedLightingModes: []

    // Feature flags (true while device-info is still loading)
    property bool hasThermalModes:    supportedFeatures.length === 0 || supportedFeatures.indexOf("Thermal Modes")    >= 0
    property bool hasFanBoost:        supportedFeatures.length === 0 || supportedFeatures.indexOf("Fan Boost")        >= 0
    property bool hasBrightness:      supportedFeatures.length === 0 || supportedFeatures.indexOf("Brightness Control") >= 0
    property bool hasLightingEffects: supportedLightingModes.length > 0
    property bool hasTurbo:           supportedFeatures.indexOf("CPU Turbo") >= 0

    // All known thermal modes with their device-info names
    readonly property var allThermalModes: [
        { cmd: "quiet",       label: "Quiet",          devName: "Quiet",         icon: "bedtime"        },
        { cmd: "battery",     label: "Battery Saving",  devName: "Battery Saving", icon: "battery_saver" },
        { cmd: "balance",     label: "Balanced",        devName: "Balanced",      icon: "balance"        },
        { cmd: "cool",        label: "Cool",            devName: "Cool",          icon: "ac_unit"        },
        { cmd: "performance", label: "Performance",     devName: "Performance",   icon: "rocket_launch"  },
        { cmd: "gmode",       label: "G-Mode",          devName: "GMode",         icon: "sports_esports" },
        { cmd: "fullspeed",   label: "Full Speed",      devName: "Full Speed",    icon: "fast_forward"   },
        { cmd: "manual",      label: "Manual",          devName: "Manual",        icon: "tune"           },
    ]

    property var thermalModes: allThermalModes.filter(
        m => supportedThermalModes.length === 0 || supportedThermalModes.indexOf(m.devName) >= 0
    )

    // All known keyboard effects with their device-info lighting mode names
    readonly property var allKbEffects: [
        { cmd: "spectrum",    label: "Spectrum",  devName: "Spectrum Effect",   needsColor: false },
        { cmd: "rainbow",     label: "Rainbow",   devName: "Rainbow Effect",    needsColor: false },
        { cmd: "static",      label: "Static",    devName: "Static Color",      needsColor: true  },
        { cmd: "breathe",     label: "Breathe",   devName: "Breathing Effect",  needsColor: true  },
        { cmd: "wave",        label: "Wave",      devName: "Wave Effect",       needsColor: true  },
        { cmd: "bkf",         label: "B&F",       devName: "Back Forth Effect", needsColor: true  },
        { cmd: "defaultblue", label: "Default",   devName: "",                  needsColor: false },
    ]

    property var kbEffects: allKbEffects.filter(
        e => supportedLightingModes.length === 0
             ? e.devName !== ""
             : (e.devName !== "" && supportedLightingModes.indexOf(e.devName) >= 0)
    )

    Timer {
        id: toastTimer
        interval: 1800
    }

    function showToast(msg) {
        root.toastText = msg
        toastTimer.restart()
    }

    // Every awcc call funnels through here, so the teardown guard lives here
    // too: reloading the plugin destroys this instance while commands are still
    // in flight, and their callbacks would then dereference a null root.
    function runAwcc(id, args, callback) {
        Proc.runCommand(root.commandNamespace + "." + id, [root.awccBinary].concat(args), (stdout, exitCode) => {
            if (!root)
                return
            callback(stdout, exitCode)
        }, 500)
    }

    function parseDeviceInfo() {
        runAwcc("deviceInfo", ["device-info"], (stdout, exitCode) => {
            if (exitCode !== 0) return
            var lines = stdout.split("\n")
            var section = ""
            var features = []
            var thermalModes = []
            var lightingModes = []
            for (var i = 0; i < lines.length; i++) {
                var line = lines[i]
                var trimmed = line.trim()
                if (trimmed === "Features enabled:")      { section = "features"; continue }
                else if (trimmed === "Thermal modes enabled:")  { section = "thermal";  continue }
                else if (trimmed === "Lighting modes enabled:") { section = "lighting"; continue }
                else if (trimmed.endsWith(":"))           { section = "";         continue }

                if (section !== "" && trimmed !== "") {
                    if (section === "features")  features.push(trimmed)
                    else if (section === "thermal")   thermalModes.push(trimmed)
                    else if (section === "lighting")  lightingModes.push(trimmed)
                }
            }
            root.supportedFeatures     = features
            root.supportedThermalModes = thermalModes
            root.supportedLightingModes = lightingModes
        })
    }

    function queryAll() {
        runAwcc("qm", ["qm"], (stdout, exitCode) => {
            if (exitCode === 0) {
                var parts = stdout.trim().split(": ")
                root.currentMode = parts.length > 1 ? parts.slice(1).join(": ") : stdout.trim()
            }
        })
        runAwcc("cb", ["cb"], (stdout, exitCode) => {
            if (exitCode === 0) {
                var parts = stdout.trim().split(": ")
                var val = parts.length > 1 ? parseInt(parts[1]) || 0 : 0
                if (val > 0) {
                    root.cpuBoost = val
                    pluginService?.savePluginData("awcc", "cpuBoost", val)
                } else if (pluginData.cpuBoost > 0) {
                    root.cpuBoost = pluginData.cpuBoost
                    root.runAwcc("scb", ["scb", root.cpuBoost.toString()], () => {})
                }
            }
        })
        runAwcc("gb", ["gb"], (stdout, exitCode) => {
            if (exitCode === 0) {
                var line = stdout.trim().split("\n")[0]
                var parts = line.split(": ")
                var val = parts.length > 1 ? parseInt(parts[1]) || 0 : 0
                if (val > 0) {
                    root.gpuBoost = val
                    pluginService?.savePluginData("awcc", "gpuBoost", val)
                } else if (pluginData.gpuBoost > 0) {
                    root.gpuBoost = pluginData.gpuBoost
                    root.runAwcc("sgb", ["sgb", root.gpuBoost.toString()], () => {})
                }
            }
        })
        if (root.hasTurbo) {
            runAwcc("getturbo", ["getturbo"], (stdout, exitCode) => {
                if (exitCode === 0) {
                    root.turboEnabled = stdout.trim().endsWith("true")
                }
            })
        }
    }

    Component.onCompleted: {
        parseDeviceInfo()
        queryAll()
    }

    Timer {
        interval: root.refreshInterval * 1000
        running: true
        repeat: true
        onTriggered: {
            root.runAwcc("qm.poll", ["qm"], (stdout, exitCode) => {
                if (exitCode === 0) {
                    var parts = stdout.trim().split(": ")
                    root.currentMode = parts.length > 1 ? parts.slice(1).join(": ") : stdout.trim()
                }
            })
        }
    }

    // ── Bar Pills ──────────────────────────────────────────────────────────────

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS
            DankIcon {
                name: "bolt"
                size: Theme.iconSize - 4
                color: Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }
            StyledText {
                text: root.currentMode
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // Wrapped in an Item that reports the icon's implicit size, matching the
    // sibling plugins. The mode name is deliberately left out: a vertical bar is
    // too narrow for it.
    verticalBarPill: Component {
        Item {
            implicitWidth: verticalIcon.implicitWidth
            implicitHeight: verticalIcon.implicitHeight

            DankIcon {
                id: verticalIcon
                anchors.centerIn: parent
                name: "bolt"
                size: 24
                color: Theme.primary
            }
        }
    }

    // ── Styled Slider ──────────────────────────────────────────────────────────

    component StyledSlider: Slider {
        id: sliderControl

        property color accentColor: Theme.primary

        background: Rectangle {
            x: sliderControl.leftPadding
            y: sliderControl.topPadding + sliderControl.availableHeight / 2 - height / 2
            width: sliderControl.availableWidth
            height: 4
            radius: 2
            color: Theme.surfaceVariant

            Rectangle {
                width: sliderControl.visualPosition * parent.width
                height: parent.height
                radius: 2
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: sliderControl.accentColor }
                    GradientStop { position: 1.0; color: Qt.rgba(sliderControl.accentColor.r, sliderControl.accentColor.g, sliderControl.accentColor.b, 0.5) }
                }
            }
        }

        handle: Rectangle {
            x: sliderControl.leftPadding + sliderControl.visualPosition * (sliderControl.availableWidth - width)
            y: sliderControl.topPadding + sliderControl.availableHeight / 2 - height / 2
            implicitWidth: 18
            implicitHeight: 18
            radius: width / 2
            color: Theme.surfaceContainerHighest
            border.color: sliderControl.accentColor
            border.width: 2

            scale: sliderControl.pressed ? 1.15 : (sliderControl.hovered ? 1.08 : 1.0)
            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
        }
    }

    // Card wrapper with an icon + title + subtitle header, matching the popouts
    // of the sibling plugins. Section controls go in the default slot.
    component SectionCard: StyledRect {
        id: card

        property string iconName: ""
        property string title: ""
        property string subtitle: ""
        property color accentColor: Theme.primary
        default property alias content: cardBody.data

        width: parent.width
        height: Math.max(0, cardCol.implicitHeight + Theme.spacingM * 2)
        radius: Theme.cornerRadius
        color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
        border.width: 1
        border.color: Qt.rgba(card.accentColor.r, card.accentColor.g, card.accentColor.b, 0.15)

        Column {
            id: cardCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.spacingM
            spacing: Theme.spacingS

            RowLayout {
                width: parent.width
                spacing: Theme.spacingXS

                DankIcon {
                    name: card.iconName
                    size: 14
                    color: card.accentColor
                    Layout.alignment: Qt.AlignVCenter
                }

                StyledText {
                    text: card.title
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Bold
                    color: Theme.surfaceText
                    Layout.alignment: Qt.AlignVCenter
                }

                StyledText {
                    text: card.subtitle
                    font.pixelSize: Theme.fontSizeSmall - 1
                    color: Theme.surfaceVariantText
                    opacity: 0.7
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    elide: Text.ElideRight
                }
            }

            Column {
                id: cardBody
                width: parent.width
                spacing: Theme.spacingS
            }
        }
    }

    // Pick-one-of-N button, used for both thermal modes and keyboard effects.
    // Corners round to a pill on hover, the same motion the sibling plugins give
    // their list rows.
    component ActionChip: Item {
        id: chip

        property string label: ""
        property string iconName: ""
        property bool active: false
        property color accentColor: Theme.primary
        signal triggered

        readonly property bool isHovered: chipMa.containsMouse

        Shape {
            id: chipBg
            anchors.fill: parent

            readonly property real target: (chip.isHovered || chip.active) ? (height / 2) : (Theme.cornerRadius || 12)
            property real r: target
            Behavior on r { NumberAnimation { duration: 500; easing.type: Easing.OutExpo } }

            ShapePath {
                fillColor: chip.active
                           ? Qt.rgba(chip.accentColor.r, chip.accentColor.g, chip.accentColor.b, 0.18)
                           : (chip.isHovered
                              ? Qt.rgba(chip.accentColor.r, chip.accentColor.g, chip.accentColor.b, 0.08)
                              : Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.04))
                strokeColor: chip.active
                             ? Qt.rgba(chip.accentColor.r, chip.accentColor.g, chip.accentColor.b, 0.5)
                             : (chip.isHovered
                                ? Qt.rgba(chip.accentColor.r, chip.accentColor.g, chip.accentColor.b, 0.3)
                                : Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.15))
                strokeWidth: 1

                startX: chipBg.r + 1; startY: 1
                PathLine { x: chipBg.width - chipBg.r - 1; y: 1 }
                PathArc { x: chipBg.width - 1; y: chipBg.r + 1; radiusX: chipBg.r; radiusY: chipBg.r; direction: PathArc.Clockwise }
                PathLine { x: chipBg.width - 1; y: chipBg.height - chipBg.r - 1 }
                PathArc { x: chipBg.width - chipBg.r - 1; y: chipBg.height - 1; radiusX: chipBg.r; radiusY: chipBg.r; direction: PathArc.Clockwise }
                PathLine { x: chipBg.r + 1; y: chipBg.height - 1 }
                PathArc { x: 1; y: chipBg.height - chipBg.r - 1; radiusX: chipBg.r; radiusY: chipBg.r; direction: PathArc.Clockwise }
                PathLine { x: 1; y: chipBg.r + 1 }
                PathArc { x: chipBg.r + 1; y: 1; radiusX: chipBg.r; radiusY: chipBg.r; direction: PathArc.Clockwise }
            }
        }

        scale: chipMa.pressed ? 0.95 : 1.0
        Behavior on scale { NumberAnimation { duration: 100 } }

        Column {
            anchors.centerIn: parent
            spacing: 2

            DankIcon {
                name: chip.iconName
                size: 14
                visible: chip.iconName.length > 0
                color: chip.active ? chip.accentColor : Theme.surfaceVariantText
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                text: chip.label
                font.pixelSize: Theme.fontSizeSmall
                font.weight: chip.active ? Font.Bold : Font.Normal
                color: chip.active ? chip.accentColor : Theme.surfaceText
                width: Math.min(implicitWidth, chip.width - 8)
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }

        DankRipple {
            id: chipRipple
            anchors.fill: parent
            cornerRadius: chipBg.r
            rippleColor: chip.accentColor
        }

        MouseArea {
            id: chipMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPressed: m => chipRipple.trigger(m.x, m.y)
            onClicked: chip.triggered()
        }
    }

    // Slider plus its label and value pill, so the three of them stay aligned
    // across sections instead of each one recomputing widths by hand.
    component LabeledSlider: RowLayout {
        id: ls

        property string label: ""
        property string iconName: ""
        property color accentColor: Theme.primary
        property alias from: slider.from
        property alias to: slider.to
        property alias value: slider.value
        signal committed(int newValue)

        width: parent.width
        spacing: Theme.spacingS

        DankIcon {
            name: ls.iconName
            size: 18
            color: Theme.surfaceVariantText
            visible: ls.iconName.length > 0
            Layout.alignment: Qt.AlignVCenter
        }

        StyledText {
            text: ls.label
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            visible: ls.label.length > 0
            Layout.preferredWidth: 32
            Layout.alignment: Qt.AlignVCenter
        }

        StyledSlider {
            id: slider
            stepSize: 1
            accentColor: ls.accentColor
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            onPressedChanged: if (!pressed) ls.committed(Math.round(value))
        }

        Rectangle {
            // Implicit, not explicit: QtQuick.Layouts ignores width/height on
            // its children and sizes them from the implicit hints, so an
            // explicit width collapses this to zero inside the RowLayout and
            // the value spills out of the pill.
            implicitHeight: 18
            implicitWidth: Math.max(42, sliderVal.implicitWidth + Theme.spacingS * 2)
            radius: height / 2
            color: Qt.rgba(ls.accentColor.r, ls.accentColor.g, ls.accentColor.b, 0.12)
            Layout.alignment: Qt.AlignVCenter

            StyledText {
                id: sliderVal
                anchors.centerIn: parent
                text: Math.round(slider.value) + "%"
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Bold
                color: ls.accentColor
            }
        }
    }

    // ── Color Picker Component ─────────────────────────────────────────────────

    component ColorPicker: Item {
        id: picker
        height: 120

        property real hue: 0
        property real saturation: 1.0
        property real value: 1.0
        property string hexColor: hsvToHex(hue, saturation, value)

        signal colorSelected(string hex)

        function hsvToHex(h, s, v) {
            var r, g, b
            var i = Math.floor(h / 60) % 6
            var f = (h / 60) - Math.floor(h / 60)
            var p = v * (1 - s)
            var q = v * (1 - f * s)
            var t = v * (1 - (1 - f) * s)
            switch (i) {
                case 0: r = v; g = t; b = p; break
                case 1: r = q; g = v; b = p; break
                case 2: r = p; g = v; b = t; break
                case 3: r = p; g = q; b = v; break
                case 4: r = t; g = p; b = v; break
                default: r = v; g = p; b = q; break
            }
            function toH(c) {
                var x = Math.round(c * 255).toString(16)
                return x.length === 1 ? "0" + x : x
            }
            return toH(r) + toH(g) + toH(b)
        }

        function hexToHsv(hex) {
            hex = hex.replace(/^#/, "")
            if (hex.length !== 6) return null
            var r = parseInt(hex.substr(0, 2), 16) / 255
            var g = parseInt(hex.substr(2, 2), 16) / 255
            var b = parseInt(hex.substr(4, 2), 16) / 255
            var max = Math.max(r, g, b), min = Math.min(r, g, b), d = max - min
            var h = 0, s = max === 0 ? 0 : d / max, v = max
            if (d !== 0) {
                if (max === r) h = 60 * (((g - b) / d) % 6)
                else if (max === g) h = 60 * ((b - r) / d + 2)
                else h = 60 * ((r - g) / d + 4)
            }
            return { h: h < 0 ? h + 360 : h, s: s, v: v }
        }

        Timer {
            id: colorDebounce
            interval: 300
            onTriggered: picker.colorSelected(picker.hexColor)
        }

        onHueChanged: { svCanvas.requestPaint(); colorDebounce.restart() }
        onSaturationChanged: { svCanvas.requestPaint(); colorDebounce.restart() }
        onValueChanged: { svCanvas.requestPaint(); colorDebounce.restart() }

        Column {
            id: pickerCol
            width: parent.width
            spacing: Theme.spacingS

            // Hue gradient strip
            Item {
                width: parent.width
                height: 20

                Rectangle {
                    anchors.fill: parent
                    radius: 4
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.000; color: "#ff0000" }
                        GradientStop { position: 0.167; color: "#ffff00" }
                        GradientStop { position: 0.333; color: "#00ff00" }
                        GradientStop { position: 0.500; color: "#00ffff" }
                        GradientStop { position: 0.667; color: "#0000ff" }
                        GradientStop { position: 0.833; color: "#ff00ff" }
                        GradientStop { position: 1.000; color: "#ff0000" }
                    }
                }

                Rectangle {
                    x: Math.max(0, Math.min(parent.width - width, (picker.hue / 360) * parent.width - width / 2))
                    width: 6
                    height: parent.height
                    radius: 3
                    color: "white"
                    border.width: 1
                    border.color: "#00000060"
                }

                MouseArea {
                    anchors.fill: parent
                    preventStealing: true
                    onPositionChanged: (m) => picker.hue = Math.max(0, Math.min(359.9, m.x / parent.width * 360))
                    onClicked: (m) => picker.hue = Math.max(0, Math.min(359.9, m.x / parent.width * 360))
                }
            }

            // Saturation/Value 2D canvas
            Canvas {
                id: svCanvas
                width: parent.width
                height: 90
                clip: true

                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)

                    var hueColor = Qt.hsva(picker.hue / 360, 1, 1, 1)

                    var gH = ctx.createLinearGradient(0, 0, width, 0)
                    gH.addColorStop(0, "white")
                    gH.addColorStop(1, hueColor.toString())
                    ctx.fillStyle = gH
                    ctx.fillRect(0, 0, width, height)

                    var gV = ctx.createLinearGradient(0, 0, 0, height)
                    gV.addColorStop(0, "rgba(0,0,0,0)")
                    gV.addColorStop(1, "rgba(0,0,0,1)")
                    ctx.fillStyle = gV
                    ctx.fillRect(0, 0, width, height)

                    var cx = picker.saturation * width
                    var cy = (1 - picker.value) * height
                    ctx.beginPath()
                    ctx.arc(cx, cy, 5, 0, Math.PI * 2)
                    ctx.strokeStyle = picker.value > 0.4 ? "black" : "white"
                    ctx.lineWidth = 2
                    ctx.stroke()
                    ctx.beginPath()
                    ctx.arc(cx, cy, 7, 0, Math.PI * 2)
                    ctx.strokeStyle = "white"
                    ctx.lineWidth = 1.5
                    ctx.stroke()
                }

                MouseArea {
                    anchors.fill: parent
                    preventStealing: true
                    onPositionChanged: (m) => {
                        picker.saturation = Math.max(0, Math.min(1, m.x / parent.width))
                        picker.value = Math.max(0, Math.min(1, 1 - m.y / parent.height))
                    }
                    onClicked: (m) => {
                        picker.saturation = Math.max(0, Math.min(1, m.x / parent.width))
                        picker.value = Math.max(0, Math.min(1, 1 - m.y / parent.height))
                    }
                }
            }

        }
    }

    // ── Popout ─────────────────────────────────────────────────────────────────

    popoutContent: Component {
        PopoutComponent {
            headerText: ""
            showCloseButton: false

            Item {
                width: parent.width
                height: mainCol.implicitHeight

                Column {
                    id: mainCol
                    width: parent.width
                    spacing: Theme.spacingM
                    topPadding: 0
                    bottomPadding: 2

                    // Header card
                    StyledRect {
                        width: parent.width
                        height: 72
                        radius: Theme.cornerRadius * 1.5
                        color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                        border.width: 1
                        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingM
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.spacingM
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spacingM

                            Rectangle {
                                width: 42
                                height: 42
                                radius: 21
                                anchors.verticalCenter: parent.verticalCenter
                                color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)

                                DankIcon {
                                    name: "bolt"
                                    size: 22
                                    color: Theme.primary
                                    anchors.centerIn: parent
                                }
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2
                                width: parent.width - 42 - Theme.spacingM

                                StyledText {
                                    width: parent.width
                                    text: "Alienware Control"
                                    font.bold: true
                                    font.pixelSize: Theme.fontSizeLarge
                                    color: Theme.surfaceText
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    width: parent.width
                                    text: root.currentMode + (root.turboEnabled ? " • Turbo on" : "")
                                    font.pixelSize: Theme.fontSizeSmall - 1
                                    color: Theme.primary
                                    opacity: 0.85
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }

                    // Thermal modes
                    SectionCard {
                        iconName: "bolt"
                        title: "THERMAL MODE"
                        subtitle: root.currentMode
                        accentColor: Theme.primary
                        visible: root.hasThermalModes

                        Column {
                            id: modesColumn
                            width: parent.width
                            spacing: Theme.spacingXS

                            readonly property int buttonWidth: Math.floor((width - 3 * Theme.spacingXS) / 4)

                            Repeater {
                                model: Math.ceil(root.thermalModes.length / 4)

                                Row {
                                    readonly property var rowModes: root.thermalModes.slice(index * 4, Math.min((index + 1) * 4, root.thermalModes.length))
                                    spacing: Theme.spacingXS
                                    anchors.horizontalCenter: parent.horizontalCenter

                                    Repeater {
                                        model: rowModes

                                        ActionChip {
                                            width: modesColumn.buttonWidth
                                            height: 50
                                            label: modelData.label
                                            iconName: modelData.icon
                                            accentColor: Theme.primary
                                            active: root.currentMode.toLowerCase() === modelData.label.toLowerCase()

                                            onTriggered: {
                                                const cmd = modelData.cmd
                                                const label = modelData.label
                                                root.runAwcc("setMode", [cmd], (stdout, exitCode) => {
                                                    if (exitCode === 0) {
                                                        root.currentMode = label
                                                        root.showToast("Thermal mode: " + label)
                                                    }
                                                })
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Fan boost
                    SectionCard {
                        iconName: "wind_power"
                        title: "FAN BOOST"
                        subtitle: "CPU " + root.cpuBoost + "% • GPU " + root.gpuBoost + "%"
                        accentColor: Theme.primary
                        visible: root.hasFanBoost

                        LabeledSlider {
                            label: "CPU"
                            from: 1
                            to: 100
                            value: root.cpuBoost
                            accentColor: Theme.primary
                            onCommitted: newValue => {
                                root.cpuBoost = newValue
                                pluginService?.savePluginData("awcc", "cpuBoost", newValue)
                                root.runAwcc("scb", ["scb", newValue.toString()], () => {})
                            }
                        }

                        LabeledSlider {
                            label: "GPU"
                            from: 1
                            to: 100
                            value: root.gpuBoost
                            accentColor: Theme.primary
                            onCommitted: newValue => {
                                root.gpuBoost = newValue
                                pluginService?.savePluginData("awcc", "gpuBoost", newValue)
                                root.runAwcc("sgb", ["sgb", newValue.toString()], () => {})
                            }
                        }
                    }

                    // Keyboard lighting
                    SectionCard {
                        id: kbSection
                        iconName: "keyboard"
                        title: "KEYBOARD"
                        subtitle: root.hasBrightness ? (root.kbBrightness + "% brightness") : ""
                        accentColor: Theme.secondary
                        visible: root.hasBrightness || root.hasLightingEffects

                        readonly property bool needsColor: ["static", "breathe", "wave", "bkf"].indexOf(root.kbEffect) >= 0

                        LabeledSlider {
                            iconName: "brightness_high"
                            from: 0
                            to: 100
                            value: root.kbBrightness
                            accentColor: Theme.secondary
                            visible: root.hasBrightness
                            onCommitted: newValue => {
                                root.kbBrightness = newValue
                                pluginService?.savePluginData("awcc", "kbBrightness", newValue)
                                root.runAwcc("brightness", ["brightness", newValue.toString()], () => {})
                            }
                        }

                        Flow {
                            width: parent.width
                            spacing: Theme.spacingXS
                            visible: root.hasLightingEffects

                            Repeater {
                                model: root.kbEffects

                                ActionChip {
                                    height: 28
                                    width: Math.max(64, label.length * 8 + Theme.spacingM * 2)
                                    label: modelData.label
                                    accentColor: Theme.secondary
                                    active: root.kbEffect === modelData.cmd

                                    onTriggered: {
                                        const cmd = modelData.cmd
                                        const needsCol = modelData.needsColor
                                        root.kbEffect = cmd
                                        pluginService?.savePluginData("awcc", "kbEffect", cmd)
                                        root.runAwcc("kbEffect", needsCol ? [cmd, root.kbColor] : [cmd], () => {})
                                        root.showToast("Keyboard: " + modelData.label)
                                    }
                                }
                            }
                        }

                        ColorPicker {
                            width: parent.width
                            visible: kbSection.needsColor && root.hasLightingEffects
                            height: (kbSection.needsColor && root.hasLightingEffects) ? 120 : 0
                            clip: true

                            Component.onCompleted: {
                                const hsv = hexToHsv(root.kbColor)
                                if (hsv) { hue = hsv.h; saturation = hsv.s; value = hsv.v }
                            }

                            onColorSelected: hex => {
                                root.kbColor = hex
                                pluginService?.savePluginData("awcc", "kbColor", hex)
                                root.runAwcc("kbColor", [root.kbEffect, hex], () => {})
                            }
                        }
                    }

                    // Turbo
                    SectionCard {
                        iconName: "rocket_launch"
                        title: "TURBO"
                        subtitle: root.turboEnabled ? "on" : "off"
                        accentColor: Theme.secondary
                        visible: root.hasTurbo

                        RowLayout {
                            width: parent.width
                            spacing: Theme.spacingM

                            StyledText {
                                text: "CPU Turbo Boost"
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceText
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                            }

                            Switch {
                                checked: root.turboEnabled
                                Layout.alignment: Qt.AlignVCenter

                                onCheckedChanged: {
                                    if (checked !== root.turboEnabled) {
                                        root.turboEnabled = checked
                                        root.runAwcc("setturbo", ["setturbo", checked ? "1" : "0"], () => {})
                                        root.showToast("CPU Turbo " + (checked ? "on" : "off"))
                                    }
                                }
                            }
                        }
                    }
                }

                // Toast, for the discrete changes that actually hit the hardware
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Theme.spacingS
                    height: 32
                    width: toastLayout.implicitWidth + Theme.spacingM * 2
                    radius: height / 2
                    color: Qt.rgba(Theme.surfaceContainerHighest.r, Theme.surfaceContainerHighest.g, Theme.surfaceContainerHighest.b, 0.95)
                    border.width: 1
                    border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.4)
                    z: 999
                    opacity: toastTimer.running ? 1.0 : 0.0
                    scale: toastTimer.running ? 1.0 : 0.75

                    Behavior on opacity { NumberAnimation { duration: 200 } }
                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

                    RowLayout {
                        id: toastLayout
                        anchors.centerIn: parent
                        spacing: Theme.spacingXS

                        DankIcon { name: "info"; size: 16; color: Theme.primary }

                        StyledText {
                            text: root.toastText
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Bold
                            color: Theme.surfaceText
                        }
                    }
                }
            }
        }
    }

    popoutWidth: 420
    popoutHeight: 0
}
