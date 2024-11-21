if type(_userdata_DB) == 'nil' then _userdata_DB = {} end
if _userdata_DB.core then return _userdata_DB.core end

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

local data_basepath = 'usercontent/'

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

--- @param color_name 'default'|'disabled'|'finished'|'error'|'danger'|'warning'|'info'|'success'
--- @return integer
local function get_color(color_name)
    return status_colors[color_statuses[color_name]]
end

--- @param subpath string
--- @return string
local function get_path(subpath)
    if subpath:sub(1, 1) == '/'  then
        return data_basepath .. subpath:sub(2)
    else
        return data_basepath .. subpath
    end
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

--- @param type ContentFileType
--- @return string
local function get_glob_regex(type)
    local path = resolve_file(type, '.*?\\')
    path = path:gsub('/', '\\\\')
    return path
end

local version = {0, 5, 0}

--- @class ContentEditorCore
_userdata_DB.core = {
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
    --- Generate a regex for an fs.glob call of everything within a file type's folder
    get_glob_regex = get_glob_regex,
    --- Whether the content editor part of the mod is enabled and loaded
    editor_enabled = false,
}

require('content_editor.utils')
--- Basic game specifics
_userdata_DB.core.game = require('content_editor.setup')
return _userdata_DB.core
