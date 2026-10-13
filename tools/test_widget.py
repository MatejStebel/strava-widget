#!/usr/bin/env python3
"""Offline tests of the actual JavaScript/QML functions; no accounts or network."""
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')
os.environ.setdefault('QT_QUICK_BACKEND', 'software')
from PySide6.QtGui import QGuiApplication
from PySide6.QtCore import QUrl, qInstallMessageHandler
from PySide6.QtQml import QJSEngine, QQmlEngine, QQmlComponent
from PySide6.QtQuick import QQuickWindow

APP = QGuiApplication([])
PACKAGE = Path(__file__).resolve().parents[1] / 'package'
JS = (PACKAGE / 'contents/code/strava.js').read_text()
MAIN = (PACKAGE / 'contents/ui/main.qml').read_text()


class Adapter(unittest.TestCase):
    def setUp(self):
        self.engine = QJSEngine()
        self.js(JS + '\nfunction assert(v, m) { if (!v) throw new Error(m || "Assertion failed") }')

    def js(self, code):
        result = self.engine.evaluate(code)
        self.assertFalse(result.isError(), result.toString() + '\n' + result.property('stack').toString())

    def test_varied_tables_dates_and_order_counts(self):
        self.js('''
            var menu = parseMenu({table10: [{datum:'2026-10-14T00:00:00', nazev:'Dinner', pocet:'2'}],
                table0: [{datum:'13.10.2026', nazev:'Soup', pocet:1},
                    {datum:'13.10.2026', nazev:'Lunch 2', pocet:'0'},
                    {datum:'13.10.2026', nazev:'Unknown'},
                    {datum:'13.10.2026', nazev:'Unknown null', pocet:null}],
                metadata: 'ignored'});
            assert(mealsForDay(menu, '2026-10-13', false).length === 1);
            assert(mealsForDay(menu, '2026-10-13', true).length === 4);
            assert(mealsForDay(menu, '2026-10-14', false)[0].count === 2);
            assert(mealsForDay(menu, '2026-10-15', true).length === 0);
            assert(!menu[2].orderKnown && !menu[3].orderKnown);
            assert(parseMenu({table0:[]}).length === 0);
        ''')

    def test_bad_responses_are_not_empty_days(self):
        self.js('''
            [null, {}, [], {table0:{}}, {table0:[{nazev:'Lunch', datum:'bad'}]}].forEach(function(data) {
                var failed = false;
                try { parseMenu(data) } catch (e) { failed = true }
                assert(failed);
            });
            assert(errorCode({state:'error', number:15}) === '15');
        ''')

    def test_calendar_and_credentials(self):
        self.js('''
            assert(localDate(dayOffset(new Date(2026,11,31),1)) === '2027-01-01');
            assert(localDate(dayOffset(new Date(2026,9,25),1)) === '2026-10-26');
            assert(dateKey('1. 2. 2026') === '2026-02-01');
            var body = loginBody('0012','u','p');
            assert(body.cislo === '0012' && body.heslo === 'p' && !body.zustatPrihlasen);
            assert(menuBody('0012','sid','hash').s5url === 'hash');
        ''')


