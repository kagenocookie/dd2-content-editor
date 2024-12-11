if type(usercontent) == 'nil' then usercontent = {} end
if usercontent._devtools then return usercontent._devtools end

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
    loc_bookmarks = {},
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

local t_position = sdk.find_type_definition('via.Position')

---@param position via.vec3|via.Position|Vector3f|nil
---@param time_hour number|nil
---@param time_min number|nil
---@param time_day number|nil
---@param timeType 'add'|'set'|nil
local function warp_player(position, time_hour, time_min, time_day, timeType)
    local player = sdk.get_managed_singleton("app.CharacterManager"):get_ManualPlayer()

    local transform = player:get_GameObject():get_Transform()
    if transform == nil then print('player has no transform?') return end

    if position and (not position.get_type_definition or not position--[[@as any]]:get_type_definition():is_a(t_position)) then
        local newpos = ValueType.new(sdk.find_type_definition('via.Position'))--[[@as any]]
        newpos.x = position.x
        newpos.y = position.y
        newpos.z = position.z
        position = newpos
    end

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

local bookmarkName = ''
editor.define_window('dev_tools', 'Dev tools', function (state)
    local changed
    changed, state.pos_picker, state.pos_filter = ui.basic.filterable_enum_value_picker("Location", state.pos_picker, AIKeyLocation, state.pos_filter)
    if imgui.button('Teleport to AIKeyLocation') and state.pos_picker then
        warp_player(get_AIKeyLocation_uni_position(tonumber(state.pos_picker)))
    end
    imgui.same_line()
    if imgui.button('Bookmark location') and state.pos_picker then
        storage.loc_bookmarks = storage.loc_bookmarks or {}
        storage.loc_bookmarks[#storage.loc_bookmarks+1] = { id = state.pos_picker, label = bookmarkName }
        editor.persistent_storage.save()
    end
    imgui.same_line()
    imgui.set_next_item_width(imgui.calc_item_width() - 300)
    bookmarkName = select(2, imgui.input_text('Bookmark label', bookmarkName))
    if storage.loc_bookmarks and #storage.loc_bookmarks > 0 and imgui.tree_node('Bookmarked locations') then
        imgui.begin_list_box('##Bookmarks', Vector2f.new(300, math.min((#storage.loc_bookmarks + 1) * (imgui.get_default_font_size() + 4), 400)))
        for idx, loc in ipairs(storage.loc_bookmarks) do
            if imgui.button(loc.label .. ' - ' .. AIKeyLocation.get_label(loc.id)) then
                warp_player(get_AIKeyLocation_uni_position(loc.id))
            end
            imgui.same_line()
            if imgui.button('X') then
                table.remove(storage.loc_bookmarks, idx)
            end
        end
        imgui.end_list_box()
        imgui.tree_pop()
    end

    changed, state.item_picker, state.item_filter = ui.basic.filterable_enum_value_picker("Item", state.item_picker, ItemID, state.item_filter)
    if imgui.button('Give player item') and state.item_picker then
        -- if selected item is gold, give 10k instead
        local count = state.item_picker == 93 and 10000 or 1
        give_item(state.item_picker, count)
    end

    changed, state.time_input = imgui.input_text("Time", state.time_input, 1)
    if imgui.button('Skip hours') then
        warp_player(nil, tonumber(state.time_input), nil, nil, 'add')
    end
    imgui.same_line()
    if imgui.button('Skip days') then
        warp_player(nil, nil, nil, tonumber(state.time_input), 'add')
    end

    ui.basic.setting_checkbox('Show locations on screen', storage, 'show_locations', editor.persistent_storage.save)
    if imgui.button('Stop all running custom effects') then
        usercontent.script_effects.stop_all_effects()
    end
    if imgui.button('Set all current enemy HP to 1') then
        ce_find('ch2:app.Monster::item._Chara:get_Hit():setHpValue(1.0, false)')
    end
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

usercontent._devtools = {
    warp_player = warp_player,
    give_item = give_item,
}
return usercontent._devtools