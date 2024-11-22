if usercontent == nil then usercontent = {} end
if usercontent.console then return usercontent.console end


local udb = require('content_editor.database')
local core = require('content_editor.core')
local helpers = require('content_editor.helpers')
local utils = require('content_editor.utils')

local editor = require('content_editor.editor')
local ui = require('content_editor.ui')

local max_history = 50

local console_ctx = ui.context.create_root({}, nil, 'console', '__console')

---@param obj REManagedObject|ValueType
local function display_managed(obj, state)
    ui.handlers.show(obj, nil, nil, nil, state)
end

local result_cache = {}

---@param tbl table
local function display_table(tbl, state)

    local len = #tbl
    if len == 0 then len = utils.assoc_table_count(tbl) end
    imgui.text(tostring(tbl) .. ' (count: ' .. len .. ')')

    for k, v in pairs(tbl) do
        if type(v) == 'table' then
            if imgui.tree_node(tostring(k)..':') then
                display_table(v, state)
                imgui.tree_pop()
            end
        elseif type(v) == 'userdata' then
            if ui.core.treenode_suffix(tostring(k), helpers.to_string(v)) then
                display_managed(v--[[@as any]], state)
                imgui.tree_pop()
            end
        else
            imgui.text(tostring(k) .. ': ' .. tostring(v))
        end
    end
end


udb.events.on('ready', function ()
    -- clear open entries from all console windows
    local windows = usercontent.__internal.config.data.editor.windows
    for _, state in pairs(windows) do
        if state.name == 'data_viewer' and state.open_entries and not state.keep_results then
            state.open_entries = nil
        end
    end
end)

---@param text string
local function linecount(text)
    local m = text:gmatch('\n')
    local count = 1
    while m() do
        count = count + 1
    end
    return count
end

---@param text string
local function isMultiline(text)
    return not not text:find('\n')
end

---@param text string
local function firstLine(text)
    local nl = text:find('\n')
    if nl then
        return text:sub(1, nl - 1) .. ' (...)'
    end
    return text
end

local globalSettings = editor.persistent_storage.get('console', {})
local maxlines = 12

