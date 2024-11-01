if type(_userdata_DB) == 'nil' then _userdata_DB = {} end
if _userdata_DB.editor then return _userdata_DB.editor end

local core = require('content_editor.core')
local internal = require('content_editor._internal')
local config = internal.config
local udb = require('content_editor.database')
local typecache = require('content_editor.typecache')
local enums = require('content_editor.enums')
local imgui_wrappers = require('content_editor.ui.imgui_wrappers')
local utils = require('content_editor.utils')

core.editor_enabled = true

local window_title = 'Content editor v' .. table.concat(core.VERSION, '.')
local tabs = {}

--- @class WindowDefinition
--- @field title string
--- @field draw WindowCallback

--- @alias WindowCallback fun(state: EditorState|table)

--- Define and retrieve a persistent storage table that is not linked to a specific editor window
--- @generic T : table
--- @param key string
--- @param defaultData nil|T
--- @return T
local function persistent_storage_get(key, defaultData)
    config.data.editor.storage = config.data.editor.storage or {}
    local data = config.data.editor.storage[key]
    if not data then
        data = defaultData and utils.clone_table(defaultData) or {}
        config.data.editor.storage[key] = data
    else
        if defaultData then
            utils.merge_into_table(defaultData, data)
        end
    end
    return data
end

-- JP font borrowed from EMV engine
local utf16_font = imgui.load_font('NotoSansSC-Bold.otf', imgui.get_default_font_size()+2, {
    0x0020, 0x00FF, -- Basic Latin + Latin Supplement
    0x2000, 0x206F, -- General Punctuation
    0x3000, 0x30FF, -- CJK Symbols and Punctuations, Hiragana, Katakana
    0x31F0, 0x31FF, -- Katakana Phonetic Extensions
    0xFF00, 0xFFEF, -- Half-width characters
    0x4e00, 0x9FAF, -- CJK Ideograms
    0,
})

--- @type table<string, WindowDefinition>
local editor_defs = {
    user = {
        title = 'User',
        draw = function ()
            local changed, newValue = imgui.input_text('Author name', config.data.editor.author_name)
            if changed then
                config.data.editor.author_name = newValue
                config.save()
            end
            changed, newValue = imgui.input_text_multiline('Author description', config.data.editor.author_description or '', 10)
            if changed then
                config.data.editor.author_description = newValue
                config.save()
            end
            imgui_wrappers.tooltip('Name to save into the author field for new data bundles')
        end
    },
    load_order = {
        title = 'Load order',
        draw = require('content_editor._load_order_handler')(udb)
    },
}
local editor_ids = {''}
local editor_labels = {'<open new window>'}

local function set_need_game_restart()
    internal.need_restart_for_clean_data = true
end

local function set_need_script_reset()
    internal.need_script_reset = true
end

--- @class _ActiveEditorTab
--- @field state EditorState
--- @field editor WindowCallback

--- @type _ActiveEditorTab[]
local tabHandlers = {}

