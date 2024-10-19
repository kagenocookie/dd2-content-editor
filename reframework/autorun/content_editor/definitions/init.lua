if type(_userdata_DB) == 'nil' then _userdata_DB = {} end
if _userdata_DB._definitions then return _userdata_DB._definitions end

--- @type table<string, UserdataEditorSettings>
local type_settings = require('content_editor.definitions.' .. reframework.get_game_name())

local function merge_table(target, src)
    for key, val in pairs(src) do
        target[key] = val
    end
end

--- @param sourceOverride UserdataEditorSettings
--- @param targetOverride UserdataEditorSettings
--- @return UserdataEditorSettings
local function merge_type_override(sourceOverride, targetOverride)
    if not targetOverride then
        targetOverride = {}
    end

    for settingName, settingValue in pairs(sourceOverride) do
        if settingName == 'fields' and targetOverride[settingName] then
            merge_table(targetOverride[settingName], settingValue)
        else
            targetOverride[settingName] = settingValue
        end
    end
    return targetOverride
end

local overrides = {}
--- Add additional type overrides for UI and importing logic.
--- A change of the `override_id` will automatically trigger a full re-generation of the type cache,
--- useful for whenever you change the definitions, by naming it e.g. quest1, quest2, ... for each new version.
--- Pass in an empty string if no typecache-affecting settings will be defined, so we don't trigger a typecache rebuild.
--- @param overrides_id string A unique ID to identify the override provider and version.
--- @param settings table<string, UserdataEditorSettings>
local function add_type_overrides(overrides_id, settings)
    if type(overrides_id) == 'string' and overrides_id ~= '' then
        overrides[#overrides+1] = overrides_id
        table.sort(overrides)
        _userdata_DB._definitions._hash = table.concat(overrides, ' ')
    end

    for containerClass, classSettings in pairs(settings) do
        local ts = type_settings[containerClass]
        if not ts then
            ts = {}
            type_settings[containerClass] = ts
        end
        merge_type_override(classSettings, ts)
    end
end

--- Apply the same set of overrides to multiple classes
--- @param classnames string[]
--- @param settings UserdataEditorSettings|fun(settings: UserdataEditorSettings) Either a direct object or a function that modifies the object. A function would generally be the better choice because otherwise any object instances are shared between all the overridden types.
local function add_type_overrides_specific(classnames, settings)
    if type(settings) == 'function' then
        for _, cls in ipairs(classnames) do
            local defs = type_settings[cls]
            if defs == nil then
                defs = {}
                type_settings[cls] = defs
            end

            settings(defs)
        end
    else
        local list = {}
        for _, cls in ipairs(classnames) do
            list[cls] = settings
        end
        add_type_overrides('', list)
    end
end

--- Apply an override to all abstract subtypes of a given class
--- @param classname string
--- @param settings UserdataEditorSettings|fun(settings: UserdataEditorSettings) Either a direct object or a function that modifies the object. A function would generally be the better choice because otherwise any object instances are shared between all the overridden types.
local function add_type_overrides_abstract(classname, settings)
    local classnames = type_settings[classname].abstract or {}
    add_type_overrides_specific(classnames, settings)
end

--- Get all the defined overrides for a type. Note that there is no inheritance for the values returned here.
--- @param type string
--- @return UserdataEditorSettings
local function get_type_overrides(type)
    return type_settings[type] or {}
end

_userdata_DB._definitions = {
    type_settings = type_settings,
    override = add_type_overrides,
    override_specific = add_type_overrides_specific,
    override_abstract = add_type_overrides_abstract,
    merge_type_override = merge_type_override,
    get = get_type_overrides,
    _hash = '',
}
return _userdata_DB._definitions