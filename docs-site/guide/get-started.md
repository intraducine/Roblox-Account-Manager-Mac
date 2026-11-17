# Get started

Save your Roblox accounts and open them together on your Mac. Each account gets its own copy of Roblox and its own data folder.

## Before you begin

You need macOS 13 or later and Roblox installed at `/Applications/Roblox.app`. The app works on both Apple silicon and Intel Macs.

## Install the manager

1. Download the ZIP from the [latest release](https://github.com/intraducine/Roblox-Account-Manager-Mac/releases/latest).
2. Extract the ZIP and move **Roblox Account Manager.app** to Applications.
3. Open the manager.

macOS may block the first launch because the app is not notarized by Apple. To open it, go to **System Settings > Privacy & Security** and select **Open Anyway**.

If macOS says the app is damaged, download it again from the [latest release](https://github.com/intraducine/Roblox-Account-Manager-Mac/releases/latest) and replace your copy. If macOS still reports damage or warns that the app is harmful, do not open it. Report the warning on the [project’s GitHub page](https://github.com/intraducine/Roblox-Account-Manager-Mac/issues).

## Add an account

1. Select **Add Account**.
2. Use **Sign In on Roblox** and sign in on the Roblox page.
3. When the window says **Ready to save**, select **Save This Account**.
4. Repeat for each account you want to use.

The manager stores the Roblox sign-in in macOS Keychain. It does not save your password. See [Accounts and groups](./accounts) for sign-in recovery and profile details.

## Launch a game

1. Select an account in the list, or select the checkboxes for multiple accounts.
2. Select **Choose Game**, paste a Roblox game link, and select **Find Game**. Select **Choose** for the result.
3. Leave the server set to **Let Roblox choose**, or [choose a server](./games-and-servers).
4. Select **Launch Game** for one account. For several accounts, select the launch button. It shows the number of selected accounts, such as **Launch 2 Accounts**.

<figure class="guide-image">
  <a href="../images/launch-accounts.png" target="_blank" rel="noopener" aria-label="Open the account selection screenshot at full size">
    <img src="/images/launch-accounts.png" alt="Three example accounts are checked in the account list. The launch panel shows the selected game and a Launch 3 Accounts button.">
  </a>
  <figcaption>Select the checkboxes beside the accounts you want to launch together. Select the image to view it full size.</figcaption>
</figure>

To open Roblox without joining a game, select **Open Roblox App** or **Open Roblox Apps**. Use **Stop All** to close managed clients.

## Update the manager

1. Choose **Roblox Account Manager > Check for Updates**.
2. If an update is available, select **Download Update**.
3. When it is ready, select **Install and Restart**, then confirm.

The manager closes and reopens to finish the update. Your accounts, notes, groups, and games stay in place. If the update fails, see [Troubleshooting](./troubleshooting#an-update-cannot-be-installed).
