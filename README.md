# Strava Meals for KDE Plasma

A Plasma 6.3+ widget showing your ordered Strava.cz meals for **today**, with
**Today / Tomorrow** buttons and a setting to include meals you haven't ordered.
Tomorrow means the next calendar day, including weekends and holidays.

The native Plasma controls, centered heading, rounded translucent meal cards,
password field, and KWallet workflow follow the neighboring Bakaláři widget.

## Install

Requires KDE Plasma 6.3 or newer, including `org.kde.plasma.workspace.dbus`
(provided by `plasma-workspace` on Debian 13). No compilation, Python service,
pip packages, or separate API server is required.

```bash
cd strava-widget
./install.sh
```

Add **Strava Meals** through Plasma's **Add Widgets** menu. When updating an
existing instance, log out of Plasma and back in to reload the QML.
The installer also accepts `--destination DIRECTORY` for package staging.

1. Open the widget's **Configure → General** page.
2. Enter your cafeteria number exactly as shown on Strava.cz, preserving leading
   zeros, and your username. Optionally set a display name and refresh interval.
3. Apply the settings, then enter your password in the widget and press **Login**.
4. Enable **Show meals I haven't ordered** in settings to see all available choices.

The widget shows order status and quantities, meal descriptions and allergens
when supplied by the cafeteria. It refreshes periodically and updates the dates
after midnight. **Refresh** retries failed requests. Empty days and failed loads
have separate messages; old data retained after a refresh failure is labeled.
This widget displays existing orders; it does not place or cancel orders.

## Passwords

Passwords are saved only after successful login, using the same asynchronous
KWallet D-Bus backend as the reference widget. They are stored in the separate
`Strava Plasma Widget` folder under application ID `cz.saruman.strava`, keyed by
cafeteria and username. Passwords and session tokens are never written into
Plasma configuration or logs. Strava session credentials stay in memory.

If KWallet is locked, it may ask you to unlock it. If unavailable, manual login
still works for the current session and the widget reports that saving failed.
**Forget password and log out** clears the current session and removes the
current account's saved password. Changing accounts clears displayed meals and
invalidates pending responses; previously saved accounts remain in KWallet.
Forget an account before changing its settings if you want its password removed.
Expired server sessions prompt for login again.

## API and compatibility

[The direct adapter](package/contents/code/strava.js) and
[request lifecycle](package/contents/ui/main.qml) use the HTTPS endpoints at
`https://app.strava.cz/api/`, following the protocol documented by
[kralicekgamer/strava.cz_api](https://github.com/kralicekgamer/strava.cz_api)
(reviewed revision `933e8982b8401e2325e62b0994b98ab306488996`).
This is an independent JavaScript implementation, with no third-party proxy.

Login uses `/login`; reading menus uses `/objednavky`. The latter uses POST
because Qt's XMLHttpRequest cannot send a GET body; the referenced API documents
that both methods work. The login response supplies `sid` and `s5url`, which are
forwarded with the cafeteria number for menu requests. TLS validation remains
enabled. Requests time out after 30 seconds.

The parser reads all `tableN` arrays, filters by each meal's actual `datum`
(Czech or ISO format), and treats positive `pocet` values as ordered quantities.
It does not assume a fixed number of meals, specific course names, or that
`table0` is today. Missing order counts are marked unknown, never guessed.

Strava.cz is an unofficial, variable API. This should accommodate cafeterias
using the documented schema, but universal compatibility cannot be guaranteed.
Unsupported response shapes produce an error instead of silently showing an
empty menu. Automated verification is offline; a live cafeteria account has
not been tested.

## Development checks

With Python 3 and PySide6 installed:

```bash
python3 tools/test_widget.py
bash -n install.sh
```

Tests execute the actual adapter and lifecycle functions using Qt's JavaScript
engine, compile all QML components, and construct the representation offscreen
at several widths with fake data. No real credentials, wallet, or network are
used by these tests.
