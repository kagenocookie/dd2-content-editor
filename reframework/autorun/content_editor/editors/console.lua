if _userdata_DB == nil then _userdata_DB = {} end
if _userdata_DB.console then return _userdata_DB.console end


local udb = require('content_editor.database')
local core = require('content_editor.core')
local helpers = require('content_editor.helpers')
local utils = require('content_editor.utils')

local editor = require('content_editor.editor')
local ui = require('content_editor.ui')

local max_history = 50

---@param obj REManagedObject|ValueType
local function display_managed(obj, state)
    ui.handlers.show(obj, nil, nil, nil, 'dv_' .. state.id .. '_' .. obj:get_address())
end

local display_table

---@param tbl table
display_table = function(tbl, state)

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
    local windows = _userdata_DB.__internal.config.data.editor.windows
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

local editorConfig = _userdata_DB.__internal.config

editorConfig.data.editor--[[@as any]].console = editorConfig.data.editor.console or {}
local globalSettings = editorConfig.data.editor.console
local maxlines = 12

local function exec_text(state, text)
    table.insert(state.open_entries, 1, {text = text, id = math.random(1, 99999999)})
    state.history = state.history or {}
    table.insert(state.history, 1, text)
    while #state.history > max_history do
        table.remove(state.history, max_history)
    end
    editorConfig.save()
end

editor.define_window('data_viewer', 'Data viewer', function (state)
    local confirm = imgui.button('Run')
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
    if changed then _userdata_DB.__internal.config.save() end

    imgui.same_line()
    changed, state.multiline = imgui.checkbox('Multiline', state.multiline)
    if imgui.is_item_hovered() then imgui.set_tooltip("Allow entering multiple lines. To get an actual value result, return that value.") end
    if changed then _userdata_DB.__internal.config.save() end

    if state.input and state.input ~= '' and confirm then
        exec_text(state, state.input)
        state.input = ''
    end

    if imgui.tree_node('History') then
        --- @type string[]
        state.history = state.history or {}
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
                    exec_text(state, bookmark.text)
                end
                if copy then
                    state.input = bookmark.text
                    state.multiline = isMultiline(bookmark.text)
                end
                if remove then
                    table.remove(globalSettings.bookmarks, idx)
                    editorConfig.save()
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
                        editorConfig.save()
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
            _userdata_DB.__internal.config.save()
            imgui.pop_id()
            break
        end
        imgui.same_line()
        if imgui.tree_node(entry.text) then
            local success
            if isMultiline(entry.text) then
                success, func = pcall(load, entry.text, nil, 't')
            else
                success, func = pcall(load, 'return ' .. entry.text, nil, 't')
            end
            if not success then
                imgui.text_colored('Syntax error:' .. tostring(func), core.get_color('error'))
            elseif func == nil then
                imgui.text_colored('Nil func oi:' .. tostring(func), core.get_color('error'))
            else
                success, data = pcall(func)
                if not success then
                    imgui.text_colored('Error:' .. tostring(data), core.get_color('error'))
                else
                    if type(data) == 'userdata' then
                        display_managed(data--[[@as any]], state)
                    elseif type(data) == 'table' then
                        display_table(data, state)
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

_userdata_DB.console = {
}
return _userdata_DB.console