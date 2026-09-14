# Calibre beta test matrix

Ask each tester to fill one row. Do not request Plugin Index inclusion until
every critical behavior passes on all three operating systems and at least one
Calibre 7 or 8 installation.

| OS | Calibre | Install | Whole library | Search | Virtual Library | Re-reshuffle pool | Restore | Result |
|---|---:|---|---|---|---|---|---|---|
| macOS | 9.2.1 | Pass | Pending GUI check | Pending | Pending | Pending | Pending | In progress |
| macOS | 8.x |  |  |  |  |  |  |  |
| macOS | 7.x |  |  |  |  |  |  |  |
| Windows | 9.x |  |  |  |  |  |  |  |
| Windows | 8.x or 7.x |  |  |  |  |  |  |  |
| Linux | 9.x |  |  |  |  |  |  |  |
| Linux | 8.x or 7.x |  |  |  |  |  |  |  |

## iPhone Content Server checks

| Scenario | Expected result | Status |
|---|---|---|
| Bonjour discovery | Server appears without entering an IP | Implemented; device check needed |
| Manual local address | Test Connection succeeds | Live server response verified |
| Wrong address | Clear connection failure | Type-checked; device check needed |
| Wrong credentials | Calibre rejection is explained | Type-checked; device check needed |
| Multiple libraries | User can select a library | Implemented; multi-library server needed |
| URL prefix | Discovered/manual prefix is preserved | Implemented; live check needed |
| Relaunch with authentication | Keychain password permits quiet sync | Implemented; device check needed |
| Server offline | Existing shelf remains available | Existing behavior; device check needed |

