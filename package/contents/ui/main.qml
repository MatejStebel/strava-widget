import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import "../code/strava.js" as Strava

PlasmoidItem {
    id: root
    preferredRepresentation: fullRepresentation
    property string sessionPassword: ""
    property string accessToken: ""
    property string s5url: ""
    property string apiStatus: ""
    property string credentialStatus: ""
    property bool apiBusy: false
    property int sessionGeneration: 0
    property var activeRequest: null
    property var meals: []
    property bool menuLoaded: false
    property int selectedOffset: 0
    property date currentDay: new Date()
    readonly property date selectedDate: Strava.dayOffset(currentDay, selectedOffset)
    readonly property string selectedKey: Strava.localDate(selectedDate)
    readonly property var visibleMeals: Strava.mealsForDay(meals, selectedKey, plasmoid.configuration.showUnordered)
    readonly property bool unknownOrders: meals.some(function(meal) { return meal.date === selectedKey && !meal.orderKnown })
    property bool logoutRequested: plasmoid.configuration.logoutRequested

    onLogoutRequestedChanged: {
        if (logoutRequested) {
            forgetPasswordAndLogout()
            plasmoid.configuration.logoutRequested = false
        }
    }
    Loader {
        id: walletLoader
        source: "WalletDbus.qml"
        onLoaded: Qt.callLater(function() { root.tryAutomaticLogin() })
        onStatusChanged: {
            if (status === Loader.Error)
                root.credentialStatus = i18n("Password storage is unavailable. You can still log in for this session.")
        }
    }
    Timer {
        id: refreshTimer
        interval: Math.max(1, plasmoid.configuration.refreshInterval) * 60000
        repeat: true
        running: root.accessToken !== ""
        onTriggered: root.fetchMenu()
    }
    Timer {
        interval: 30000
        repeat: true
        running: true
        onTriggered: {
            var now = new Date()
            if (Strava.localDate(now) !== Strava.localDate(root.currentDay)) {
                root.currentDay = now
                root.fetchMenu()
            }
        }
    }
    Timer {
        id: requestTimeout
        interval: 30000
        onTriggered: {
            var request = root.activeRequest
            root.activeRequest = null
            root.apiBusy = false
            root.sessionPassword = ""
            root.apiStatus = i18n("Request timed out. Please retry.")
            if (request) request.abort()
        }
    }
    Connections {
        target: plasmoid.configuration
        function onCafeteriaChanged() { root.accountChanged() }
        function onUsernameChanged() { root.accountChanged() }
    }
    function walletKey() {
        var cafeteria = plasmoid.configuration.cafeteria.trim()
        var username = plasmoid.configuration.username.trim()
        return cafeteria && username ? JSON.stringify([cafeteria, username]) : ""
    }
    function accountChanged() {
        clearLoginSession()
        Qt.callLater(function() { root.tryAutomaticLogin() })
    }
    function clearLoginSession() {
        ++root.sessionGeneration
        requestTimeout.stop()
        var request = root.activeRequest
        root.activeRequest = null
        if (request) request.abort()
        root.accessToken = ""
        root.s5url = ""
        root.sessionPassword = ""
        root.meals = []
        root.menuLoaded = false
        root.apiBusy = false
        root.apiStatus = i18n("Logged out")
        root.credentialStatus = ""
    }
    function savePasswordToWallet(key, password, generation) {
        if (!walletLoader.item) {
            root.credentialStatus = i18n("Logged in, but the password could not be saved.")
            return
        }
        walletLoader.item.savePassword(key, password, function(error) {
            if (generation !== root.sessionGeneration) return
            root.credentialStatus = error ? i18n("Logged in, but the password could not be saved to KWallet.") : ""
        })
    }
    function forgetPasswordAndLogout() {
        var key = root.walletKey()
        clearLoginSession()
        var generation = root.sessionGeneration
        if (!key) return
        if (!walletLoader.item) {
            root.credentialStatus = i18n("Logged out, but the saved password could not be removed.")
            return
        }
        walletLoader.item.deletePassword(key, function(error) {
            if (generation !== root.sessionGeneration) return
            root.credentialStatus = error ? i18n("Logged out, but the saved password could not be removed from KWallet.") : ""
        })
    }
    function tryAutomaticLogin() {
        var key = root.walletKey()
        if (!key || !walletLoader.item || root.accessToken || root.apiBusy || root.sessionPassword) return
        var generation = root.sessionGeneration
        walletLoader.item.loadPassword(key, function(error, password) {
            if (generation !== root.sessionGeneration || key !== root.walletKey()
                    || root.apiBusy || root.accessToken || root.sessionPassword) return
            if (error) {
                root.credentialStatus = i18n("Could not read KWallet. Enter your password to log in.")
                return
            }
            if (password) {
                root.sessionPassword = password
                root.login()
            }
        })
    }
    function apiRequest(endpoint, body, callback) {
        var request = new XMLHttpRequest()
        var generation = root.sessionGeneration
        var key = root.walletKey()
        root.activeRequest = request
        root.apiBusy = true
        // Strava accepts POST for reading orders too; QML XHR drops GET bodies.
        request.open("POST", "https://app.strava.cz/api/" + endpoint)
        request.setRequestHeader("Content-Type", "text/plain;charset=UTF-8")
        request.onreadystatechange = function() {
            if (request.readyState !== XMLHttpRequest.DONE || root.activeRequest !== request) return
            requestTimeout.stop()
            root.activeRequest = null
            root.apiBusy = false
            if (generation !== root.sessionGeneration || key !== root.walletKey()) return
            if (request.status !== 200) {
                callback(i18n("Connection failed (HTTP %1). Please retry.", request.status), null, "")
                return
            }
            var data
            try { data = JSON.parse(request.responseText) }
            catch (error) {
                callback(i18n("Invalid response from Strava.cz."), null, "")
                return
            }
            var code = Strava.errorCode(data)
            callback(code ? i18n("Strava.cz error %1. Check your account details or retry.", code) : "", data, code)
        }
        requestTimeout.restart()
        request.send(JSON.stringify(body))
    }
    function login() {
        if (root.apiBusy) return
        if (!root.walletKey() || !/^\d+$/.test(plasmoid.configuration.cafeteria.trim())) {
            root.apiStatus = i18n("Set your cafeteria number and username in the widget settings.")
            return
        }
        if (!root.sessionPassword) {
            root.apiStatus = i18n("Enter your Strava.cz password.")
            return
        }
        var password = root.sessionPassword
        var key = root.walletKey()
        var generation = root.sessionGeneration
        root.sessionPassword = ""
        root.apiStatus = i18n("Logging in...")
        apiRequest("login", Strava.loginBody(plasmoid.configuration.cafeteria.trim(),
            plasmoid.configuration.username.trim(), password), function(error, data) {
            if (error || !data || typeof data.sid !== "string" || !data.sid) {
                password = ""
                root.apiStatus = error || i18n("Login response has no session. Check your account details.")
                return
            }
            root.accessToken = data.sid
            root.s5url = typeof data.s5url === "string" ? data.s5url : ""
            root.savePasswordToWallet(key, password, generation)
            password = ""
            root.fetchMenu()
        })
    }
    function fetchMenu() {
        if (!root.accessToken || root.apiBusy) return
        root.apiStatus = i18n("Loading meals...")
        apiRequest("objednavky", Strava.menuBody(plasmoid.configuration.cafeteria.trim(),
            root.accessToken, root.s5url), function(error, data, code) {
            if (error) {
                if (["15", "10102", "13404", "13405"].indexOf(code) !== -1) {
                    root.clearLoginSession()
                    root.apiStatus = i18n("Session expired. Enter your password to log in again.")
                } else {
                    root.apiStatus = root.menuLoaded ? i18n("Refresh failed. Showing previously loaded meals. %1", error) : error
                }
                return
            }
            try {
                root.meals = Strava.parseMenu(data)
                root.menuLoaded = true
                root.apiStatus = i18n("Updated at %1", Qt.formatTime(new Date(), "HH:mm"))
            } catch (error) {
                root.apiStatus = i18n("Unsupported menu response from this cafeteria.")
                if (root.menuLoaded) root.apiStatus += " " + i18n("Showing previously loaded meals.")
            }
        })
    }
    fullRepresentation: Item {
        implicitWidth: 480
        implicitHeight: 420
        Layout.minimumWidth: 320
        Layout.minimumHeight: 260
        ColumnLayout {
            anchors.fill: parent
            spacing: 5
            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: plasmoid.configuration.displayName.trim()
                    ? i18n("Meals — %1", plasmoid.configuration.displayName.trim()) : i18n("Meals")
                textFormat: Text.PlainText
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: 20
                font.bold: true
            }
            RowLayout {
                Layout.fillWidth: true
                visible: !root.accessToken
                TextField {
                    Layout.fillWidth: true
                    text: root.sessionPassword
                    placeholderText: i18n("Strava.cz password")
                    echoMode: TextInput.Password
                    enabled: !root.apiBusy
                    onTextEdited: root.sessionPassword = text
                    onAccepted: root.login()
                }
                Button {
                    text: root.apiBusy ? i18n("Loading...") : i18n("Login")
                    enabled: !root.apiBusy
                    onClicked: root.login()
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Button {
                    text: i18n("Today")
                    checkable: true
                    checked: root.selectedOffset === 0
                    onClicked: root.selectedOffset = 0
                }
                Button {
                    text: i18n("Tomorrow")
                    checkable: true
                    checked: root.selectedOffset === 1
                    onClicked: root.selectedOffset = 1
                }
                Item { Layout.fillWidth: true }
                Button {
                    text: i18n("Refresh")
                    enabled: !!root.accessToken && !root.apiBusy
                    onClicked: root.fetchMenu()
                }
            }
            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: Qt.formatDate(root.selectedDate, "dddd, d MMMM yyyy")
                horizontalAlignment: Text.AlignHCenter
                font.bold: true
            }
            PlasmaComponents.Label {
                Layout.fillWidth: true
                visible: !!root.credentialStatus
                text: root.credentialStatus
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
            }
            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: root.apiStatus
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                opacity: 0.8
                horizontalAlignment: Text.AlignHCenter
            }
            PlasmaComponents.Label {
                Layout.fillWidth: true
                visible: root.unknownOrders
                text: i18n("Some meals have no order status. Enable unordered meals in settings to view them.")
                wrapMode: Text.WordWrap
            }
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: availableWidth
                ColumnLayout {
                    width: parent.width
                    spacing: 5
                    Repeater {
                        model: root.visibleMeals
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: mealColumn.implicitHeight + 16
                            radius: 6
                            color: modelData.ordered ? Qt.rgba(0.7, 0.7, 0.7, 0.25) : Qt.rgba(0.7, 0.7, 0.7, 0.08)
                            ColumnLayout {
                                id: mealColumn
                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                                PlasmaComponents.Label {
                                    Layout.fillWidth: true
                                    text: modelData.course + " · " + (modelData.ordered ? i18n("Ordered (%1)", modelData.count)
                                        : (modelData.orderKnown ? i18n("Not ordered") : i18n("Order status unknown")))
                                    textFormat: Text.PlainText
                                    wrapMode: Text.WordWrap
                                    opacity: 0.8
                                }
                                PlasmaComponents.Label {
                                    Layout.fillWidth: true
                                    text: modelData.name
                                    textFormat: Text.PlainText
                                    wrapMode: Text.WordWrap
                                    font.bold: true
                                    font.pixelSize: 16
                                }
                                PlasmaComponents.Label {
                                    Layout.fillWidth: true
                                    visible: !!modelData.description && modelData.description !== modelData.name
                                    text: modelData.description
                                    textFormat: Text.PlainText
                                    wrapMode: Text.WordWrap
                                }
                                PlasmaComponents.Label {
                                    Layout.fillWidth: true
                                    visible: !!modelData.allergens
                                    text: i18n("Allergens: %1", modelData.allergens)
                                    textFormat: Text.PlainText
                                    wrapMode: Text.WordWrap
                                    opacity: 0.7
                                }
                            }
                        }
                    }
                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        visible: root.visibleMeals.length === 0
                        text: !root.accessToken ? i18n("Configure your account in settings, then enter your password.")
                            : (!root.menuLoaded ? (root.apiBusy ? i18n("Loading meals...") : i18n("Meals have not been loaded. Press Refresh to retry."))
                            : (plasmoid.configuration.showUnordered ? i18n("No menu available for this day.") : i18n("No ordered meals for this day.")))
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                        opacity: 0.8
                    }
                }
            }
        }
    }
}