--- @param window_type_id string The ID string by which to identify the window type
--- @param title string The default title to display for this editor
--- @param draw_callback WindowCallback
local function define_window(window_type_id, title, draw_callback)
    editor_defs[window_type_id] = {
        title = title,
        draw = draw_callback,
    }
    editor_ids[#editor_ids+1] = window_type_id
    editor_labels[#editor_labels+1] = title
end

--- @param window_type_id string
local function add_editor_tab(window_type_id)
    local editorDefinition = editor_defs[window_type_id]
    if not editorDefinition then
        print('ERROR: Unknown editor type: ' .. window_type_id)
        return nil
    end

    local state = config.data.editor.tabs[window_type_id]
    if not state then
        state = {
            id = internal.config._get_next_editor_id(),
            name = window_type_id,
            title = editorDefinition.title,
        }
        config.data.editor.tabs[window_type_id] = state
    end

    --- @type _ActiveEditorTab
    local handler = {
        state = state,
        editor = editorDefinition.draw,
    }

    local idx = #tabs + 1
    tabHandlers[idx] = handler
    tabs[idx] = state.title
end

--- @param window_type_id string
--- @param initial_state nil|EditorState
--- @return integer|nil windowId The ID of the new editor window or nil if window failed to create
local function open_editor_window(window_type_id, initial_state)
    local editorDefinition = editor_defs[window_type_id]
    if not editorDefinition then
        print('ERROR: Unknown editor type: ' .. window_type_id)
        return nil
    end

    --- @type EditorState
    local state = initial_state and utils.clone_table(initial_state) or {}
    state.id = internal.config._get_next_editor_id()
    state.name = window_type_id
    state.title = state.title or editorDefinition.title
    config.data.editor.windows[#config.data.editor.windows + 1] = state
    config.save()
    return state.id
end

--- @param window_type_id string
--- @param id integer
--- @param state table
local function embed_window(window_type_id, id, state)
    local handler = editor_defs[window_type_id]
    if handler then
        imgui.push_id('window_' .. id)
        local success, error = pcall(handler.draw, state)
        if not success then
            print('ERROR: content editor window ' .. (state.name or window_type_id) .. '#' .. id .. ' caused error:\n' .. tostring(error))
        end
        imgui.pop_id()
    else
        imgui.text_colored('Unknown window type ' .. (state.name or window_type_id), core.get_color('error'))
    end
end

define_window('bundles', 'Data bundles', require('content_editor.editors.data_bundles'))

define_window('save_button', 'Save button', function ()
    if _userdata_DB.editor.active_bundle then
        if imgui.button('Save') then
            _userdata_DB.database.save_bundle(_userdata_DB.editor.active_bundle)
        end
        if _userdata_DB.database.bundle_has_unsaved_changes(_userdata_DB.editor.active_bundle) then
            imgui.same_line()
            imgui.text_colored('*', core.get_color('danger'))
        end
        imgui.same_line()
        imgui.text('Bundle: ' .. _userdata_DB.editor.active_bundle)
    else
        imgui.text('No active bundle')
    end
end)

add_editor_tab('load_order')
add_editor_tab('user')
add_editor_tab('bundles')

local function draw_editor()
    if internal.need_restart_for_clean_data then
        imgui.text_colored('Some changes may need a full game restart to apply.', core.get_color('danger'))
    elseif internal.need_script_reset then
        imgui.text_colored('Some changes need a script reset.', core.get_color('danger'))
    end

    local changed
    if imgui.button('Refresh database') then
        udb.reload_all_bundles()
    end
    imgui_wrappers.tooltip('This will reload all DB files from disk and re-import them into the game. Any unsaved changes will be lost.\nNot fully tested yet, may not work as expected - Reset scripts can be more reliable.')

    imgui.same_line()
    if imgui.button('Reset type cache') then
        typecache.clear()
        set_need_script_reset()
    end
    imgui.same_line()
    if imgui.button('Save type cache') then
        typecache.save()
    end
    if imgui.is_item_hovered() then imgui.set_tooltip('Force save the current type cache') end
    imgui.same_line()
    local idx
    imgui.set_next_item_width(200)
    changed, idx = imgui.combo('##Open new window', 1, editor_labels)
    if changed and idx > 1 then
        open_editor_window(editor_ids[idx])
    end

    if imgui.tree_node('Data dumps') then
        if imgui.button('Dump enums: ' .. core._basepath .. 'dump/enums/*.json') then
            enums.dump_all_enums()
        end

        imgui.tree_pop()
    end

    local w = imgui.calc_item_width()
    imgui.set_next_item_width(w / 2)
    local newbundle
    changed, newbundle = imgui_wrappers.enum_picker('Active bundle', config.data.editor.active_bundle, udb.bundles_enum)
    if changed then
        if newbundle == '' or newbundle == udb.bundles_enum.valueToLabel[0] then newbundle = nil end
        config.data.editor.active_bundle = newbundle
        _userdata_DB.editor.active_bundle = newbundle
        config.save()
    end
    imgui_wrappers.tooltip("The bundle that you're currently editing.\nAll new entities will be stored in this bundle.")
    local unsavedBundleChanges = udb.bundle_has_unsaved_changes(config.data.editor.active_bundle)
    if unsavedBundleChanges then
        imgui.same_line()
        if imgui.button('Save changes') then
            udb.save_bundle(config.data.editor.active_bundle)
        end
        imgui.same_line()
        imgui.text_colored('* Unsaved changes', core.get_color('danger'))
    end

    changed, config.data.editor.selected_editor_tab_index = imgui_wrappers.tabs(tabs, config.data.editor.selected_editor_tab_index)
    if changed then config.save() end

    local tabHandler = tabHandlers[config.data.editor.selected_editor_tab_index]
    if not tabHandler then
        imgui.text('UNKNOWN TAB HANDLER ' .. config.data.editor.selected_editor_tab_index)
        return
    end

    if imgui.button('Clone editor to new window') then
        open_editor_window(tabHandler.state.name, tabHandler.state)
    end

    imgui.spacing()
    imgui.push_id('entity_editor')
    tabHandler.editor(tabHandler.state)
    imgui.pop_id()
end

re.on_frame(function ()
    if reframework:is_drawing_ui() then
        if config.data.editor.show_window then
            local font_succeeded = pcall(imgui.push_font, utf16_font)

            config.data.editor.show_window = imgui.begin_window(window_title, config.data.editor.show_window)
            if config.data.editor.show_window then
                imgui.spacing()
                imgui.indent(4)
                draw_editor()
                imgui.unindent(4)
                imgui.end_window()
            else
                config.save()
            end

            for i = 1, #config.data.editor.windows do
                local windowState = config.data.editor.windows[i]
                if windowState then
                    local show = imgui.begin_window(windowState.title .. ' #' .. windowState.id, true)
                    if not show then
                        table.remove(config.data.editor.windows, i)
                        config.save()
                        i = i - 1
                    else
                        embed_window(windowState.name, windowState.id, windowState)
                        imgui.end_window()
                    end
                end
            end

            if font_succeeded then imgui.pop_font() end
        end

    end
end)

_userdata_DB.editor = {
    define_window = define_window,
    add_editor_tab = add_editor_tab,
    open_editor_window = open_editor_window,

    embed_window = embed_window,

    get_color = core.get_color,

    set_need_game_restart = set_need_game_restart,
    set_need_script_reset = set_need_script_reset,

    active_bundle = config.data.editor.active_bundle,

    persistent_storage = {
        get = persistent_storage_get,
        save = function () config.save() end,
    },
}

return _userdata_DB.editor
