# TODO
List of various incomplete tasks and ideas that might get implemented eventually

## Quests
Currently not fully functional
- current quest related files in natives/.. are out of date for the latest version, need to be remade following the instructions in this doc
- custom talk events (using app.AISituationTaskStateTalkToPlayer): UI freezes up (can't pause) and no talk event happens, NPC returns to his routine
    - TalkTo is fine, returns Continue (with my hook, that is, cause of those pesky enums)
    - isEventPlayable is true with no custom changes
    - but then something dies somewhere
    - TalkTo.updateImpl() is not called again
    - the task keeps shitting itself and making the NPC psychotic even when he's just waiting there, so that's probably what to look into
- Figuring out custom dialogue voices
- Probably a ton of other things as well

## Quest dev tools
Tools that would probably be helpful with testing and developing quests
- warp location favorites list

## Editor enhancements
- AIKeyLocation
    - toggle "only nearby (distance < 200) locations" or alternatively a "sort by distance" option
        - maybe an option to have the enum automatically sort by distance globally, though with the amount of locations, might be slow
    - expandable AIKeyLocation editor (for creating new locations, once we have that working)
- replace certain enums with simpler UIs like a checkbox?
    - *.LogicalOperatorBool
- app.QuestProcessor
    - attach to game/detach (add or remove from the quest processor transform)
    - see all processors that depend on this one (in a single flat list)
    - app.quest.action.TaskSetting: _ResourceData - pick from a list of the owned quest AI situation's role list
- Quest dev tools
    - check the currently active quest, add suggestion buttons for things you might need (teleport to X, give items, mark completed, fully reset quest state)
- app.ItemDeliverySegmentNode
    - add a deliver entity picker similar to quest nodes in NextNodesCandidates (and make that one more generic)
- quest tree data: display with an actual tree editor window
- app.quest.action.QuestRewardData.Data
    - add linked reference to the actual app.QuestRewardData object (and offer a "Create new" button)
