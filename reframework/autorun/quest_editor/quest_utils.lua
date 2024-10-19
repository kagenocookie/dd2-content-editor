if type(_quest_DB) == 'nil' then _quest_DB = {} end
if _quest_DB.utils then return _quest_DB.utils end

local enums = require('quest_editor.enums')
local gamedb = require('quest_editor.gamedb')
local config = require('quest_editor.quests_config')
local ui = require('content_editor.ui')
local editor = require('content_editor.editor')

local function create_universal_position(x, y, z)
    local pos = ValueType.new(sdk.find_type_definition('via.Position')) ---@type any
    pos.x = x
    pos.y = y
    pos.z = z
    return pos
end

local getNearPlayerPosition = sdk.find_type_definition('app.QuestUtil'):get_method('getNearPlayerPosition')
local function get_near_player_safe_npc_position(distance, characterId)
    return getNearPlayerPosition:call(nil, distance, characterId)
end

local timeManager = sdk.get_managed_singleton("app.TimeManager")
local timeSkipManager = sdk.get_managed_singleton("app.TimeSkipManager")
local CharacterManager = sdk.get_managed_singleton('app.CharacterManager')

local MathEx = sdk.find_type_definition('via.MathEx')
local distSqVec3 = MathEx:get_method('distanceSq(via.vec3, via.vec3)')
local distSqPosition = MathEx:get_method('distanceSq(via.Position, via.Position)')

---@param time_hour number|nil
---@param time_min number|nil
---@param time_day number|nil
---@param timeType 'add'|'set'|nil
local function warp_player(position, time_hour, time_min, time_day, timeType)
    local player = sdk.get_managed_singleton("app.CharacterManager"):get_ManualPlayer()

    local transform = player:get_GameObject():get_Transform()
    if transform == nil then print('player has no transform?') return end
    position = position or transform:get_UniversalPosition()

    local now_hr = timeManager:get_InGameHour() --- @type number
    local now_min = timeManager:get_InGameMinute() --- @type number
    local now_day = timeManager:get_InGameDay() --- @type number

    local end_hr = now_hr
    local end_min = now_min
    local end_day = now_day

    if timeType == 'add' then
        if time_day == nil then time_day = 0 end
        if time_hour == nil then time_hour = 0 end
        if time_min == nil then time_min = 0 end

        end_min = now_min + time_min

        time_hour = now_hr + time_hour + math.floor(end_min / 60)
        end_min = end_min % 60

        end_day = now_day + time_day + math.floor(time_hour / 24)
        end_hr = time_hour % 24
    else
        if time_day == nil or time_hour == nil then
            if time_min == nil then time_min = now_min end
        else
            if time_min == nil then time_min = 0 end
        end
        if time_day == nil or time_day < now_day then time_day = now_day end
        if time_hour == nil then time_hour = now_hr end

        if time_day == now_day and (time_hour > now_hr or time_hour == now_hr and time_min > now_min) then
            end_day = end_day + 1
        end
        end_hr = time_hour
        end_min = time_min
    end
    print('Skipping time from', now_day, now_hr, now_min, 'to', end_day, end_hr, end_min ,' according to', time_hour, time_min, time_day, timeType)

    timeSkipManager:call('requestPlayerWarp', end_hr, end_min, end_day, position, transform:get_Rotation(), nil, true, true)
end

local AIAreaUtil = sdk.find_type_definition('app.AIAreaUtil')
local getPlayerLocalArea = AIAreaUtil:get_method('getPlayerLocalArea')
local getPlayerArea = AIAreaUtil:get_method('getPlayerArea')

local AIAreaManager = sdk.get_managed_singleton("app.AIAreaManager")
local NPCManager = sdk.get_managed_singleton("app.NPCManager")

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

local all_locations_cache = {}
local location_cache_anchor = nil
local function fetch_all_locations()
    if #all_locations_cache > 0 then
        if location_cache_anchor then
            local lastpos = location_cache_anchor[1]
            local lastposId = location_cache_anchor[2]
            local nowpos = gamedb.get_AIKeyLocation_position(lastposId)
            if nowpos and distSqVec3:call(nil, lastpos, nowpos) < 1 then
                return all_locations_cache
            end
            all_locations_cache = {}
            location_cache_anchor = nil
        else
            return all_locations_cache
        end
    end

    location_cache_anchor = nil
    local i = 1
    for _, loc in ipairs(enums.AIKeyLocation.labels) do
        local locId = enums.AIKeyLocation.labelToValue[loc]
        local pos = gamedb.get_AIKeyLocation_position(locId)
        if pos then
            all_locations_cache[i] = { pos = pos, name = loc }
            if location_cache_anchor == nil then location_cache_anchor = { pos, locId } end
            i = i + 1
        end
    end
    return all_locations_cache
end

local function npc_is_in_task_guide_dict(charaId)
    local it = NPCManager.TaskGuideFollowIdleNPCDict:call('System.Collections.IDictionary.GetEnumerator()')
    while it:MoveNext() do
        local npcId = it:get_Current()._value.CharaID
        if npcId == charaId then return true end
    end
    return false
