import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "awcc"

    StyledText {
        width: parent.width
        text: "AWCC Control"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Configure the AWCC binary path and polling interval."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StringSetting {
        settingKey: "awccBinary"
        label: "AWCC Binary Path"
        description: "Path to the awcc executable"
        defaultValue: "awcc"
        placeholder: "awcc"
    }

    SliderSetting {
        settingKey: "refreshInterval"
        label: "Refresh Interval"
        description: "How often to poll the current thermal mode (in seconds)."
        defaultValue: 10
        minimum: 1
        maximum: 60
        unit: "sec"
        leftIcon: "schedule"
    }
}
