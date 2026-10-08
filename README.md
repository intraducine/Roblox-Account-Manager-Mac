# Roblox Account Manager for Mac

![macOS](https://img.shields.io/badge/macOS-supported-black?style=for-the-badge&logo=apple)
![Release](https://img.shields.io/github/v/release/intraducine/Roblox-Account-Manager-Mac?style=for-the-badge)
![Downloads](https://img.shields.io/github/downloads/intraducine/Roblox-Account-Manager-Mac/total?style=for-the-badge)
![Stars](https://img.shields.io/github/stars/intraducine/Roblox-Account-Manager-Mac?style=for-the-badge)
![License](https://img.shields.io/github/license/intraducine/Roblox-Account-Manager-Mac?style=for-the-badge)

Run several Roblox accounts on one Mac, with a separate Roblox app copy and data folder for each account. Sign-ins and profile notes stay in macOS Keychain.

**[Download the latest release](https://github.com/intraducine/Roblox-Account-Manager-Mac/releases/latest)** · [User guide](docs/USER_GUIDE.md) · [Build from source](docs/DEVELOPMENT.md)

This is an independent project. Roblox Corporation does not make or approve it. Use only accounts that you own or have permission to use.

## Install

You need **macOS 13 or newer** and Roblox at `/Applications/Roblox.app`. Release builds support Apple silicon and Intel Macs.

1. Download the release ZIP and its `.sha256` file. Check the download as described in the [install guide](docs/USER_GUIDE.md#install-and-update).
2. Extract the ZIP and move **Roblox Account Manager.app** to Applications.
3. Open the manager. If macOS blocks the first launch, follow the [security warning steps](docs/USER_GUIDE.md#install-and-update). Keep macOS security checks on.

For later updates, choose **Roblox Account Manager > Check for Updates**. If an older manager rejects the update, follow the [manual update steps](docs/USER_GUIDE.md#install-and-update).

## Start playing

1. Select **Add Account**, sign in on the Roblox page, then select **Save This Account**.
2. Repeat for your other accounts. Use the checkboxes to select accounts to launch together.
3. Select **Choose Game** and paste a Roblox game link. Keep **Let Roblox choose** or choose another server.
4. Select **Launch Game** for one account or **Launch Accounts** for several.

To open Roblox without joining a game, use **Open Roblox App** or **Open Roblox Apps**. Use **Stop All** to close the managed clients.

## Other tools

- **Groups and Launch Sets:** organize accounts and save common launch choices.
- **Launch Defaults:** set graphics, sound, and window positions across displays.
- **Find Players:** join visible friends through existing account friendships.
- **Account website windows:** browse Roblox as one saved account.
- **Diagnostics and Backup:** check setup and back up account details. Normal backups exclude sign-ins, profile notes, and private-server links.

See the [user guide](docs/USER_GUIDE.md) for these tools and their limits.

## If Roblox closes at once

If Roblox needs an update and is not running, the manager opens the normal Roblox app to let it update. Let it finish, quit Roblox, then retry one account. If Roblox also closes outside the manager, see [launch troubleshooting](docs/USER_GUIDE.md#roblox-closes-at-once).

Normal launches keep Roblox copies unchanged. The optional modified fallback can cause account restrictions. The manager does not bypass Roblox access rules or automate gameplay.

## License

GNU GPL version 3. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
