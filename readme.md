# DD2 Content editor
Real-time ingame data editor for DD2 (and possibly other RE engine games). Can theoretically edit any game data with the right addon support, while also providing a common reusable UI framework.

The default launch only contains the content database without editor support. Users who wish to actually edit things can enable it through the button in the ingame REF UI, in the content database section. It is disabled by default to speed up gameplay and load times, though it may not make a noticeable difference.

The mod is basically an "Any game data" JSON-serialization based editor. As long as someone implements reading and inserting data into the game at runtime, any data can be edited instead of going through .user files. This makes any changes mostly version-agnostic and reduces mod conflicts when many things share the same file, also much easier to review changes compared to raw RSZ files. The mod automatically prepares a UI for displaying any game class via IMGUI similar to alphaZomega's EMV Engine console, except simplified for only editable data while also allowing customization of the data presentation, extending it with custom features specific to an object type. I've made adding new editors and addons as straightforward as I could so anyone else is welcome to contribute.

## Requirements
- REFramework: hard requirement. In case of issues, try installing the latest nightly version.
- EMV-Engine/Console: not required, but can help with discovering things that may not be exposed by the mod yet

## Why?
Due to DD2 storing every single quest in a single catalog object, we can't really use any existing desktop tools for editing userfiles because conflicts in the quest catalog are pretty much unresolvable. So we need some sort of "patching" support. This mod does that, ingame (meaning the actual files are left clean in the game folder) and in realtime (meaning that we can dynamically alter them while the game is running, like changing NPC behaviors etc).

## DD2 editors current status
- ✔️Fully functional: Create and edit events (escorts, monster culling requests, affinity escorts) [Info](https://github.com/kagenocookie/dd2-content-editor/wiki/Events)
- ✔️Fully functional: Create and edit items (custom consumables, armor, weapons) [Info](https://github.com/kagenocookie/dd2-content-editor/wiki/Items)
- ✔️Fully functional: Shops editor
- PoC: Human parameters, job parameters
- On hold, partial support: Quest editor (see [Info](https://github.com/kagenocookie/dd2-content-editor/wiki/Quests))
- On hold, partial support: Dialogue editor

## Gameplay setup
A proper release will be made once I feel the mod is stable and meaningful enough. For now:
- clone the repository
- run build.ps1 (note that the mod structure is still subject to change)
- drop the content_editor_full.zip as a mod in Fluffy mod manager
- activate the individual mods you want to enable
- place some bundle json files into the GAMEDIR/reframework/data/usercontent/bundles folder

When first launching (and whenever the game version or content addons change), the game will freeze up for a bit in order to build up a nice friendly cache of all the object types that are used by the mod so don't worry if the game becomes unresponsive the first time or after updates. Last I checked, this takes about 25s on my machine. Subsequent launches should be fast since it's just fetching the cached data.

## Current editor features
- All custom data is stored in bundle json files that may contain any number of different entity types
- Full data JSON serialization support - as long as a content addon knows where to store relevant data
- Can be easily extended via lua addons to support additional data
- General: Support for custom lua scripts to be executed on supported objects
- General: Modify/override any translation strings (message guids)

## Mod development setup
- clone the repository
- symlink the folders and files in reframework/autorun into your game's reframework/autorun folder (or copy the manually when changing, or have it stored directly in the gamedir (please don't))
- copy the core usercontent files from the mod into your game's data/usercontent/ directory
- ideally, install the LuaLS extension by sumneko
- for proper game type references, setup the `Lua.workspace.library` workspace setting if using vscode, or whatever equivalent your IDE of choice supports, with the output of e.g. https://github.com/kagenocookie/REFDumpFormatter

## Is this safe to use?
Probably. Depends on the mods running. Custom events are fine, custom items may not be. I'd still recommend making a save backup because there might be issues I just haven't encountered yet.

## Credits
- praydog for creating the amazing REFramework
- alphaZomega for his EMV engine tools which were invaluable in researching how the game data works and getting custom things to work properly