class Lifecycle(unittest.TestCase):
    js = Adapter.js

    def setUp(self):
        Adapter.setUp(self)
        self.js('''
            var Strava = {loginBody:loginBody, menuBody:menuBody, parseMenu:parseMenu, errorCode:errorCode};
            var root = {sessionPassword:'',accessToken:'',s5url:'',apiStatus:'',credentialStatus:'',
                apiBusy:false,sessionGeneration:0,activeRequest:null,meals:[],menuLoaded:false};
            var plasmoid = {configuration:{cafeteria:'0012',username:'test'}};
            var requestTimeout = {stop:function(){},restart:function(){}};
            var Qt = {callLater:function(f){f()},formatTime:function(){return '12:00'}};
            function i18n(s){return s}
            var walletOps = [];
            var walletLoader = {item:{
                loadPassword:function(key,cb){walletOps.push({op:'load',key:key,cb:cb})},
                savePassword:function(key,pw,cb){walletOps.push({op:'save',key:key,pw:pw,cb:cb})},
                deletePassword:function(key,cb){walletOps.push({op:'delete',key:key,cb:cb})}
            }};
            var requests = [];
            function XMLHttpRequest(){requests.push(this)}
            XMLHttpRequest.DONE=4;
            XMLHttpRequest.prototype.open=function(method,url){this.method=method;this.url=url};
            XMLHttpRequest.prototype.setRequestHeader=function(){};
            XMLHttpRequest.prototype.send=function(body){this.body=JSON.parse(body)};
            XMLHttpRequest.prototype.abort=function(){this.aborted=true};
            XMLHttpRequest.prototype.reply=function(status,data){
                this.status=status;this.responseText=JSON.stringify(data);this.readyState=4;this.onreadystatechange();
            };
        ''')
        for match in re.finditer(r'^    function (\w+)\([^\n]*\) \{.*?^    \}', MAIN, re.M | re.S):
            self.js(match.group() + '\nroot.' + match[1] + '=' + match[1] + ';')

    def test_login_and_fetch(self):
        self.js('''
            root.sessionPassword='secret';root.login();
            assert(root.sessionPassword === '');
            assert(requests[0].body.cislo === '0012');
            requests[0].reply(200,{sid:'session',s5url:'cafeteria-url'});
            assert(walletOps[0].pw === 'secret');
            assert(requests[1].body.sid === 'session' && requests[1].body.s5url === 'cafeteria-url');
            assert(requests[1].method === 'POST' && requests[1].url.endsWith('/objednavky'));
            requests[1].reply(200,{table0:[{datum:'13.10.2026',nazev:'Lunch',pocet:1}]});
            assert(root.meals.length === 1 && root.menuLoaded && !root.apiBusy);
            walletOps[0].cb('wallet failed');
            assert(root.accessToken === 'session' && root.credentialStatus);
        ''')

    def test_logout_during_login_and_wallet_read(self):
        self.js('''
            root.tryAutomaticLogin();root.forgetPasswordAndLogout();
            walletOps[0].cb('', 'late password');
            assert(requests.length === 0 && walletOps[1].op === 'delete');
            root.sessionPassword='secret';root.login();root.forgetPasswordAndLogout();
            requests[0].reply(200,{sid:'late'});
            assert(root.accessToken === '' && requests[0].aborted);
            assert(walletOps.every(function(op){return op.op !== 'save'}));
        ''')

    def test_account_change_and_late_menu(self):
        self.js('''
            root.sessionPassword='secret';root.login();requests[0].reply(200,{sid:'s'});
            plasmoid.configuration.username='other';root.accountChanged();
            requests[1].reply(200,{table0:[{datum:'13.10.2026',nazev:'Old',pocet:1}]});
            assert(root.meals.length === 0 && !root.menuLoaded && root.accessToken === '');
        ''')

    def test_errors_and_retry(self):
        self.js('''
            root.sessionPassword='bad';root.login();requests[0].reply(200,{state:'error',number:13405});
            assert(!root.accessToken && !root.apiBusy && walletOps.length === 0);
            root.sessionPassword='good';root.login();requests[1].reply(200,{sid:'s'});
            requests[2].reply(200,{table0:[]});
            root.fetchMenu();root.fetchMenu();assert(requests.length === 4);
            requests[3].reply(503,{});assert(root.menuLoaded && root.apiStatus.indexOf('previously') !== -1);
            root.fetchMenu();requests[4].reply(200,{state:'error',number:15});
            assert(!root.accessToken && !root.menuLoaded);
        ''')

    def test_session_only_login_and_stale_wallet_callback(self):
        self.js('''
            walletLoader.item=null;
            root.sessionPassword='secret';root.login();requests[0].reply(200,{sid:'s'});
            assert(root.accessToken === 's' && root.credentialStatus && requests.length === 2);
            requests[1].reply(200,{table0:[]});
            root.forgetPasswordAndLogout();
            assert(!root.accessToken && root.credentialStatus);
        ''')

    def test_timeout_discards_late_response(self):
        timer = re.search(r'id: requestTimeout\n.*?onTriggered: \{(.*?)\n        \}', MAIN, re.S)
        self.assertIsNotNone(timer)
        self.js("root.sessionPassword='secret';root.login();")
        self.js(timer[1])
        self.js('''
            requests[0].reply(200,{sid:'too-late'});
            assert(!root.apiBusy && !root.accessToken && !root.sessionPassword);
            assert(requests[0].aborted && walletOps.length === 0);
            root.sessionPassword='retry';root.login();assert(requests.length === 2);
        ''')


