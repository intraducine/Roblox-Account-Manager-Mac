# Troubleshooting

## Roblox closes immediately

1. Update the manager and select **Stop All**.
2. If the manager opens the Roblox updater, let it finish and quit Roblox. Select **Check Roblox Version**, then **Retry Launch**.
3. If Roblox also closes when you open it directly, try updating or reinstalling Roblox before trying the manager again.
4. Open **Tools > Diagnostics and Backup** and select **Run Check**. The results can help identify a problem with Roblox, saved sign-ins, or the manager’s files.

## An account is signed out

Select the account, choose **Check Account** in its profile, and use **Sign In Again** if offered. Sign in as the same account. See [Check a sign-in](./accounts#check-a-sign-in).

## Windows do not move

To see Roblox windows together, open **Window Layout** in the batch or Launch Set and choose **Tile Windows**. **Full Screen Separately** puts each window on its own desktop.

Open **Tools > Launch Defaults** and select **Open Accessibility Settings**. Turn on access for Roblox Account Manager, return to the app, and select **Check Again**. If access was already on, turn it off and on again. Then check that you have assigned a position to each profile.

## A server or friend cannot be joined

The server may be full or closed, or an account may not have access. Refresh the server or player list and try again. To join a friend, select an account shown under **Visible to these accounts**. If you still cannot join, open the friend’s profile with that account and check whether Roblox lets you join there.

## An update cannot be installed

If the updater cannot install a release, download the [latest release](https://github.com/intraducine/Roblox-Account-Manager-Mac/releases/latest), extract it, and replace the manager in Applications. If the manager cannot write to its current location, move it to Applications and try again. Saved accounts stay available.

## Keychain asks for access

The first time **Roblox Account Manager Keychain** opens an existing Keychain item, macOS may ask for access. Select **Always Allow** to keep that approval for future updates. Use the copy in Applications.

## Ask for help

Open **Tools > Send Feedback** and describe the problem. You can include your app version and Mac details to help with troubleshooting. To include a diagnostic report, open **Tools > Diagnostics and Backup**, run a check, and select **Export Redacted Report**.

If you select **Restart Form**, anything you entered in the form is cleared.
