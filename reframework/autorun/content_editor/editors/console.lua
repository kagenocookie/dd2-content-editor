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

local console_ui_settings = { no_nonserialized_indicator = true, allow_props = true, allow_methods = true }

---@param obj REManagedObject|ValueType
local function display_managed(obj, state)
    ui.handlers.show(obj, nil, nil, nil, state, console_ui_settings)
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
            if ui.basic.treenode_suffix(tostring(k), helpers.to_string(v)) then
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

--- @param item via.Component
local function remap_gameobj(item) return item and item.get_GameObject and item:get_GameObject():add_ref()--[[@as any]] or item end

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

    local list = sceneFindComponents:call(scene, typedef)--[[@as SystemArray]]
    list = list and list:get_elements() or {}
    local count = 0
    if name_prefix then
        local filtered = {}
        for _, item in ipairs(list) do
            local s, go = pcall(compGetGO.call, compGetGO, item)
            if s and go then
                local name = goGetName:call(go)
                if name:find(name_prefix) then
                    filtered[#filtered+1] = item
                    count = count +1
                end
            end
        end
        list = filtered
    else
        local list2 = {}
        table.move(list, 1, #list, 1, list2)
        list = list2
        count = #list
    end

    if count > 0 and remap then
        for i, v in ipairs(list) do
            list[i] = remap(v)
        end
    end

    if count == 1 then return list[1] end
    return list
end

--- @param query string syntax: {gameobject_name?}:{classname?}:{mapper_function?}
local function find_game_object(query)
    local typedef
    local filter = nil
    local remap = nil
    if not query or query == '' then
        typedef = sdk.typeof('via.Transform')
        remap = remap_gameobj
    else
        local colon = query:find(':')
        if not colon then
            typedef = sdk.typeof('via.Transform')
            remap = remap_gameobj
            filter = query
        else
            filter = query:sub(1, colon - 1)
            local colon2 = query:find('::', colon + 1)

            if colon2 == colon + 1 then
                typedef = sdk.typeof('via.Transform')
            else
                local t = query:sub(colon + 1, colon2 and colon2 - 1 or #query)
                typedef = sdk.typeof(t)
                if not typedef then
                    error('Invalid type "' .. t .. '"')
                end
            end

            if colon2 then
                local success, remapper = pcall(load, 'return function(item) return ' .. query:sub(colon2 + 2) .. ' end', nil, 't')
                if not success or not remapper then error('load error' .. tostring(remapper)) end
                remap = remapper()
            end
        end
    end
    return find_gameobjects(typedef, filter, remap)
end

--- @param text string
--- @return boolean success, any result
local function prepare_exec_func(text)
    local uncached = false
    if text:sub(1, 1) == '!' then
        uncached = true
        text = text:sub(2)
    end

    if text:sub(1, 1) == '/' then
        text = text:sub(2)
        if uncached then
            return true, function () return find_game_object(text) end
        end
        return pcall(find_game_object, text)
    else
        local code = isMultiline(text) and text or 'return ' .. text
        local success, errOrFunc = pcall(load, code, nil, 't')
        if uncached then return success, errOrFunc end
        if not success or not errOrFunc then print('errored out', errOrFunc) return false, errOrFunc end
        return pcall(errOrFunc)
    end
end

function ce_find(text, single)
    local s, e = pcall(find_game_object, text)
    if single == true and type(e) == 'table' then
        return select(2, next(e))
    end
    return e
end

function ce_dump(command, outputFile)
    if not command then return nil end
    local result
    if type(command) == 'string' then
        result = ce_find(command)
    else
        result = command
    end
    if not outputFile then
        if type(command) == 'string' then
            outputFile = command
        else
            outputFile = tostring(command)
        end

        outputFile = outputFile:gsub('[^a-zA-Z0-9_]', '')
        if outputFile:len() > 100 then
            outputFile = outputFile:sub(1, 100)
        end
    end
    outputFile = 'ce_dump/' .. outputFile
    if outputFile:sub(-5) ~= '.json' then
        outputFile = outputFile .. '.json'
    end

    if result == nil then
        fs.write(outputFile, 'null')
        return '<no results>'
    elseif type(result) == 'table' then
        local items = utils.map(result, function (value)
            return usercontent.import_handlers.export(value, nil, { raw = true })
        end)
        json.dump_file(outputFile, items)
        return outputFile .. ' => ' .. #result .. ' items'
    elseif type(result) == 'userdata' then
        json.dump_file(outputFile, usercontent.import_handlers.export(result, nil, { raw = true }))
        return outputFile .. ' => ' .. tostring(result)
    else
        json.dump_file(result, outputFile)
        return outputFile .. ' => ' .. tostring(result)
    end
end

function ce_create(classname, data)
    if type(data) == 'string' then
        return usercontent.import_handlers.import(classname, json.load_string(data) or data)
    else
        return usercontent.import_handlers.import(classname, data or {})
    end
end

--- @param state table
--- @param text string
local function add_to_exec_list(state, text)
    table.insert(state.open_entries, 1, {text = text, id = math.random(1, 99999999)})
    state.history = state.history or {}
    if state.history[1] ~= text then
        table.insert(state.history, 1, text)
        while #state.history > max_history do
            table.remove(state.history, max_history)
        end
    end
    editor.persistent_storage.save()
end

local last_result_string = nil

editor.define_window('data_viewer', 'Console', function (state)
    local confirm = imgui.button('Run')
    imgui.same_line()
    if imgui.button('?') then state.toggleInfo = not state.toggleInfo end
    imgui.same_line()
    if state.multiline then
        state.input = select(2, ui.basic.expanding_multiline_input('##data_viewer', state.input or ''))
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
        local _success, _eval = prepare_exec_func(state.input)
        if _success then
            if type(_eval) == 'function' then
                _success, _eval = pcall(_eval)
                if _success then
                    last_result_string = helpers.to_string(_eval)
                else
                    last_result_string = 'ERROR: ' .. tostring(_eval)
                end
            else
                last_result_string = helpers.to_string(_eval)
            end
        else
            last_result_string = 'ERROR: ' .. tostring(_eval)
        end
        state.input = ''
    end

    if state.toggleInfo then
        imgui.begin_rect()
        imgui.text('Can write any valid lua code')
        imgui.text('Entering a / prefix does a search for game objects')
        imgui.text('/Player will search for any transforms that contain the text "Player"')
        imgui.text('/Player:app.Character will search for any app.Character components that contain the text "Player"')
        imgui.text('/Player:app.Character::item:get_GameObject() will evaluate the function after :: on each matching item and return that value instead')
        imgui.text('/:app.Character will find every currently active app.Character component irrelevant of name')
        imgui.text('All the content editor API is available under the `usercontent` variable')
        imgui.text('Entering a ! prefix makes the result evaluate every frame instead of showing a cached result')
        imgui.end_rect(2)
    end

    if last_result_string then
        if last_result_string:find('ERROR:') == 1 then
            imgui.text_colored(last_result_string, core.get_color('error'))
        else
            imgui.text(last_result_string)
        end
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
            entryResult = cache._eval
            if not success then
                imgui.text_colored('Error: ' .. tostring(entryResult), core.get_color('error'))
            elseif entryResult == nil then
                imgui.text_colored('No results', core.get_color('error'))
            elseif type(entryResult) == 'string' then
                imgui.text(entryResult)
            else
                local data
                if type(entryResult) == 'function' then
                    success, data = pcall(entryResult)
                else
                    success, data = true, entryResult
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