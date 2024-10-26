if type(_userdata_DB) == 'nil' then _userdata_DB = {} end
if _userdata_DB._devtools then return _userdata_DB._devtools end

local core = require('content_editor.core')
if not core.editor_enabled then return end

local enums = require('content_editor.enums')
local ui = require('content_editor.ui')
local editor = require('content_editor.editor')

local AIKeyLocation = enums.get_enum('app.AIKeyLocation')
local ItemID = enums.get_enum('app.ItemIDEnum')
local CharacterID = enums.get_enum('app.CharacterID')

local storage = editor.persistent_storage.get('devtools', {
    show_locations = false,
})

local AIAreaManager = sdk.get_managed_singleton("app.AIAreaManager") ---@type app.AIAreaManager

local function get_AIKeyLocation_position(locationId)
    local node = AIAreaManager:getKeyLocationNode(locationId)
    return node and node:get_WorldPos()
end

local function get_AIKeyLocation_uni_position(locationId)
    local node = AIAreaManager:getKeyLocationNode(locationId)
    return node and node:get_UniversalPosition()
end

local timeManager = sdk.get_managed_singleton("app.TimeManager")
local timeSkipManager = sdk.get_managed_singleton("app.TimeSkipManager")
local CharacterManager = sdk.get_managed_singleton('app.CharacterManager')

local MathEx = sdk.find_type_definition('via.MathEx')
local distSqVec3 = MathEx:get_method('distanceSq(via.vec3, via.vec3)')

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

local all_locations_cache = {}
local location_cache_anchor = nil
local function fetch_all_locations()
    if #all_locations_cache > 0 then
        if location_cache_anchor then
            local lastpos = location_cache_anchor[1]
            local lastposId = location_cache_anchor[2]
            local nowpos = get_AIKeyLocation_position(lastposId)
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
    for _, loc in ipairs(AIKeyLocation.labels) do
        local locId = AIKeyLocation.labelToValue[loc]
        local pos = get_AIKeyLocation_position(locId)
        if pos then
            all_locations_cache[i] = { pos = pos, name = loc }
            if location_cache_anchor == nil then location_cache_anchor = { pos, locId } end
            i = i + 1
        end
    end
    return all_locations_cache
end

local ItemManager = sdk.get_managed_singleton('app.ItemManager')
local getItem = sdk.find_type_definition('app.ItemManager'):get_method('getItem(System.Int32, System.Int32, app.CharacterID, System.Boolean, System.Boolean, System.Boolean, app.ItemManager.GetItemEventType)')
local function give_item(itemId, count)
    print('giving player item id ', itemId, count)
    getItem:call(ItemManager, itemId, count, CharacterID.labelToValue.ch000000_00, true, false, false, 1)
end

--#region IMGUI

editor.define_window('dev_tools', 'Dev tools', function (state)
    local changed
    changed, state.pos_picker, state.pos_filter = ui.core.filterable_enum_value_picker("Location", state.pos_picker, AIKeyLocation, state.pos_filter)
    if imgui.button('Teleport to AIKeyLocation') and state.pos_picker then
        warp_player(get_AIKeyLocation_uni_position(tonumber(state.pos_picker)))
    end

    changed, state.item_picker, state.item_filter = ui.core.filterable_enum_value_picker("Item", state.item_picker, ItemID, state.item_filter)
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

    ui.core.setting_checkbox('Show locations on screen', storage, 'show_locations', editor.persistent_storage.save)
end)

local maxDistanceSqr = 50 * 50
re.on_frame(function ()
    if storage.show_locations then
        local player = CharacterManager:get_ManualPlayer() --[[@as app.Character]]
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

_userdata_DB._devtools = {
    warp_player = warp_player,
    give_item = give_item,
}
return _userdata_DB._devtools