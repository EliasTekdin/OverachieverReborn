# Overachiever Reborn

Overachiever Reborn is a community rebuild of the original Overachiever tweak for modern rootless and roothide jailbreak environments.

## How it works

The tweak loads into the configured GameKit host and waits for an authenticated `GKLocalPlayer`. It asynchronously loads the game's achievement descriptions and the local player's existing achievements. Each described achievement that is not already complete is represented by a `GKAchievement` with `percentComplete` set to `100`, then submitted through `reportAchievements:withCompletionHandler:`. Authentication changes trigger another attempt, while completed and already-submitted identifiers are skipped to avoid unnecessary duplicate reports.

The legacy preference file is read directly from:

`/var/mobile/Library/Preferences/de.ingmarstein.overachiever.plist`

Set `OverachieverEnabled` to `false` to disable the behavior. If the key is absent, the tweak is enabled by default.

## Settings

The package includes a PreferenceLoader pane named **Overachiever Reborn** in Settings. It has a global switch and dynamically lists installed applications using `LSApplicationWorkspace`. Each application row stores an `ApplicationEnabled.<bundle identifier>` switch in the `com.ilyastekdin.overachieverreborn` preferences domain. The tweak listens for the pane's Darwin notification and re-reads the values without blocking the host thread.

The original `com.apple.GameKit` filter is retained. The filter also recognises `GKLocalPlayer` so GameKit clients can be selected for injection; an application's switch is evaluated from the host application's bundle identifier when the tweak is loaded there.

## Requirements

- A jailbroken iOS device with rootless or roothide injection support.
- MobileSubstrate-compatible tweak injection.
- PreferenceLoader for the Settings pane.
- GameKit and an authenticated Game Center account.
- A GameKit host selected by the package filter.

The package is built with Objective-C and `MSHookMessageEx`, with a deployment target of iOS 16.0 and slices for rootless (`arm64`, `arm64e`) and roothide (`arm64e`).

## Limitations

Game Center behavior is controlled by iOS, the game, and the account. This project does not guarantee that reporting will succeed for every game or account, and it does not claim to bypass server-side restrictions. Device behavior still needs to be verified on the target setup before relying on it.

## License

The source is distributed under the MIT license. The project is an independent community rebuild and is not affiliated with Apple or the original author.
