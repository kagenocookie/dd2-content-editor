if type(usercontent) == 'nil' then usercontent = {} end
if usercontent.__internal and usercontent.__internal.presets then return usercontent.__internal.presets end

local core = require('content_editor.core')
local utils = require('content_editor.utils')

--- @class DataObjectPreset
--- @field name string
--- @field data table

--- @type table<string, DataObjectPreset[]>
local presets_by_type = {}
--- @type table<string, string[]>
local preset_names_by_type = {}

local function define_preset(type, name, data)
    local pbt = presets_by_type[type]
    if pbt == nil then
        pbt = {}
        presets_by_type[type] = pbt
    end
    pbt[#pbt+1] = {
        name = name,
        data = data,
    }

    local names = preset_names_by_type[type]
    if not names then
        names = {}
        preset_names_by_type[type] = names
    end
    names[#names+1] = name
end

local function refresh_available_presets()
    local files = core.get_files('preset')
    for _, presetPath in ipairs(files) do
        local newPreset = json.load_file(presetPath)
        if newPreset and type(newPreset) == 'table' then
            local type = presetPath:match('presets\\([^\\]+)')
            local name = presetPath:match(tostring(type) .. '\\([^\\]+).json$')
            if not type or not name or type == '' or name == '' then
                print('WARNING: invalid preset path ', presetPath, type, name)
            else
                define_preset(type, name, newPreset)
                -- print('adding new preset', type, name, newPreset)
            end
        end
    end
end

--- @return string[]
local function get_preset_names(type)
    if not next(preset_names_by_type) then refresh_available_presets() end
    local names = {}
    for k, v in pairs(preset_names_by_type[type] or {}) do
        names[#names+1] = v
    end
    return names
end

--- @return DataObjectPreset[]
local function get_preset_list(type)
    if not next(preset_names_by_type) then refresh_available_presets() end
    return presets_by_type[type] or {}
end

local function get_preset_data(type, name)
    if not next(preset_names_by_type) then refresh_available_presets() end
    local names = preset_names_by_type[type]
    if not names then return nil end

    local idx = utils.table_index_of(names, name)
    if idx == 0 then return nil end

    return presets_by_type[type][idx].data
end

usercontent.__internal.presets = {
    refresh = refresh_available_presets,
    get_names = get_preset_names,
    get_presets = get_preset_list,
    get_preset_data = get_preset_data,
}
return usercontent.__internal.presets
