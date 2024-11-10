-- fallback case for the few people whose REF loads up way too early for whatever reason
-- in theory, if one of these dynamic dictionaries are set, they should probably all be
local QuestManager = sdk.get_managed_singleton('app.QuestManager')
local function game_data_is_ready()
    return QuestManager.QuestCatalogDict and QuestManager.QuestCatalogDict:getCount() > 0
end

local function setup()
    local enums = _userdata_DB.enums
    local utils = _userdata_DB.utils
    local utils_dd2 = _userdata_DB.utils_dd2
    local CharacterID = enums.get_enum('app.CharacterID')
    CharacterID.set_display_labels(utils.map(CharacterID.values, function (val) return {val, CharacterID.valueToLabel[val] .. ' : ' .. utils_dd2.translate_character_name(val)} end))
    enums.create_subset(CharacterID, 'CharacterID_NPC', function (label) return label == 'Invalid' or label:sub(1,3) == 'ch3' and label:len() > 5 end)

    local effects = _userdata_DB.script_effects
    local CharacterManager = sdk.get_managed_singleton('app.CharacterManager')
    effects.add_effect_category('player', function ()
        return CharacterManager:get_ManualPlayer()
    end)
end

return {
    game_data_is_ready = game_data_is_ready,
    setup = setup,
}
