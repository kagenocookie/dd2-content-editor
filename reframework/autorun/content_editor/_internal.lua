if type(_userdata_DB) == 'nil' then _userdata_DB = {} end
if _userdata_DB.__internal and _userdata_DB.__internal.config then return _userdata_DB.__internal end

require('content_editor.events')
local core = require('content_editor.core')
local utils = require('content_editor.utils')

--- @class UserdataConfig
--- @field bundle_order string[]
--- @field bundle_settings table<string, UserdataConfig.BundleSettings>
--- @field editor _UserdataConfig.EditorSettings

--- @class _UserdataConfig.EditorSettings
--- @field enabled boolean
--- @field show_window boolean
--- @field selected_editor_tab_index number
--- @field author_name string
--- @field active_bundle string
--- @field next_editor_id integer
--- @field tabs table<string, EditorState>
--- @field windows EditorState[]

--- @alias EditorState _EditorStateDefaults|table

--- @class _EditorStateDefaults
--- @field id integer
--- @field name string
--- @field title string

--- @class UserdataConfig.BundleSettings
--- @field disabled boolean

--- @type UserdataConfig
local config = {
    editor = {
        enabled = false,
        show_window = false,
        selected_editor_tab_index = 1,
        author_name = 'Unknown user',
        active_bundle = '',
        tabs = {},
        windows = {},
        next_editor_id = 1,
    },
    bundle_order = {},
    bundle_settings = {},
}

local function load_config()
    local f = json.load_file(core.get_path('editor_settings.json'))
    if f then
        if f.bundle_settings then
            for name, settings in pairs(f.bundle_settings) do
                local existing = config.bundle_settings[name]
                if not existing then
                    config.bundle_settings[name] = settings
                else
                    utils.merge_into_table(settings, existing)
                end
            end
        end

        if f.bundle_order then config.bundle_order = f.bundle_order end
        utils.table_assign(config.editor, f.editor or {})

        _userdata_DB.__internal.emit('_loadConfig', config)
    end
end

local function save_config()
    json.dump_file(core.get_path('editor_settings.json'), config)
end

load_config()
_userdata_DB.__internal.config = {
    data = config,
    save = save_config,
    load = load_config,
    _get_next_editor_id = function ()
        local id = config.editor.next_editor_id
        config.editor.next_editor_id = id + 1
        return id
    end
}

core.editor_enabled = config.editor.enabled
return _userdata_DB.__internal
