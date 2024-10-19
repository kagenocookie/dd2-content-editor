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
- Fully functional: Create and edit events (escorts, monster culling requests, affinity escorts)
- WIP: Can partially edit basegame quests (conditions, triggers, dialogues, ...)
- WIP: Can create custom quests, though still missing many features (see [quests](quests-guide.md))
- WIP: Armor styles editor
- WIP: Item data editor
- WIP: Dialogue editor
- PoC: Human params
- PoC: Shops

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

### Code snippets
Extend the content database with a new entity type
```lua
local udb = require('content_editor.database')
udb.register_entity_type('event_context', {
    import = function (data, instance)
        --- @cast instance EventContext|nil
        local instance = instance or {}
        instance.data = import_handlers.import('app.SuddenQuestSelectData', data.data, instance.data)
        sdk.get_managed_singleton('app.SomeManager').MyDataList[instance.id] = instance.data
        return instance
    end,
    export = function (entity)
      return {
        data = import_handlers.export(entity.data, 'app.SuddenQuestSelectData')
      }
    end,
    delete = delete_event_context,
    root_types = {'app.SuddenQuestSelectData'},
    insert_id_range = {100000, 999000},
})
```

Add a new editor tab:
```lua
local udb = require('content_editor.database')
local editor = require('content_editor.editor')
local ui = require('content_editor.ui') -- this import provides some common editor features to simplify editor code

editor.define_window('my_custom_editor', 'Nice title', function (state)
  -- write any imgui code you want here
  imgui.text('Hello, world!')

  -- easy-to-use entity picker
  local selectedEntity = ui.editor.entity_picker('quest', state)

  -- simple way to offer customizable presets when creating new entities
  if editor.active_bundle then
    local create, preset = ui.editor.create_button_with_preset(state, 'event_context', 'new_ctx', 'New event')
    if create then
      -- create a new entity with some initial values, can be taken from a preset or defined manually
      local newEntity = udb.insert_new_entity('quest', editor.active_bundle, preset or {})
    end
  end

end)
editor.add_tab('my_custom_editor')
```

Create a custom escort quest:
```lua
local my_fixed_quest_id = 1234 -- use the same id when adding the quest between runs in order to guarantee that they'll persist properly between reloads
local sqEntity = quests.db.sudden_quests.create({
    key = my_fixed_quest_id,
    label = 'NPC Followers escort',
    startLocation = 2220, -- qu012020_084, right outside vernworth NE gate
    endLocation = 86, -- Gimmick_Camp_032, hill near the vernworth east-west river (why do the rivers not even have names, Capcom?)
    npcIDs = {"ch310002"},
    type = 2, -- NpcGuard
})
```

## Credits
- praydog for creating the amazing REFramework
- alphaZomega for his EMV engine tools which were invaluable in researching how the game data works and getting custom things to work properly
