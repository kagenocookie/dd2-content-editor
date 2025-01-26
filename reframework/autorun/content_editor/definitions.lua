if type(usercontent) == 'nil' then usercontent = {} end
if usercontent.definitions then return usercontent.definitions end

local core = require('content_editor.core')
local common = require('content_editor.ui.common')

--- @type table<string, UserdataEditorSettings>
local type_settings = {
    -- this one seems to have some magic that auto converts the via.GameObjectRef to a `nil|via.GameObject`
    -- not sure how we can edit this but it's probably a runtime entity that gets set automatically anyway
    ['via.GameObjectRef'] = {
        uiHandler = common.readonly_label(),
    },
    ['via.gui.PlayObject'] = {
        propOrder = {'Visible', 'Name', 'Parent', 'Child', 'Next', 'Component', 'GameObject'},
        abstract = {
            'via.gui.BlurFilter',
            'via.gui.Capture',
            'via.gui.Circle',
            'via.gui.Control',
            'via.gui.DebugRect',
            'via.gui.DebugText',
            'via.gui.Effect',
            'via.gui.Effect2D',
            'via.gui.Effect2DTexture',
            'via.gui.EventTrigger',
            'via.gui.FluentScrollBar',
            'via.gui.FluentScrollGrid',
            'via.gui.FluentScrollList',
            'via.gui.FreePolygon',
            'via.gui.HitArea',
            'via.gui.ImageFilter',
            'via.gui.ItemsControlLink',
            'via.gui.Line',
            'via.gui.Material',
            'via.gui.MaterialText',
            'via.gui.Mesh',
            'via.gui.NumberSelection',
            'via.gui.OverlayUITexture',
            'via.gui.Panel',
            'via.gui.ParamSetter',
            'via.gui.Rect',
            'via.gui.Scale9Grid',
            'via.gui.Scale9GridV2',
            'via.gui.ScrollBar',
            'via.gui.ScrollGrid',
            'via.gui.ScrollList',
            'via.gui.SelectItem',
            'via.gui.SimpleList',
            'via.gui.SpriteSet',
            'via.gui.Svg',
            'via.gui.Text',
            'via.gui.Texture',
            'via.gui.TextureSet',
            'via.gui.View',
            'via.gui.Window',
        },
    },
}

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
        usercontent.definitions._hash = table.concat(overrides, ' ')
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
--- @param settings UserdataEditorSettings|fun(settings: UserdataEditorSettings, classname: string) Either a direct object or a function that modifies the object. A function would generally be the better choice because otherwise any object instances are shared between all the overridden types.
local function add_type_overrides_specific(classnames, settings)
    if type(settings) == 'function' then
        for _, cls in ipairs(classnames) do
            local defs = type_settings[cls]
            if defs == nil then
                defs = {}
                type_settings[cls] = defs
            end

            settings(defs, cls)
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
--- @param settings UserdataEditorSettings|fun(settings: UserdataEditorSettings, classname: string) Either a direct object or a function that modifies the object. A function would generally be the better choice because otherwise any object instances are shared between all the overridden types.
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

local rszPath = 'usercontent/rsz/' .. reframework.get_game_name() .. '.json'
local rszTypes = json.load_file(rszPath)
if rszTypes then
    add_type_overrides('', rszTypes)
end

if core.editor_enabled then
    add_type_overrides('', {
        ['via.GameObject'] = {
            force_expander = true,
        },
        ['via.UserData'] = {
            toString = function (value, context)
                return (context and context.data.classname or value:get_type_definition():get_full_name()) .. ': ' .. (value.get_Path and value:get_Path() or tostring(value))
            end
        },
        ['via.Quaternion'] = {
            force_expander = false,
        },
        ['via.Float4'] = {
            force_expander = false,
        },
        ['via.vec4'] = {
            force_expander = false,
        },
        ['via.Size'] = {
            uiHandler = common.vec_n({'w', 'h'}, imgui.drag_float2, function() return Vector2f.new(0, 0) end),
        },
    })
    add_type_overrides_abstract('via.gui.PlayObject', function (settings, classname)
        if not settings.toString then
            settings.toString = function (value, context)
                return value:get_Name() .. '     | ' .. classname
            end
        end
    end)
end

usercontent.definitions = {
    type_settings = type_settings,
    override = add_type_overrides,
    override_specific = add_type_overrides_specific,
    override_abstract = add_type_overrides_abstract,
    merge_type_override = merge_type_override,
    get = get_type_overrides,
    _hash = '',
}
return usercontent.definitions