local sceneFindComponents = sdk.find_type_definition('via.Scene'):get_method('findComponents(System.Type)')
local compGetGO = sdk.find_type_definition('via.Component'):get_method('get_GameObject')
local goGetName = sdk.find_type_definition('via.GameObject'):get_method('get_Name')
--- @param typedef System.Type
--- @param name_prefix string|nil
--- @param remap nil|fun(item: any): any
local function find_gameobjects(typedef, name_prefix, remap)
    local scene = core.game.get_root_scene()
    if not scene then return nil end
    if not typedef then return nil end

    local list = sceneFindComponents:call(scene, typedef)
    list = list and list:get_elements() or {}
    if name_prefix then
        local filtered = {}
        for _, item in ipairs(list) do
            local s, go = pcall(compGetGO.call, compGetGO, item)
            if s and go then
                local name = goGetName:call(go)
                if name:find(name_prefix) then
                    if remap then
                        filtered[#filtered+1] = remap(item)
                    else
                        filtered[#filtered+1] = item
                    end
                end
            end
        end
        list = filtered
    end
    if #list == 1 then return list[1] end
    return list
end

--- @param text string
--- @return boolean success, any result
local function prepare_exec_func(text)
    if text:sub(1, 1) == '/' then
        local filter = text ~= '/' and text:sub(2) or nil
        local typedef
        if not filter then
            typedef = sdk.typeof('via.Transform')
        else
            local colon = filter:find(':')
            if not colon then
                typedef = sdk.typeof('via.Transform')
            else
                local colon2 = filter:find('::', colon + 1)
                if colon2 then
                    local t = filter:sub(1, colon - 1)
                    typedef = sdk.typeof(t)
                    if not typedef then
                        return false, 'Invalid type "' .. t .. '"'
                    end
                    -- print('colon2', 'function(item) return ' .. filter:sub(colon2 + 2) .. ' end')
                    local success, remapper = pcall(load, 'return function(item) return ' .. filter:sub(colon2 + 2) .. ' end', nil, 't')
                    if not success or not remapper then return false, 'load error' .. tostring(remapper) end

                    filter = filter:sub(colon + 1, colon2 - 1)
                    return true, find_gameobjects(typedef, filter, remapper())
                else
                    local t = filter:sub(1, colon - 1)
                    typedef = sdk.typeof(t)
                    filter = filter:sub(colon + 1)
                    if not typedef then
                        return false, 'Invalid type "' .. t .. '"'
                    end
                end
            end
        end
        return true, find_gameobjects(typedef, filter)
    elseif text:sub(1, 1) == '!' then
        local code = isMultiline(text) and text:sub(2) or 'return ' .. text:sub(2)
        local success, errOrFunc = pcall(load, code, nil, 't')
        if not success or not errOrFunc then print('errored out', errOrFunc) return false, errOrFunc end
        return pcall(errOrFunc)
    else
        local code = isMultiline(text) and text or 'return ' .. text
        return pcall(load, code, nil, 't')
    end
end

_G.ce_find = function (text)
    local s, e = prepare_exec_func(text)
    return e
end

local function add_to_exec_list(state, text)
    table.insert(state.open_entries, 1, {text = text, id = math.random(1, 99999999)})
    state.history = state.history or {}
    table.insert(state.history, 1, text)
    while #state.history > max_history do
        table.remove(state.history, max_history)
    end
    editor.persistent_storage.save()
end

editor.define_window('data_viewer', 'Data console', function (state)
    local confirm = imgui.button('Run')
    imgui.same_line()
    if imgui.button('?') then state.toggleInfo = not state.toggleInfo end
    imgui.same_line()
    if state.multiline then
        local w = imgui.calc_item_width()
        local lines = state.input and math.min(maxlines, linecount(state.input)) or 1
        state.input = select(2, imgui.input_text_multiline('##data_viewer', state.input or '', Vector2f.new(w, 6 + lines * 18)))
    else
        state.input = select(2, imgui.input_text('##data_viewer', state.input or ''))
    end
    imgui.same_line()
    local changed
    changed, state.keep_results = imgui.checkbox('Keep results', state.keep_results)
    if imgui.is_item_hovered() then imgui.set_tooltip('If you want all data results to stay between game restarts and script resets') end
    if changed then usercontent.__internal.config.save() end

    imgui.same_line()
    changed, state.multiline = imgui.checkbox('Multiline', state.multiline)
    if imgui.is_item_hovered() then imgui.set_tooltip("Allow entering multiple lines. To get an actual value result, return that value.") end
    if changed then usercontent.__internal.config.save() end

    if state.input and state.input ~= '' and confirm then
        add_to_exec_list(state, state.input)
        state.input = ''
    end

    if state.toggleInfo then
        imgui.text('Can write any valid lua code')
        imgui.text('Entering a / prefix does a search for game objects')
        imgui.text('/Player will search for any transforms that contain the text "Player"')
        imgui.text('/app.Character:Player will search for any app.Character components that contain the text "Player"')
        imgui.text('/app.Character:Player::item:get_GameObject() will evaluate the function after :: on each matching item and return that value instead')
        imgui.text('Entering a ! prefix evaluates the result once and retrieves the cached result instead of evaluating every frame')
    end

    if imgui.tree_node('History') then
        --- @type string[]
        state.history = state.history or {}
        if imgui.button('Clear history') then
            state.history = {}
            ui.context.delete_children(console_ctx)
            editor.persistent_storage.save()
        end

        for idx, historyEntry in ipairs(state.history) do
            imgui.push_id(idx..historyEntry)
            local use = imgui.button('Use')
            imgui.same_line()
            local copy = imgui.button('Copy')
            imgui.same_line()
            local removeHistory = imgui.button('Remove')
            imgui.same_line()
            local bm = imgui.button('Bookmark')
            imgui.pop_id()
            imgui.same_line()
            imgui.text(idx .. '. ' .. firstLine(historyEntry))

            if use then
                state.open_entries[#state.open_entries+1] = {text = historyEntry, id = math.random(1, 99999999)}
            end
            if removeHistory then
                table.remove(state.history, idx)
                break
            end
            if copy then
                state.input = historyEntry
                state.multiline = isMultiline(historyEntry)
            end
            if bm then
                globalSettings.bookmarks = globalSettings.bookmarks or {}
                globalSettings.bookmarks[#globalSettings.bookmarks+1] = {
                    id = math.random(1,9999999),
                    text = historyEntry,
                    label = firstLine(historyEntry),
                    time = utils.get_irl_timestamp()
                }
                editor.persistent_storage.save()
            end
        end
        imgui.tree_pop()
    end
    if globalSettings.bookmarks and #globalSettings.bookmarks > 0 then
        if imgui.tree_node('Bookmarks') then
            for idx, bookmark in ipairs(globalSettings.bookmarks) do
                imgui.push_id(bookmark.id)
                local use = imgui.button('Use')
                imgui.same_line()
                local copy = imgui.button('Copy')
                imgui.same_line()
                local remove = imgui.button('Remove')
                imgui.same_line()
                local rename = imgui.button('Rename')
                imgui.same_line()
                imgui.text(bookmark.label)
                if use then
                    add_to_exec_list(state, bookmark.text)
                end
                if copy then
                    state.input = bookmark.text
                    state.multiline = isMultiline(bookmark.text)
                end
                if remove then
                    table.remove(globalSettings.bookmarks, idx)
                    editor.persistent_storage.save()
                    imgui.pop_id()
                    break
                end
                if rename then
                    state.renaming = { id = bookmark.id, label = bookmark.label }
                end
                if state.renaming and state.renaming.id == bookmark.id then
                    imgui.indent(12)
                    state.renaming.label = select(2, imgui.input_text('New name', state.renaming.label))
                    if imgui.button('Confirm') then
                        bookmark.label = state.renaming.label
                        state.renaming = nil
                        editor.persistent_storage.save()
                    end
                    imgui.same_line()
                    if imgui.button('Cancel') then
                        state.renaming = nil
                    end
                    imgui.unindent(12)
                end
                imgui.pop_id()
            end

            imgui.tree_pop()
        end
    end
    --- @type {text: string, id: number}[]
    state.open_entries = state.open_entries or {}

    for idx, entry in ipairs(state.open_entries) do
        imgui.push_id(entry.id)
        if imgui.button('X') then
            table.remove(state.open_entries, idx)
            usercontent.__internal.config.save()
            imgui.pop_id()
            break
        end
        imgui.same_line()
        if imgui.tree_node(entry.text) then
            local cache = result_cache[entry]
            if cache then
                imgui.same_line()
                if imgui.button('Re-evaluate') then
                    cache._eval = nil
                    cache._success = nil
                    cache._is_managed = nil
                end
            end
            local success
            if not cache or cache._eval == nil then
                cache = cache or {}
                result_cache[entry] = cache
                cache._success, cache._eval = prepare_exec_func(entry.text)
                success = cache._success
            else
                success = cache._success
            end
            func = cache._eval
            if not success then
                imgui.text_colored('Error: ' .. tostring(func), core.get_color('error'))
            elseif func == nil then
                imgui.text_colored('No results', core.get_color('error'))
            elseif type(func) == 'string' then
                imgui.text(func)
            else
                local data
                if type(cache._eval) == 'function' then
                    success, data = pcall(func)
                else
                    success, data = true, cache._eval
                end
                if not success then
                    imgui.text_colored('Error:' .. tostring(data), core.get_color('error'))
                else
                    console_ctx.data.children = console_ctx.data.children or {}
                    if type(data) == 'userdata' then
                        if cache._is_managed == nil then cache._is_managed = sdk.is_managed_object(data) end
                        if cache._is_managed then
                            display_managed(data--[[@as any]], console_ctx.data.children)
                        else
                            imgui.text(tostring(data))
                        end
                    elseif type(data) == 'table' then
                        display_table(data, console_ctx.data.children)
                    elseif data == nil then
                        imgui.text('nil')
                    else
                        imgui.text(tostring(data) .. ' ('..type(data)..')')
                    end
                end
            end
            imgui.tree_pop()
        end
        imgui.pop_id()
    end
end)

usercontent.console = {
}
return usercontent.console