end

local getComponent = sdk.find_type_definition('via.GameObject'):get_method('getComponent(System.Type)')
local function npc_is_follower(npc_go)
    local chara = getComponent:call(npc_go, sdk.typeof('app.Character'))
    local npcholder = NPCManager:call('getNPCHolder', chara:get_CharaID())
    if npcholder then
        if npcholder:call('isFlagTaskGuideFollow') then return true end
        if npc_is_in_task_guide_dict(chara:get_CharaID()) then
            -- the npcholder flag isn't always set, force update it here
            npcholder:call('setTaskGuideFollowIdle')
            return true
        end
    end
    return false
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
local function hook_suddenquest_ignore_sentiment() -- there is no sentiment conditions on the basegame sudden quests :)
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

_userdata_DB.__internal.on('_quests_loadconfig', function ()
    hook_suddenquest_ignore_timeofday()
    hook_suddenquest_ignore_level()
    hook_suddenquest_ignore_sentiment()
    hook_suddenquest_ignore_scenario()
end)

local ItemManager = sdk.get_managed_singleton('app.ItemManager')
local getItem = sdk.find_type_definition('app.ItemManager'):get_method('getItem(System.Int32, System.Int32, app.CharacterID, System.Boolean, System.Boolean, System.Boolean, app.ItemManager.GetItemEventType)')
local function give_item(itemId, count)
    print('giving player item id ', itemId, count)
    getItem:call(ItemManager, itemId, count, enums.CharacterID.labelToValue.ch000000_00, true, false, false, 1)
end

--#region IMGUI

editor.define_window('quest_utils', 'Quest dev toolbox', function (state)
    local changed
    changed, state.pos_picker, state.pos_filter = ui.core.filterable_enum_value_picker("Location", state.pos_picker, enums.AIKeyLocation, state.pos_filter)
    if imgui.button('Teleport to AIKeyLocation') and state.pos_picker then
        warp_player(gamedb.get_AIKeyLocation_uni_position(tonumber(state.pos_picker)))
    end

    changed, state.item_picker, state.item_filter = ui.core.filterable_enum_value_picker("Item", state.item_picker, enums.ItemID, state.item_filter)
    if imgui.button('Give player item') and state.item_picker then
        give_item(state.item_picker, 1)
    end

    changed, state.time_input = imgui.input_text("Time", state.time_input, 1)
    if imgui.button('Skip hours') then
        warp_player(nil, tonumber(state.time_input), nil, nil, 'add')
    end
    imgui.same_line()
    if imgui.button('Skip days') then
        warp_player(nil, nil, nil, tonumber(state.time_input), 'add')
    end

    ui.core.setting_checkbox('Show locations on screen', config.data.devtools, 'show_locations', config.save,
        "Due to how the game handles coordinates, I'm not sure if we actually show everything always.\nMaybe also try resetting scripts sometimes.")

    if ui.core.treenode_tooltip('event overrides', 'event - random culling request, NPC escort quests that you find in the wild') then
        ui.core.setting_checkbox('Disable distance / time limit', sq_overrides, 'ignore_fail', config.save,
            "Disable escort quest failure conditions for being too far from the NPC for too long\nThis does not apply to battle quests because otherwise if you leave that surprise drake there, he might just stay there forever, blocking other escort quests."
        )

        changed = ui.core.setting_checkbox('Ignore time of day for events', sq_overrides, 'ignore_time', config.save) or changed
        changed = ui.core.setting_checkbox('Ignore player level for events', sq_overrides, 'ignore_level', config.save) or changed
        changed = ui.core.setting_checkbox('Ignore scenario (quest pre-requisites) for events', sq_overrides, 'ignore_scenario', config.save,
            'WARNING: Might break game behavior or be impossible to complete if the destination is inaccessible.'
        ) or changed
        changed = ui.core.setting_checkbox('Ignore NPC sentiment for event', sq_overrides, 'ignore_sentiment', config.save,
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

local maxDistanceSqr = 50 * 50
re.on_frame(function ()
    if config.data.devtools.show_locations then
        local player = CharacterManager:get_ManualPlayer()
        if player and player:get_Valid() then
            local locations = fetch_all_locations()
            local curpos = player:get_Transform():get_Position()
            for _, loc in ipairs(locations) do
                local distSqr = distSqVec3:call(nil, loc.pos, curpos)
                if distSqr < maxDistanceSqr then
                    local flatpos = draw.world_to_screen(loc.pos)
                    if flatpos ~= nil then
                        draw.text(loc.name, flatpos.x, flatpos.y, 0xff0000EE)
                    end
                end
            end
        end
    end
end)
--#endregion

_quest_DB.utils = {
    get_near_player_safe_npc_position = get_near_player_safe_npc_position,
    get_random_near_player_AIKeyLocation = get_random_near_player_AIKeyLocation,
    get_AIKeyLocation_position = gamedb.get_AIKeyLocation_position,
    create_universal_position = create_universal_position,

    warp_player = warp_player,
    give_item = give_item,
}
return _quest_DB.utils