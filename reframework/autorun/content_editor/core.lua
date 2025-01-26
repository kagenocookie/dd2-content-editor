if type(usercontent) == 'nil' then usercontent = {} end
if usercontent.core then return usercontent.core end

require('content_editor.events')
local utils = require('content_editor.utils')

local color_statuses = {
    default = 0,
    disabled = 1,
    finished = 2,
    error = 3,
    danger = 4,
    warning = 5,
    info = 6,
    note = 7,
    success = 8,
}

local data_basepath = 'usercontent'
local data_basepath_slash = 'usercontent/'

local status_colors = {
    [color_statuses.default] = 0xffffffff,
    [color_statuses.disabled] = 0xffbbbbbb,
    [color_statuses.finished] = 0xffffffff,
    [color_statuses.error] = 0xff6666ff,
    [color_statuses.danger] = 0xff0099ff,
    [color_statuses.warning] = 0xffbbbbff,
    [color_statuses.info] = 0xffffaaaa,
    [color_statuses.note] = 0xff888888,
    [color_statuses.success] = 0xffaaffaa,
}

--- @alias ContentFileType 'enum'|'dump'|'preset'|'bundle'

--- @param color_name 'default'|'disabled'|'finished'|'error'|'danger'|'warning'|'info'|'note'|'success'
--- @return integer
local function get_color(color_name)
    return status_colors[color_statuses[color_name]]
end

--- @param subpath string
--- @return string
local function get_path(subpath)
    if subpath:sub(1, 1) == '/'  then
        return data_basepath_slash .. subpath:sub(2)
    else
        return data_basepath_slash .. subpath
    end
end

--- @param type ContentFileType|string
--- @return string
local function get_folder_name(type)
    if type == 'enum' then return 'enums' end
    if type == 'dump' then return 'dumps' end
    if type == 'preset' then return 'presets' end
    if type == 'bundle' then return 'bundles' end
    return type
end

--- @param type ContentFileType
--- @param subpath string
--- @return string
local function resolve_file(type, subpath)
    if type == 'enum' then return get_path('enums/' .. subpath .. '.json') end
    if type == 'dump' then return get_path('dumps/' .. subpath .. os.date('_%Y-%m-%d %H-%M-%S.json')) end
    if type == 'preset' then return get_path('presets/' .. subpath .. '.json') end
    if type == 'bundle' then return get_path('bundles/' .. subpath .. '.json') end
    return get_path(subpath)
end

local globCache = nil

--- @param type ContentFileType|string
--- @param forceRescan boolean|nil
--- @return string[]
local function get_files(type, forceRescan)
    if forceRescan or not globCache then
        globCache = {}
        local files = fs.glob(data_basepath .. '\\\\.*?\\.json$')
        for _, f in ipairs(files) do
            local mainPath = f:match('^' .. data_basepath .. '[\\/][^\\/]+')
            if mainPath then
                mainPath = mainPath:gsub('^' .. data_basepath .. '[\\/]', '')
                globCache[mainPath] = globCache[mainPath] or {}
                globCache[mainPath][#globCache[mainPath]+1] = f
            end
        end
    end
    local folder_name = get_folder_name(type)
    return globCache[folder_name] or {}
end

--- @class UserdataConfig
--- @field bundle_order string[]
--- @field bundle_settings table<string, UserdataConfig.BundleSettings>
--- @field editor _UserdataConfig.EditorSettings

--- @class _UserdataConfig.EditorSettings
--- @field enabled boolean
--- @field show_window boolean
--- @field selected_editor_tab_index number
--- @field author_name string
--- @field devmode boolean|nil
--- @field disable_unknown_entity_alerts boolean|nil
--- @field show_prop_labels boolean|nil
--- @field author_description string|nil
--- @field active_bundle string|nil
--- @field next_editor_id integer
--- @field tabs table<string, EditorState>
--- @field windows EditorState[]
--- @field language string
--- @field storage nil|table<string, any>

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
        active_bundle = nil,
        tabs = {},
        windows = {},
        storage = {},
        next_editor_id = 1,
        show_prop_labels = false,
        language = 'en',
    },
    bundle_order = {},
    bundle_settings = {},
}

local function load_config()
    local f = json.load_file(get_path('editor_settings.json'))
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

        usercontent.__internal.emit('_loadConfig', config)
    end
end

local function save_config()
    json.dump_file(get_path('editor_settings.json'), config)
end

load_config()

local version = {0, 0, 0}

local isDebug = nil
local function log_debug(...)
    if isDebug == nil then
        if usercontent.__internal then
            isDebug = usercontent.__internal.config.data.editor.devmode == true
        else
            return
        end
    end
    if not isDebug then return end
    print('[DEBUG] Content editor:', ...)
    log.info('[DEBUG] Content editor: ' .. table.concat({...}, '\t'))
end

--- @class ContentEditorCore
usercontent.core = {
    --- Active mod version {major, minor, patch}
    VERSION = version,
    --- Active mod version string
    VERSION_STR = table.concat(version, '.'),
    --- Basic game specific info and hooks
    game = {}--[[@as any]], ---@type ContentEditorGameController
    --- Base content db path
    _basepath = data_basepath,
    --- Get a color preset
    get_color = get_color,
    --- Get a file relative to the mod base path
    get_path = get_path,
    --- Resolve the path to a specific content db file type
    resolve_file = resolve_file,
    --- Get a list of files within a content editor folder
    get_files = get_files,
    --- Whether the content editor part of the mod is enabled and loaded
    editor_enabled = config.editor.enabled,
    --- Log a message to both console and log file if content editor debug mode is enabled
    log_debug = log_debug,
}

usercontent.__internal.config = {
    data = config,
    save = save_config,
    load = load_config,
    _get_next_editor_id = function ()
        local id = config.editor.next_editor_id
        config.editor.next_editor_id = id + 1
        return id
    end
}

require('content_editor.utils')
--- Basic game specifics
usercontent.core.game = require('content_editor.setup')
return usercontent.core
