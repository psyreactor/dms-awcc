import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "awcc"

    // Section header: icon, title and a one-line explanation of the group.
    component GroupHeader: RowLayout {
        property string iconName: ""
        property string title: ""
        property string subtitle: ""

        width: parent.width
        spacing: Theme.spacingM

        DankIcon {
            name: iconName
            size: 22
            color: Theme.primary
            Layout.alignment: Qt.AlignVCenter
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            StyledText {
                text: title
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
                Layout.fillWidth: true
            }

            StyledText {
                text: subtitle
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }
        }
    }

    // Card wrapper matching the popout's cards.
    component SettingsGroup: StyledRect {
        default property alias content: groupCol.data

        width: parent.width
        height: Math.max(0, groupCol.implicitHeight + Theme.spacingM * 2)
        radius: Theme.cornerRadius
        color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
        border.width: 1
        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)

        Column {
            id: groupCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.spacingM
            spacing: Theme.spacingL
        }
    }

    Column {
        width: parent.width
        spacing: Theme.spacingL

        SettingsGroup {
            GroupHeader {
                iconName: "terminal"
                title: "AWCC CLI"
                subtitle: "The awcc executable this widget drives, and how often it re-reads the current mode."
            }

            StringSetting {
                settingKey: "awccBinary"
                label: "AWCC Binary Path"
                description: "Path to the awcc executable."
                defaultValue: "awcc"
                placeholder: "awcc"
            }

            SliderSetting {
                settingKey: "refreshInterval"
                label: "Refresh Interval"
                description: "How often to poll the current thermal mode, in seconds."
                defaultValue: 10
                minimum: 1
                maximum: 60
                unit: "sec"
                leftIcon: "schedule"
            }
        }
    }
}
