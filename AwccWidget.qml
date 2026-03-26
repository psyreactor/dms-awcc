import QtQuick
import QtQuick.Controls
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

    // State
    property string currentMode: "..."
    property int cpuBoost: 0
    property int gpuBoost: 0
    property bool turboEnabled: false
    property int kbBrightness: pluginData.kbBrightness !== undefined ? pluginData.kbBrightness : 50
    property int lbBrightness: pluginData.lbBrightness !== undefined ? pluginData.lbBrightness : 50
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
    property bool hasLightBar:        false  // not listed in device-info
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

    function runAwcc(id, args, callback) {
        Proc.runCommand("awcc." + id, [root.awccBinary].concat(args), callback, 500)
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

    verticalBarPill: Component {
        DankIcon {
            name: "bolt"
            size: 24
            color: Theme.primary
        }
    }

    // ── Styled Slider ──────────────────────────────────────────────────────────

    component StyledSlider: Slider {
        id: sliderControl

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
                color: Theme.primary
                radius: 2
            }
        }

        handle: Rectangle {
            x: sliderControl.leftPadding + sliderControl.visualPosition * (sliderControl.availableWidth - width)
            y: sliderControl.topPadding + sliderControl.availableHeight / 2 - height / 2
            implicitWidth: 20
            implicitHeight: 20
            radius: 10
            color: sliderControl.pressed ? Qt.darker(Theme.primary, 1.1) : Theme.primary
            border.color: Theme.primary
            border.width: 2
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
        Flickable {
            implicitWidth: root.popoutWidth
            implicitHeight: root.popoutHeight
            contentWidth: width
            contentHeight: mainCol.height + Theme.spacingM * 2
            clip: true


            Column {
                id: mainCol
                x: Theme.spacingM
                y: Theme.spacingM
                width: parent.width - Theme.spacingM * 2
                spacing: Theme.spacingM

                // ── THERMAL MODE ──────────────────────────────────────────────

                Column {
                    id: thermalSection
                    width: parent.width
                    spacing: Theme.spacingS
                    visible: root.hasThermalModes

                    Row {
                        spacing: Theme.spacingS
                        DankIcon { name: "bolt"; size: 16; color: Theme.primary; anchors.verticalCenter: parent.verticalCenter }
                        StyledText {
                            text: "THERMAL MODE"
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Bold
                            color: Theme.surfaceVariantText
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

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

                                    Rectangle {
                                        width: modesColumn.buttonWidth
                                        height: 50
                                        radius: Theme.cornerRadius

                                        readonly property bool active: root.currentMode.toLowerCase() === modelData.label.toLowerCase()

                                        color: active ? Theme.primary
                                                      : modeArea.containsMouse ? Theme.surfaceContainerHigh : Theme.surfaceContainer
                                        border.width: 0

                                        Column {
                                            anchors.centerIn: parent
                                            spacing: 2

                                            DankIcon {
                                                name: modelData.icon
                                                size: 14
                                                color: parent.parent.active ? Theme.primaryText : Theme.surfaceVariantText
                                                anchors.horizontalCenter: parent.horizontalCenter
                                            }

                                            StyledText {
                                                text: modelData.label
                                                font.pixelSize: Theme.fontSizeSmall
                                                color: parent.parent.active ? Theme.primaryText : Theme.surfaceText
                                                font.weight: parent.parent.active ? Font.Bold : Font.Normal
                                                elide: Text.ElideRight
                                                width: modesColumn.buttonWidth - 8
                                                horizontalAlignment: Text.AlignHCenter
                                            }
                                        }

                                        MouseArea {
                                            id: modeArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                var cmd = modelData.cmd
                                                var label = modelData.label
                                                root.runAwcc("setMode", [cmd], (stdout, exitCode) => {
                                                    if (exitCode === 0) root.currentMode = label
                                                })
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width; height: 1
                    color: Theme.outline; opacity: 0.3
                    visible: root.hasThermalModes && root.hasFanBoost
                }

                // ── FAN BOOST ─────────────────────────────────────────────────

                Column {
                    width: parent.width
                    spacing: Theme.spacingS
                    visible: root.hasFanBoost

                    Row {
                        spacing: Theme.spacingS
                        DankIcon { name: "wind_power"; size: 16; color: Theme.primary; anchors.verticalCenter: parent.verticalCenter }
                        StyledText {
                            text: "FAN BOOST"
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Bold
                            color: Theme.surfaceVariantText
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: Theme.spacingS

                        StyledText {
                            text: "CPU"
                            width: 32
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledSlider {
                            id: cpuBoostSlider
                            width: parent.width - 32 - 40 - Theme.spacingS * 2
                            from: 1; to: 100; stepSize: 1
                            value: root.cpuBoost
                            anchors.verticalCenter: parent.verticalCenter
                            onPressedChanged: {
                                if (!pressed) {
                                    root.cpuBoost = Math.round(value)
                                    pluginService?.savePluginData("awcc", "cpuBoost", root.cpuBoost)
                                    root.runAwcc("scb", ["scb", Math.round(value).toString()], () => {})
                                }
                            }
                        }

                        StyledText {
                            text: Math.round(cpuBoostSlider.value) + "%"
                            width: 40
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceText
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: Theme.spacingS

                        StyledText {
                            text: "GPU"
                            width: 32
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledSlider {
                            id: gpuBoostSlider
                            width: parent.width - 32 - 40 - Theme.spacingS * 2
                            from: 1; to: 100; stepSize: 1
                            value: root.gpuBoost
                            anchors.verticalCenter: parent.verticalCenter
                            onPressedChanged: {
                                if (!pressed) {
                                    root.gpuBoost = Math.round(value)
                                    pluginService?.savePluginData("awcc", "gpuBoost", root.gpuBoost)
                                    root.runAwcc("sgb", ["sgb", Math.round(value).toString()], () => {})
                                }
                            }
                        }

                        StyledText {
                            text: Math.round(gpuBoostSlider.value) + "%"
                            width: 40
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceText
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }

                Rectangle {
                    width: parent.width; height: 1
                    color: Theme.outline; opacity: 0.3
                    visible: root.hasFanBoost && (root.hasBrightness || root.hasLightingEffects)
                }

                // ── KEYBOARD LIGHTING ─────────────────────────────────────────

                Column {
                    id: kbSection
                    width: parent.width
                    spacing: Theme.spacingS
                    visible: root.hasBrightness || root.hasLightingEffects

                    property bool needsColor: ["static", "breathe", "wave", "bkf"].indexOf(root.kbEffect) >= 0

                    Row {
                        spacing: Theme.spacingS
                        DankIcon { name: "keyboard"; size: 16; color: Theme.primary; anchors.verticalCenter: parent.verticalCenter }
                        StyledText {
                            text: "KEYBOARD"
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Bold
                            color: Theme.surfaceVariantText
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: Theme.spacingS
                        visible: root.hasBrightness

                        DankIcon {
                            name: "brightness_high"
                            size: 18
                            color: Theme.surfaceVariantText
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledSlider {
                            id: kbBrightnessSlider
                            width: parent.width - 18 - 40 - Theme.spacingS * 2
                            from: 0; to: 100; stepSize: 1
                            value: root.kbBrightness
                            anchors.verticalCenter: parent.verticalCenter
                            onPressedChanged: {
                                if (!pressed) {
                                    root.kbBrightness = Math.round(value)
                                    pluginService?.savePluginData("awcc", "kbBrightness", root.kbBrightness)
                                    root.runAwcc("brightness", ["brightness", Math.round(value).toString()], () => {})
                                }
                            }
                        }

                        StyledText {
                            text: Math.round(kbBrightnessSlider.value) + "%"
                            width: 40
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceText
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Flow {
                        id: kbEffectsFlow
                        width: parent.width
                        spacing: Theme.spacingXS
                        visible: root.hasLightingEffects

                        Repeater {
                            model: root.kbEffects

                            Rectangle {
                                height: 28
                                width: kbEffLabel.implicitWidth + Theme.spacingM * 2
                                radius: Theme.cornerRadius
                                color: {
                                    if (root.kbEffect === modelData.cmd) return Theme.primaryContainer
                                    return kbEffArea.containsMouse ? Theme.surfaceContainerHigh : Theme.surfaceContainer
                                }
                                border.width: root.kbEffect === modelData.cmd ? 1 : 0
                                border.color: Theme.primary

                                StyledText {
                                    id: kbEffLabel
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceText
                                }

                                MouseArea {
                                    id: kbEffArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        var cmd = modelData.cmd
                                        var needsCol = modelData.needsColor
                                        root.kbEffect = cmd
                                        pluginService?.savePluginData("awcc", "kbEffect", cmd)
                                        var args = needsCol ? [cmd, root.kbColor] : [cmd]
                                        root.runAwcc("kbEffect", args, () => {})
                                    }
                                }
                            }
                        }
                    }

                    ColorPicker {
                        id: kbColorPicker
                        width: parent.width
                        visible: kbSection.needsColor && root.hasLightingEffects
                        height: (kbSection.needsColor && root.hasLightingEffects) ? 120 : 0
                        clip: true

                        Component.onCompleted: {
                            var hsv = hexToHsv(root.kbColor)
                            if (hsv) { hue = hsv.h; saturation = hsv.s; value = hsv.v }
                        }

                        onColorSelected: (hex) => {
                            root.kbColor = hex
                            pluginService?.savePluginData("awcc", "kbColor", hex)
                            root.runAwcc("kbColor", [root.kbEffect, hex], () => {})
                        }
                    }
                }

                // ── TURBO ─────────────────────────────────────────────────────

                Rectangle {
                    width: parent.width; height: 1
                    color: Theme.outline; opacity: 0.3
                    visible: root.hasTurbo && (root.hasBrightness || root.hasLightingEffects)
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingS
                    visible: root.hasTurbo

                    Row {
                        spacing: Theme.spacingS
                        DankIcon { name: "rocket_launch"; size: 16; color: Theme.primary; anchors.verticalCenter: parent.verticalCenter }
                        StyledText {
                            text: "TURBO"
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Bold
                            color: Theme.surfaceVariantText
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Row {
                        width: parent.width

                        StyledText {
                            text: "CPU Turbo Boost"
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceText
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - turboSwitch.width
                        }

                        Switch {
                            id: turboSwitch
                            checked: root.turboEnabled
                            anchors.verticalCenter: parent.verticalCenter

                            onCheckedChanged: {
                                if (checked !== root.turboEnabled) {
                                    root.turboEnabled = checked
                                    root.runAwcc("setturbo", ["setturbo", checked ? "1" : "0"], () => {})
                                }
                            }
                        }
                    }
                }

                // Bottom padding
                Item { width: parent.width; height: Theme.spacingM }
            }
        }
    }

    popoutWidth: 420
    popoutHeight: 560
}