class QmlSyntax(unittest.TestCase):
    def test_components_compile(self):
        engine = QQmlEngine()
        for relative in ['ui/main.qml', 'ui/WalletDbus.qml', 'ui/configGeneral.qml', 'config/config.qml']:
            component = QQmlComponent(engine, QUrl.fromLocalFile(str(PACKAGE / 'contents' / relative)))
            while component.isLoading():
                APP.processEvents()
            self.assertFalse(component.isError(), '\n'.join(e.toString() for e in component.errors()))

    def test_layout_with_fake_account_and_meals(self):
        # Instantiate the actual representation offscreen, replacing only the Plasma host
        # and disabling wallet access. Never contact the desktop's real wallet in tests.
        source = MAIN.replace('import org.kde.plasma.plasmoid', '')
        source = source.replace('PlasmoidItem {', '''Item {
            width: 480; height: 420
            property var preferredRepresentation
            property Component fullRepresentation
            property var plasmoid: QtObject {
                property QtObject configuration: QtObject {
                    property string cafeteria: ""
                    property string username: ""
                    property string displayName: "Test diner"
                    property int refreshInterval: 15
                    property bool showUnordered: true
                    property bool logoutRequested: false
                }
            }
            function i18n(s, arg) { return arg === undefined ? s : s.replace("%1", arg) }
            Loader { anchors.fill: parent; sourceComponent: fullRepresentation }
        ''', 1).replace('source: "WalletDbus.qml"', 'source: ""')
        messages = []
        previous = qInstallMessageHandler(lambda kind, context, message: messages.append(message))
        try:
            engine = QQmlEngine()
            component = QQmlComponent(engine)
            component.setData(source.encode(), QUrl.fromLocalFile(str(PACKAGE / 'contents/ui/layout-test.qml')))
            while component.isLoading():
                APP.processEvents()
            self.assertFalse(component.isError(), '\n'.join(e.toString() for e in component.errors()))
            obj = component.create()
            self.assertIsNotNone(obj)
            window = QQuickWindow()
            window.resize(480, 420)
            obj.setParentItem(window.contentItem())
            window.show()
            obj.setProperty('meals', [{'date': '2026-10-13', 'name': 'A long meal name ' * 10,
                'course': 'Lunch', 'ordered': True, 'orderKnown': True, 'count': 1,
                'description': 'Vegetables and potatoes', 'allergens': '1, 7'}])
            from PySide6.QtCore import QDateTime, QDate, QTime
            obj.setProperty('currentDay', QDateTime(QDate(2026, 10, 13), QTime(12, 0)))
            obj.setProperty('menuLoaded', True)
            for width in [480, 320, 800]:
                obj.setProperty('width', width)
                for _ in range(10):
                    APP.processEvents()
            obj.deleteLater()
            window.close()
            APP.processEvents()
            self.assertEqual(messages, [])
        finally:
            qInstallMessageHandler(previous)


class Installation(unittest.TestCase):
    def test_staged_package(self):
        # A mock version command avoids launching plasmashell outside a desktop.
        # All module discovery and package copying still use the real installer.
        with tempfile.TemporaryDirectory(prefix='strava-install-') as temporary:
            temp = Path(temporary)
            command = temp / 'plasmashell'
            command.write_text('#!/bin/sh\necho "plasmashell 6.3.0"\n')
            command.chmod(0o755)
            env = dict(os.environ, PATH=str(temp) + os.pathsep + os.environ['PATH'])
            destination = temp / 'installed'
            result = subprocess.run(['bash', str(PACKAGE.parent / 'install.sh'),
                '--destination', str(destination)], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            for source in PACKAGE.rglob('*'):
                if source.is_file():
                    self.assertEqual(source.read_bytes(), (destination / source.relative_to(PACKAGE)).read_bytes())
            command.write_text('#!/bin/sh\necho "plasmashell 6.2.0"\n')
            result = subprocess.run(['bash', str(PACKAGE.parent / 'install.sh'),
                '--destination', str(temp / 'unsupported')], env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((temp / 'unsupported').exists())


if __name__ == '__main__':
    unittest.main()
