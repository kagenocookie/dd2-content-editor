if type(_quest_DB) == 'nil' then _quest_DB = {} end
if _quest_DB.utils then return _quest_DB.utils end

local core = require('content_editor.core')
local gamedb = require('editors.quests.gamedb')
local config = require('editors.quests.quests_config')

local getNearPlayerPosition = sdk.find_type_definition('app.QuestUtil'):get_method('getNearPlayerPosition')
local function get_near_player_safe_npc_position(distance, characterId)
    return getNearPlayerPosition:call(nil, distance, characterId)
end

local AIAreaUtil = sdk.find_type_definition('app.AIAreaUtil')
local getPlayerLocalArea = AIAreaUtil:get_method('getPlayerLocalArea')
local getPlayerArea = AIAreaUtil:get_method('getPlayerArea')

local AIAreaManager = sdk.get_managed_singleton("app.AIAreaManager")

local function get_random_near_player_AIKeyLocation()
    local localArea = getPlayerLocalArea:call(nil)
    local area = getPlayerArea:call(nil)
    print('area', area, localArea)
    local randomNode = AIAreaManager:getRandomNodeInArea(area, localArea, localArea == -1)
    if not randomNode then print('No random node oi') end
    if randomNode and not randomNode.KeyLocation then
        print('node has no AIKeyLocation', randomNode)
    end
    return randomNode and randomNode.KeyLocation
end

--#region Optional hooks
local sq_overrides = config.data.devtools.events.overrides
local sq_ignore_time_hooked = false
local function hook_suddenquest_ignore_timeofday()
    if not sq_ignore_time_hooked and sq_overrides.ignore_time then
        sq_ignore_time_hooked = true
        sdk.hook(
            sdk.find_type_definition('app.quest.condition.SuddenQuestCondition.CheckTimeOfDay'):get_method('onEvaluate'),
            function (args) if sq_overrides.ignore_time then return sdk.PreHookResult.SKIP_ORIGINAL end end,
            function (retval) if sq_overrides.ignore_time then return sdk.to_ptr(true) else return retval end end
        )
    end
end

local sq_ignore_level_hooked = false
local function hook_suddenquest_ignore_level()
    if not sq_ignore_level_hooked and sq_overrides.ignore_level then
        sq_ignore_level_hooked = true
        sdk.hook(
            sdk.find_type_definition('app.quest.condition.SuddenQuestCondition.CheckPlayerLevel'):get_method('onEvaluate'),
            function (args) if sq_overrides.ignore_level then return sdk.PreHookResult.SKIP_ORIGINAL end end,
            function (retval) if sq_overrides.ignore_level then return sdk.to_ptr(true) else return retval end end
        )
    end
end
local sq_ignore_scenario_hooked = false
local function hook_suddenquest_ignore_scenario()
    if not sq_ignore_scenario_hooked and sq_overrides.ignore_scenario then
        sq_ignore_scenario_hooked = true
        sdk.hook(
            sdk.find_type_definition('app.quest.condition.SuddenQuestCondition.CheckScenario'):get_method('onEvaluate'),
            function (args) if sq_overrides.ignore_scenario then return sdk.PreHookResult.SKIP_ORIGINAL end end,
            function (retval) if sq_overrides.ignore_scenario then return sdk.to_ptr(true) else return retval end end
        )
    end
end

local sq_ignore_sentiment_hooked = false
local function hook_suddenquest_ignore_sentiment() -- there is no sentiment conditions in basegame sudden quests :)
    if not sq_ignore_sentiment_hooked and sq_overrides.ignore_sentiment then
        sq_ignore_sentiment_hooked = true
        sdk.hook(
            sdk.find_type_definition('app.quest.condition.SuddenQuestCondition.CheckSentimentRank'):get_method('onEvaluate'),
            function (args) if sq_overrides.ignore_sentiment then return sdk.PreHookResult.SKIP_ORIGINAL end end,
            function (retval) if sq_overrides.ignore_sentiment then return sdk.to_ptr(true) else return retval end end
        )
    end
end
--#endregion

usercontent.__internal.on('_quests_loadconfig', function ()
    hook_suddenquest_ignore_timeofday()
    hook_suddenquest_ignore_level()
    hook_suddenquest_ignore_sentiment()
    hook_suddenquest_ignore_scenario()
end)

if core.editor_enabled then
    local ui = require('content_editor.ui')
    local editor = require('content_editor.editor')

    editor.define_window('quest_utils', 'Quest dev toolbox', function (state)
        if ui.basic.treenode_tooltip('event overrides', 'event - random culling request, NPC escort quests that you find in the wild') then
            ui.basic.setting_checkbox('Disable distance / time limit', sq_overrides, 'ignore_fail', config.save,
                "Disable escort quest failure conditions for being too far from the NPC for too long\nThis does not apply to battle quests because otherwise if you leave that surprise drake there, he might just stay there forever, blocking other escort quests."
            )

            local changed
            changed = ui.basic.setting_checkbox('Ignore time of day for events', sq_overrides, 'ignore_time', config.save) or changed
            changed = ui.basic.setting_checkbox('Ignore player level for events', sq_overrides, 'ignore_level', config.save) or changed
            changed = ui.basic.setting_checkbox('Ignore scenario (quest pre-requisites) for events', sq_overrides, 'ignore_scenario', config.save,
                'WARNING: Might break game behavior or be impossible to complete if the destination is inaccessible.'
            ) or changed
            changed = ui.basic.setting_checkbox('Ignore NPC sentiment for event', sq_overrides, 'ignore_sentiment', config.save,
                "Note that none of the basegame events actually use this condition, but it's here for completeness sake"
            ) or changed

            if changed then
                hook_suddenquest_ignore_timeofday()
                hook_suddenquest_ignore_level()
                hook_suddenquest_ignore_scenario()
                hook_suddenquest_ignore_sentiment()
            end

            imgui.tree_pop()
        end
    end)
end

_quest_DB.utils = {
    get_near_player_safe_npc_position = get_near_player_safe_npc_position,
    get_random_near_player_AIKeyLocation = get_random_near_player_AIKeyLocation,
    get_AIKeyLocation_position = gamedb.get_AIKeyLocation_position,
}
return _quest_DB.utils
