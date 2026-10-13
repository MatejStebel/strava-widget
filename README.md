# strava-widget

A KDE Plasma widget that displays your ordered meals from **Strava.cz**. See
what you have ordered for today, switch to tomorrow, or show the full menu
including meals you haven't ordered.

## Features

- **Today and tomorrow:** switch between the two days with a single click.
- **Ordered meals by default:** optionally include unordered meals in settings.
- **Flexible menus:** supports different meal types, including second dinner,
  when provided by your cafeteria.
- **Meal details:** displays order quantities, descriptions, and allergens when available.
- **Automatic refresh:** configurable refresh interval, manual refresh, and date updates after midnight.
- **KWallet integration:** securely save your password and sign in automatically.
- **Native Plasma interface:** follows your desktop theme, with styling and
  password handling based on [bakalari-widget](https://github.com/MatejStebel/bakalari-widget).

The widget displays existing orders. It does not place or cancel orders.
**Tomorrow** always means the next calendar day, including weekends and holidays.

## Requirements

- KDE Plasma **6.3 or newer**.
- The Plasma QML module `org.kde.plasma.workspace.dbus`.
- A Strava.cz account and your cafeteria number.
- KWallet for saving passwords; manual login also works without it.

No compilation, Python service, or separate API server is needed to run the widget.

## Installation

Download or clone this repository, then open a terminal in its root directory
and run:

```bash
./install.sh
```

Run the installer as your normal user from your KDE desktop session. It checks
runtime requirements and installs the widget to:

```text
~/.local/share/plasma/plasmoids/cz.saruman.strava
```

If `XDG_DATA_HOME` is set, the installer uses that location instead of
`~/.local/share`.

After installation, open Plasma's **Add Widgets** menu and add **Strava Meals**
to your desktop or panel.

### Updating

Download the latest source and run `./install.sh` again. Then log out of Plasma
and back in to load the updated widget. Reinstalling preserves your account
settings and saved password.

## Setup

1. Open the widget's **Configure → General** page.
2. Enter your **cafeteria number** and **Strava.cz username**. Keep any leading
   zeros in the cafeteria number, such as `0012`.
3. Optionally enter a display name and change the refresh interval.
4. Apply the settings.
5. Enter your password in the widget and press **Login**. If prompted, allow
   KWallet access to save it for future logins.

Use **Today** or **Tomorrow** to choose the day and **Refresh** to reload meals.

### Settings

| Setting | Description | Default |
| --- | --- | --- |
| Cafeteria number | Your cafeteria's identifier on Strava.cz | Not set |
| Login-username | Your Strava.cz username | Not set |
| Display name | Optional name shown in the widget heading | Not set |
| Show meals I haven't ordered | Include unordered meals and meals with unknown order status | Off |
| Refresh interval | Minutes between automatic updates | 15 |
| Forget password and log out | Remove the current account's saved password and clear its session | — |

## Password storage

Passwords are saved to **KWallet** only after a successful login. The widget uses
its own `Strava Plasma Widget` wallet folder and the application ID
`cz.saruman.strava`. Saved entries are separated by cafeteria number and username.

Passwords and session tokens are not written to Plasma configuration or logs.
Session tokens remain in memory, and requests go directly to Strava.cz over HTTPS.

If KWallet is unavailable or access is denied, you can still log in for the
current session. The widget will report that the password could not be saved.

To remove a saved password, use **Forget password and log out** in settings.
Changing the cafeteria or username clears the current session but keeps the
previous account's password in KWallet. To remove that password, log out with
**Forget password and log out** before changing accounts.

## API and compatibility

The widget includes an independent JavaScript client based on the protocol
published by [kralicekgamer/strava.cz_api](https://github.com/kralicekgamer/strava.cz_api).
It connects directly to `https://app.strava.cz/api/`; it does not install the
Python library or send credentials through a third-party proxy.

The implementation uses `/login` for authentication and `/objednavky` for reading
menus. It reads all returned menu tables, selects meals by their dates, and uses
the reported order quantities to determine which meals are ordered. It does not
assume fixed meal names or a fixed number of courses.

This integration uses an **unofficial API**. Cafeteria responses can vary, so
compatibility with every cafeteria cannot be guaranteed. Missing order statuses
are marked as unknown, and unsupported menu responses produce an error message.
Live cafeteria account verification has not yet been performed; the automated
tests use simulated responses.

## Troubleshooting

| Problem | What to check |
| --- | --- |
| Widget does not appear after installation | Confirm Plasma 6.3 or newer is installed, then log out and back in. Look for **Strava Meals** in Add Widgets. |
| Installer reports a missing D-Bus QML module | Install your distribution's Plasma workspace runtime containing `org.kde.plasma.workspace.dbus`. |
| Installer cannot check the Plasma version | Run it from a terminal in your KDE desktop session. |
| Login fails | Check the cafeteria number, including leading zeros, username, and password. |
| Password cannot be saved | Check that KWallet is available and allow access when prompted. Session-only login remains available. |
| Session expired | Enter your password to sign in again. |
| No ordered meals are shown | Check the selected day or enable **Show meals I haven't ordered** to view the available menu. |
| Refresh fails | Press **Refresh** to retry. Previously loaded meals remain visible with a message indicating that the refresh failed. |
| Unsupported menu response | Your cafeteria may return a different API format. Report the problem with the error message and Plasma version, without including credentials or session tokens. |

## Development

The widget is written in QML and JavaScript.

| File | Purpose |
| --- | --- |
| [main.qml](package/contents/ui/main.qml) | Widget interface, requests, and login lifecycle |
| [strava.js](package/contents/code/strava.js) | API payloads, menu parsing, and date filtering |
| [WalletDbus.qml](package/contents/ui/WalletDbus.qml) | KWallet password storage |
| [configGeneral.qml](package/contents/ui/configGeneral.qml) | Settings interface |
| [main.xml](package/contents/config/main.xml) | Configuration entries and defaults |
| [test_widget.py](tools/test_widget.py) | Offline tests |

### Running checks

Install Python 3 and PySide6 alongside the Plasma runtime, then run:

```bash
python3 tools/test_widget.py
bash -n install.sh
```

The tests cover menu parsing, date selection, login and logout, stale responses,
request timeouts, QML compilation, and the layout at different widths. They also
check package installation using a simulated Plasma version command. Tests do
not use real credentials, contact Strava.cz, or access your wallet.

To stage the package in a custom directory:

```bash
./install.sh --destination /absolute/path/to/staging-directory
```

The installer still checks Plasma runtime requirements when staging.

## Credits

- [kralicekgamer/strava.cz_api](https://github.com/kralicekgamer/strava.cz_api)
  for documenting the Strava.cz API protocol. The implementation was based on
  revision `933e8982b8401e2325e62b0994b98ab306488996`.
- [bakalari-widget](https://github.com/MatejStebel/bakalari-widget)
  for the Plasma interface and KWallet integration used as a reference.
