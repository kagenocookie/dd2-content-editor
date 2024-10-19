The way Capcom coded quests is a bit convoluted, so editing without proper tooling is hell. The goal of this mod is to simplify data editing as much as possible.

There are 2 types of quests, one is normal quests, and the other is "sudden quests", or events as I'm calling them for an easier distinction.

## Events
Events are limited to the 3 types of "random" quests you can find in the wilderness, which is either EnemyBattle (monster culling, where some NPC is being assaulted), NpcGuard (escorting random NPCs) and NpcTravel (affinity escorts for the important NPCs, where they stake out your house when you get home). Events are feature complete for the mod, including saving and loading changes to basegame events or creating completely new ones.

Each event consists of a "Data" object and one or more "contexts". The base data defines the start and end position and the starting conditions. The context defines any spawned enemies, is used to vary the available NPCs and define their talk message, as well as defines the type of the event (I'm not sure why type is defined on the context, I don't think there's ever different context types for one data nor would it make sense, Capcom pls).

Example of things that could be done with events:
- add new escort missions for arbitrary NPCs
- add specific enemy spawns to specific locations
- spawn some extra enemies while a certain quest is active
- You can combine any of these in one event, so an escort quest with predefined enemy spawns is possible

The game evaluates every single active event distributed over several frames to check whether it should trigger or not. The base game has very strict limits on the timeframe when these events can occur to give the illusion that they're random, but really if you disable the TimeOfDay conditions they mostly just happen all the time, though each event context has a baked in IntervalTime setting to limit it to once per 30 days (defined on the event context, can be changed).

One thing to keep in mind, only one event can be active at a time. This is a hard limit by how the game code is setup, no easy way to work around that.

### Event enemy spawning logic
- each enemy spawn request set has a list of predefined enemies it can spawn (character id + min/max count + chance), and a total count.
- each enemy spawn row has a group property (A/B/C/D/...). Whenever a spawn is requested, the game picks one group (or does it follow some sort of algorithm?) and evaluates all the rows for that group. Spawn groups can have conditions in the InitSetDatas object.
    - SetCount: determines how many enemies should spawn for this group
    - TimeZoneEnum: likely to limit spawns to a specific timezone (dawn, dusk, ...), though events seem to always allow all timezones
    - SystemFlag: not sure what this does exactly
    - Random: seems to be always 100, I assume it could be the "max int" for the random dice rolls later
- then, it picks random rows to spawn from the chosen group
    - there's 2 ways this could be done, I'm not sure which one the game is using:
        - does a weighted RNG where it adds up all the chances and then picks a number from 0 to sum
        - or it goes through the enemy rows in sequence, doing a dice roll each time to see if it should trigger that spawn
    - each row has a min/max number of enemies it can spawn, where X = min spawned, and Y = max spawned count
    - adds the chosen enemies to the generated set
    - repeat until we've either exhausted all enemy set rows or reached the SetCount limit
- spawn the generated set of enemies

## Quests
These are the important quests. Basically, you have the basic quest data, scattered across several objects (NPC schedule overrides, item delivery, variables, "after stories", various conditions and branches) and grouped together by a quest ID. For example, the "Monster culling" quest you get in Vernworth is ID 10090. Some of the quests aren't actually quests in the sense that they get noted down in the ingame quest journal, but only used as a sort of "platform" to add in specific behaviours, like the NPCs hinting you about the medusa, or newt liquor sellers.

I've grouped up by quest ID most of the important data into the Quests tab in the editor so stuff is easier to look up.

One thing to keep in mind, most of the quest logic is based on "what's the current state" type of conditions instead of "when this happens, do this", which can make it a bit hard to reason about when what happens and making sure all situations are covered. I feel like Capcom dealt with that by just making more quest processors for every single thing which just makes it all even more convoluted.

### NPC overrides
NPC overrides let you override NPC behaviour - their schedule, whether they spawn or not, costume/appearance (for NPC specific variants like Sven's outfit in the Ornate box quest), npc job, combat job (including making them equip a custom weapon, making them able to fight), crime group, morgue (Vernworth or Battahl), or some coffin setting (not sure what this does exactly).

I think these also deactivate when the quest is inactive (completed or failed). Overrides can be conditional based on either quest variables or a time of day.

TODO I'm not sure yet how they get prioritized if there's several active ones for an NPC

### Delivery data
Quests that have you deliver items to an NPC always have one or more entries in the Delivers section. This can be either money, specific items, or a list of items.

They are linked to an NPC from talk event nodes (app.ItemDeliverySegmentNode) through the Key field.

### After stories
These seem to be post-quest-completion (or post-"some part of the quest") overrides, notably they can also change the conversation an NPC has when talked to. An afterstory setting can also define any of the same data as the "NPC schedule" section. These afterstory overrides can be either limited to a time period or permanent ("permanent" meaning that the end date is set to 999 days. Does the game stop counting time at 999 or does the override just disable and they come back? Who knows.).

After story entries can only be put conditional on variables or on the quest elapsed time, and not directly on processors or arbitrary conditions.

### Variables
These are one of the primary things used for conditions within quests (for NPC overrides, afterstories, ...). The game doesn't ship with actual names for these, just some hashes, so we can only reverse engineer and manually label these. The mod provides a way to do so via a `QuestVariables.json` file, I've already added names to some of them that were simple enough to figure out and give a reasonable name. These names aren't unique, so you can have multiple quests use the same NameHash for its variable, but still one NameHash == one name. Most objects that reference variables also include a field for the quest ID. Quest processors can also set the quest ID to -1 / `<unset>`, which makes it point to the quest its defined in, this is not the case with NPC overrides (and probably most objects that use variables) which need to have the quest set.

Variables are mostly used to make conditions for after stories, NPC overrides.

Keep in mind though, most basegame variables are just a proxy for a quest processor's result.

### Quest processors
The most important part of quests is the quest processors. These tend to contain most of the real logic related to quests, but they're stored in scene files instead of user files, so they're a bit harder to access (natives/stm/appdata/quest/*, in the Resident.scn files). They also only get instantiated ingame while the related quest is activated (via Quest tree node conditions). The mod provides a feature to force all processor folders to activate to get an overview of them, though I don't recommend playing while they're all opened up like that because it might mess with the quest logic.

Each QuestProcessor can have some preconditions in `PrevProcCondition`, which is prerequisite processors that need to be done/OK (different from -1) before the next one can execute.

Every quest that has quest processors has at least a NotifyStartQuest and a NotifyEndQuest processor. These are basically used as the "quest started" trigger for all other processors. Beside that, there's usually a bunch of other quest processor types, I won't go into too much detail here because there's a lot, so maybe just check the editor and fiddle with it a bit.

### Talk events
Many quest conditions reference "talk events" which is basically NPC dialogues. Similar to quests, each talk event can have its own result number, usually -1, 0, 1. A lot of these talk node names are in japanese so if you can't read that, it should be possible to figure out what they do from the type and other fields, especially those that display with subtitles ingame.

### Time detection keys
TODO figure out what they do

### Cast NPCs
I'm not sure what the point of these is. We can add NPC overrides regardless of their presense in this list. Might be something related to dialogues or cutscenes.

### AI situation
The game will crash if an AI situation is not defined for a quest that tries to override NPC behavior. A non-null AI situation solves that, even if none of its fields contain any extra data. The AI situation entity also contains a list of some NPC roles available to the quest and might be required when editing some quest process action types.

### Tree data
The game uses an array of "quest tree nodes" to determine whether a quest should be activated or not.

tl;dr: A quest will never activate unless it has a defined quest tree node.

These tree nodes are basically just a set of [Quest ID] + [Preqrequisite quest results]. There's also a relation IDs field, which points from the prerequisite to the quests it can open, so basically every condition goes two ways, though I'm not sure how or if relationIDs is used. On launch, these objects get converted into runtime-optimized `app.QuestManager.QuestTree.Node` class instances from QuestManager:registerQuestCatalog. These instances then also handle actually updating the runtime quest entity.

## Creating a new custom quest
Theoretically possible, though not yet fully supported. One caveat for creating new quests is that we need to separately modify the quest scene files because they can't be edited directly through REFramework. This means any custom quest mods would need a bit of manual resolution, the long term plan is to provide a tool to merge these additions, but for now it's manual. A custom quest example for a "debug" quest with id 8000 is included with the mod, feel free to abuse it as much as you like.

Some gameplay related things can be done with quests that can be used outside of actual actionable quests. This is kind of a hack that Capcom devs themselves also used, for e.g. the NPCs that warn you of the medusa and some other things. There doesn't need to be a quest log entry to have quest override features running. Example of things that might be useful:
- change an NPC into a follower
- make an NPC follow another NPC
- change NPC combat job (e.g. turn a civilian into warrior or change one job to another)
  - I'm not seeing a way to change their equipment through quests though, so I guess that part might need some custom lua logic; or maybe we just need to give them the items before the quest override triggers, an additional `app.quest.action.ItemControl` quest processor might be enough. Need to test this some more
- change NPC schedules, despawn or force them to be spawnable again (like Wilhelmina after that last quest)
- change the weather type
- block ferrystones (untested, this one also contains some ID list that I'm not sure what it represents - QuestFerrystoneControlParam; possibly blocks portcrystals and not ferrystones)

- create the minimum quest .scn files in `AppData/Quest/`
    - most easily just make a copy of the AppData/Quest/qu01/qu010020/qu010020.scn and AppData/Quest/qu01/qu010020/Resident.scn files into our own quest's folder and rename
    - make sure that you name the quest scene file like `qu######.scn`, I think the qu prefix is required.
- changes to make in the qu######.scn file:
    - app.QuestController: set quest id to your own one
    - change all GameObject GUIDs to something unique
    - maybe just replace the first 8 characters of the GUID with your own quest id
    - note down the GUID you gave to the app.QuestProcessor object, as we'll need it again
- edit the resident.scn file
    - change all GameObject GUIDs to something unique
    - set the RefQuestController field GUID to the app.QuestProcessor's one you noted down earlier
- NOTE: editing can be done most easily with RszTool;
    - as of writing this, you need one of the forks to make DD2 scene files work properly (https://github.com/lingsamuel/RszTool)
    - though I've also had issues getting the game to load after editing with RszTool after the last update, 010 editor with the proper rsz template may be more reliable
- open the AppSystem/scene/quest.scn.20
    - add a new folder for your own quest
    - this step needs manual merging for compatibility between multiple mods
    - I may eventually add some sort of automated editing of these but for now it's manual
- place the scn files in their normal folder in natives/stm/appdata/quest/..., no need for PAK, loose files work just fine
- now we can go ingame, and while still in the main menu, add a new quest with the ID you gave it in the scn file
- in theory you should now have a functioning "quest", albeit with no logic to it just yet and no quest logs or anything

## How do I ...

**Make a talk event change on the second time you talk to an NPC?**
- Add a condition to the root node's first-time node candidate as TalkEventResultCondition == -1 for the talk event in question (meaning the conversation has never finished before).
- _See Prey for the Pack talk event te5020250_190 for an example._

**Make a time sensitive quest?**
- Mark _IsTimeLimited_ on the corresponding quest log entries (this is purely visual)
- To make the quest actually time limited, add a Trigger type processor with a CheckElapsedTimeParam condition
- Add extra processors, variables, talk events as needed and make anything time sensitive end when the elapsed time processor completes
- _20250 Prey for the Pack_ is a good reference for this

**Use a custom lua script for a quest condition?**
- set the condition to type CheckLocalArea (don't mind the type name, you can script whatever you want, it's just one of the least used conditions in the basegame which makes it good for minimizing the performance impact of hooking into its evaluation check)
- press the "Use custom script" button
- create a script and write your code in

## Debugging notes
Not every type of task is applicable for every character.
Quest task type StateTaskGuide: only NPCs supported, not pawns (the game expects the target to have an NPCCharacterData - app.NPCManager.getNPCCharacterData())

