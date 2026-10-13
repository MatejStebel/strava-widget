import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    property alias cfg_cafeteria: cafeteria.text
    property alias cfg_username: username.text
    property alias cfg_displayName: displayName.text
    property alias cfg_showUnordered: showUnordered.checked
    property alias cfg_refreshInterval: refreshInterval.value

    QQC2.TextField {
        id: cafeteria
        Kirigami.FormData.label: i18n("Cafeteria number:")
        placeholderText: "0000"
        validator: RegularExpressionValidator { regularExpression: /[0-9]+/ }
        Layout.fillWidth: true
    }
    QQC2.TextField {
        id: username
        Kirigami.FormData.label: i18n("Login-username:")
        Layout.fillWidth: true
    }
    QQC2.TextField {
        id: displayName
        Kirigami.FormData.label: i18n("Display name:")
        Layout.fillWidth: true
    }
    QQC2.CheckBox {
        id: showUnordered
        Kirigami.FormData.label: i18n("Meals:")
        text: i18n("Show meals I haven't ordered")
    }
    QQC2.SpinBox {
        id: refreshInterval
        Kirigami.FormData.label: i18n("Refresh interval (minutes):")
        from: 1
        to: 1440
        editable: true
    }
    QQC2.Button {
        Kirigami.FormData.label: i18n("Account:")
        text: i18n("Forget password and log out")
        icon.name: "system-log-out"
        enabled: plasmoid.configuration.username !== "" && plasmoid.configuration.cafeteria !== ""
        onClicked: plasmoid.configuration.logoutRequested = true
    }
}
