local events = require('content_editor.events')

-- fallback case for the few people whose REF loads up way too early for whatever reason
-- in theory, if one of these dynamic dictionaries are set, they should probably all be
local QuestManager = sdk.get_managed_singleton('app.QuestManager')
local function game_data_is_ready()
    return QuestManager.QuestCatalogDict and QuestManager.QuestCatalogDict:getCount() > 0
end

local TimeManager = sdk.get_managed_singleton('app.TimeManager') ---@type app.TimeManager
local MainFlowManager = sdk.get_managed_singleton('app.MainFlowManager') ---@type app.MainFlowManager
local function is_ingame_unpaused()
    return MainFlowManager:get_IsInGamePhase() and not TimeManager:get_IsTimeStop()
end

--- @param callback fun(is_ingame: boolean)
local function on_game_load_or_reload(callback)
    sdk.hook(
        sdk.find_type_definition('app.SaveDataManager'):get_method('loadGame'),
        nil,
        function (ret)
            callback(true)
            return ret
        end
    )
end

--- @param callback fun(is_ingame: boolean)
local function on_game_after_load(callback)
    sdk.hook(
        sdk.find_type_definition('app.GuiManager'):get_method('removeLoadGuiType'),
        function (args)
            local loadtype = sdk.to_int64(args[3]) & 0xffffffff
            -- app.GuiDefine.GuiType.Loading = 1
            if loadtype == 1 then callback(true) end
        end
    )
end

--- @param callback fun(is_ingame: boolean)
local function on_game_unload(callback)
    sdk.hook(
        sdk.find_type_definition('app.ui030201'):get_method('Initialize'),
        function () callback(false) end
    )
end

events.on('setup', function ()
    local enums = require('content_editor.enums')
    local utils = usercontent.utils
    local sounds = usercontent._sounds or select(2, pcall(require, 'content_editor.features.sounds'))

    if usercontent.core.editor_enabled then
        local CharacterID = enums.get_enum('app.CharacterID')
        CharacterID.set_display_labels(utils.map(CharacterID.values, function (val) return {val, CharacterID.valueToLabel[val] .. ' : ' .. utils.dd2.translate_character_name(val)} end))
        enums.create_subset(CharacterID, 'CharacterID_NPC', function (label) return label == 'Invalid' or label:sub(1,3) == 'ch3' and label:len() > 5 end)
    end

    local effects = usercontent.script_effects
    local CharacterManager = sdk.get_managed_singleton('app.CharacterManager')
    effects.add_effect_category('player', function ()
        return CharacterManager:get_ManualPlayer()
    end)

    if sounds and type(sounds) == 'table' then
        effects.register_effect_type({
            effect_type = 'sound_player',
            label = 'Play sound on player',
            category = 'player',
            start = function (entity)
                if entity.data.trigger_id then
                    sounds.trigger_on_gameobject(entity.data.trigger_id, utils.dd2.get_player():get_GameObject())
                end
            end,
            ui = function (entity)
                local changed, newsound = imgui.input_text('Sound trigger ID', tostring(entity.data.trigger_id), 1)
                entity.data.trigger_id = newsound
                return changed
            end
        })
    end
end)

usercontent.utils.dd2 = require('editors.core.utils')
usercontent.utils.get_player = function ()
    local player = usercontent.utils.dd2.get_player()
    local go = player and player:get_Valid() and player:get_GameObject()
    return go and go:get_Valid() and go or nil
end

require('editors.core.definitions')

--- @type ContentEditorGameController|table
return {
    game_data_is_ready = game_data_is_ready,
    is_ingame_unpaused = is_ingame_unpaused,

    on_game_load_or_reload = on_game_load_or_reload,
    on_game_unload = on_game_unload,
    on_game_after_load = on_game_after_load,
}
