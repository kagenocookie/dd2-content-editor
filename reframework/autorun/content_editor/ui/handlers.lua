if type(_userdata_DB) == 'nil' then _userdata_DB = {} end
if _userdata_DB._ui_handlers then return _userdata_DB._ui_handlers end

local core = require('content_editor.core')
local utils = require('content_editor.utils')
local enums = require('content_editor.enums')
local ui = require('content_editor.ui.imgui_wrappers')
local helpers = require('content_editor.helpers')
local common = require('content_editor.ui.common')
local udb = require('content_editor.database')
local ui_context = require('content_editor.ui.context')

local type_settings = require('content_editor.definitions')
local typecache = require('content_editor.typecache')

local defines = {
    array_expand_minimum_fields = 3,
    object_expand_minimum_fields = 4,
}

--- @alias UIHandler fun(context: UIContainer): changed: boolean Receives the handled element's UI Context
--- @alias UIHandlerFactory fun(meta: TypeCacheData, classname: string, label: string, settings: UISettings): UIHandler

--- @class UISettings
--- @field hide_nonserialized boolean
--- @field is_raw_data boolean
--- @field is_readonly boolean|nil

--- @type table<string, UIHandler>
local object_handlers = {
    ['System.String'] = common.string
}

--- @type table<string, UIHandler>
local value_type_handler_defs = {
    ["System.UInt32"] = common.int(1, 0, 4294967295),
    ["System.Int32"] = common.int(1, -2147483648, 2147483647),
    ["System.UInt64"] = common.int(1, 0, 18446744073709551616),
    ["System.Int64"] = common.int(1, -9223372036854775808, 9223372036854775807),
    ["System.UInt16"] = common.int(1, 0, 65535),
    ["System.Int16"] = common.int(1, -32767, 32767),
    ["System.Byte"] = common.int(0.1, 0, 255),
    ["System.SByte"] = common.int(0.1, -128, 127),
    ["System.Boolean"] = common.bool,
    ["System.Single"] = common.float(1, -9999999999, 9999999999),
    ["System.Double"] = common.float(1, -9999999999, 9999999999),
    ['via.vec2'] = common.vec2,
    ['via.vec3'] = common.vec3,
    ['via.vec4'] = common.vec4,
    ['via.Int2'] = common.vec2_int,
    ['via.Uint3'] = common.vec3_int,
    ['via.Float2'] = common.vec2,
    ['via.Float3'] = common.vec3,
    ['via.Float4'] = common.vec4,
    ['via.Color'] = common.color,
    ['via.Position'] = common.vec3,
    ['via.Quaternion'] = common.vec4,
}

local newGuidMethod = sdk.find_type_definition('System.Guid'):get_method('NewGuid')
value_type_handler_defs['System.Guid'] = function (ctx)
    local value = ctx.get()
    if value == nil then
        imgui.text(ctx.label .. ' nil guid (may not be properly work if GameObjectRef) ' .. ui_context.get_absolute_path(ctx))
        if imgui.button('Try creating empty') then
            value = '00000000-0000-0000-0000-000000000000'
            ctx.set(value)
        end
        return false
    end
    local isRaw = type(value) == 'nil' or type(value) == 'string'

    local w = imgui.calc_item_width()
    imgui.set_next_item_width(50)
    local randomized = false
    if imgui.button('Random') then
        if isRaw then
            value = newGuidMethod:call(nil):ToString()
        else
            value.mData1 = math.random(0, 4294967296)
            value.mData2 = math.random(0, 65535)
            value.mData3 = math.random(0, 65535)
            value.mData4_0 = math.random(0, 255)
            value.mData4_1 = math.random(0, 255)
            value.mData4_2 = math.random(0, 255)
            value.mData4_3 = math.random(0, 255)
            value.mData4_4 = math.random(0, 255)
            value.mData4_5 = math.random(0, 255)
            value.mData4_6 = math.random(0, 255)
            value.mData4_7 = math.random(0, 255)
        end
        ctx.set(value)
        randomized = true
    end
    imgui.same_line()
    imgui.set_next_item_width(w - 66)
    local changed, newGuidStr = imgui.input_text(ctx.label, helpers.to_string(value))
    if changed then
        local valid, newGuid = utils.guid_try_parse(newGuidStr)
        if valid then
            if isRaw then
                value = newGuidStr
            else
                -- note: we can't directly set the new guid, need to copy the backing fields instead
                value.mData1 = newGuid.mData1
                value.mData2 = newGuid.mData2
                value.mData3 = newGuid.mData3
                value.mData4L = newGuid.mData4L
            end
            ctx.set(value)
            return true
        else
            imgui.text_colored('Invalid GUID', core.get_color('error'))
        end
    end
    return changed or randomized
end

-- --- @type ObjectFieldAccessors
local default_accessor = {
    get = function (object, fieldname)
        if object ~= nil then return object[fieldname]
        else return nil end
    end,
    set = function (object, value, fieldname) object[fieldname] = value end,
}

--- @type ObjectFieldAccessors
local boxed_value_accessor = {
    get = function (object, fieldname) return object[fieldname].m_value end,
    set = function (object, value, fieldname) object[fieldname] = value end
}

--- @type ObjectFieldAccessors
local boxed_enum_accessor = {
    get = function (object, fieldname) return object[fieldname].value__ end,
    set = function (object, value, fieldname) object[fieldname] = value end
}

--- @type ObjectFieldAccessors
local getter_prop_accessor = {
    get = function (object, propName) return object:call('get_' .. propName) end,
    set = function (object, value, fieldname) print('WARNING: Attempted to set read-only prop', object, fieldname, value) end
}

--- @param label string
--- @return string
local function generate_field_label(label)
    if label:sub(1,1) == '_' then label = label:sub(2) end
    if label:sub(1,1) == '<' then
        local name = label:match('<([a-zA-Z0-9_]+)>k__BackingField')
        if name then
            return name .. '/Prop'
        end
    end
    return label
end

--- @param label string
--- @param parentLabel string
--- @return string
local function format_field_label(label, parentLabel)
    return label:gsub('$PARENT', parentLabel) or label
end

--- @param wrappedHandler UIHandler
--- @return UIHandler
local expandable_ui = function (wrappedHandler)
    --- @type UIHandler
    return function (context)
        local extraLabel = helpers.context_to_string(context)
        if ui.treenode_suffix(context.label, extraLabel) then
            local res = wrappedHandler(context)
            imgui.tree_pop()
            return res
        else
            ui_context.delete_children(context)
        end
        return false
    end
end

--- @type table<string, fun(handler: UIHandler, data: FieldExtension): UIHandler>
local ui_extensions = {}

--- @param type string
--- @param handler fun(handler: UIHandler, data: FieldExtension|table): UIHandler
local function register_extension(type, handler)
    ui_extensions[type] = handler
end

--- @param type string Alias name
--- @param targetType string Extension to alias for
--- @param data any Additional data overrides
local function register_extension_alias(type, targetType, data)
    ui_extensions[type] = function (handler, overrideData)
        local ext = ui_extensions[targetType]
        return ext(handler, utils.table_assign(data, overrideData))
    end
end

require('content_editor.ui._extensions')(register_extension)

register_extension('expandable', expandable_ui)

local create_field_editor

--- @param handler UIHandler
--- @param containerClass string
--- @param field string|integer
--- @param fieldClass string
--- @return UIHandler
local function apply_ui_handler_overrides(handler, containerClass, field, fieldClass)
    local typesettings = type_settings.type_settings[containerClass]
    local fieldOverrides = typesettings and typesettings.fields and typesettings.fields[field] or {}
    local fieldTypeOverrides = field ~= '__element' and type_settings.type_settings[fieldClass]

    if fieldOverrides and fieldOverrides.uiHandler then
        handler = fieldOverrides.uiHandler
    elseif fieldTypeOverrides and fieldTypeOverrides.uiHandler then
        handler = fieldTypeOverrides.uiHandler
    end
    --- @cast handler -nil

    for _, extData in ipairs(fieldTypeOverrides and fieldTypeOverrides.extensions or {}) do
        local ext = ui_extensions[extData.type]
        if ext then
            handler = ext(handler, extData)
        else
            print('WARNING: unknown UI extension ', extData.type)
        end
    end

    for _, extData in ipairs(fieldOverrides.extensions or {}) do
        local ext = ui_extensions[extData.type]
        if ext then
            handler = ext(handler, extData)
        else
            print('WARNING: unknown UI extension ', extData.type)
        end
    end

    return handler
end

--- @param meta TypeCacheData
--- @param classname string
--- @param label string
--- @param array_access ArrayLikeAccessors
--- @param settings UISettings
local function create_arraylike_ui(meta, classname, label, array_access, settings)
    -- print('generating new array UIHandler', classname)
    local typesettings = type_settings.type_settings[classname]
    local expand_per_element = typesettings and typesettings.force_expander
    if expand_per_element == nil then
        local elementMeta = typecache.get(meta.elementType)
        expand_per_element = elementMeta.type ~= typecache.handlerTypes.enum and elementMeta.itemCount >= defines.array_expand_minimum_fields
    end
    local skip_root_tree_node = typesettings and typesettings.array_expander_disable or false
    if not meta.elementType then error('INVALID ARRAY: ' .. classname) return function () end end
    local elementAccessor = default_accessor
    if not settings.is_raw_data and meta.type == typecache.handlerTypes.array then
        local elementMeta = typecache.get(meta.elementType)
        if elementMeta.type == typecache.handlerTypes.value then
            elementAccessor = boxed_value_accessor
        elseif elementMeta.type == typecache.handlerTypes.enum then
            elementAccessor = boxed_enum_accessor
        end
    end

    --- @type UIHandler
    return function (context)
        local array = context.get()
        if array ~= context.object then
            -- if the instance was changed externally for whatever reason, update the cached instance
            context.object = array
        end
        if array == nil or array == 'null' then
            imgui.text(label .. ': null')
            imgui.same_line()
            imgui.text_colored(classname, core.get_color('info'))
            if imgui.button('Create') then
                array = settings.is_raw_data and {} or (array_access.create or helpers.create_instance)(classname)
                context.set(array)
                return true
            end
            return false
        end

        local changed = false
        local labelSuffix = '(' .. array_access.length(array) .. ')   ' .. helpers.to_string(array, classname)
        local show
        if skip_root_tree_node then
            show = true
            imgui.text(label)
            imgui.same_line()
            imgui.text_colored(labelSuffix, 0xffcccccc)
        else
            show = ui.treenode_suffix(label, labelSuffix)
        end
        if show then
            imgui.push_id(array.get_address and array:get_address() or tostring(array))
            for idx, element in pairs(array_access.get_elements(array)) do
                if element == nil then goto continue end
                imgui.begin_rect()
                imgui.push_id(idx)
                if imgui.button('X') then
                    -- delete all child element containers and re-create them next iteration, that's the easiest way of ensuring we don't mess up the children index keys
                    ui_context.delete_children(context)
                    context.set(array_access.remove_at(array, idx))
                    imgui.tree_pop()
                    return true
                end

                imgui.same_line()
                local isNewChildCtx = context.children[idx] == nil
                local childCtx = create_field_editor(context, classname, idx, meta.elementType, tostring(idx), elementAccessor, settings, not expand_per_element)
                if isNewChildCtx then
                    childCtx.ui = apply_ui_handler_overrides(childCtx.ui, classname, "__element", meta.elementType)
                end

                local childChanged = childCtx.ui(childCtx)
                changed = childChanged or changed

                imgui.pop_id()
                imgui.end_rect(1)
                ::continue::
            end
            imgui.pop_id()

            if array_access.add and imgui.button('Add') then
                local newElement = settings.is_raw_data and {} or helpers.create_instance(meta.elementType)
                array = array_access.add(array, newElement, classname)
                context.set(array)
                ui_context.delete_children(context)
                changed = true
            end

            if not skip_root_tree_node then imgui.tree_pop() end
        else
            ui_context.delete_children(context)
        end

        return changed
    end
end

--- @type table<HandlerType, UIHandlerFactory>
local field_editor_factories

--- @type table<HandlerType, UIHandlerFactory>
field_editor_factories = {
    [typecache.handlerTypes.enum] = function (meta, classname)
        return common.enum(enums.get_enum(classname))
    end,
    [typecache.handlerTypes.value] = function (meta, classname, label, settings)
        local predefined = value_type_handler_defs[classname]
        if predefined then
            return predefined
        end

        local typesettings = type_settings.type_settings[classname] or {}
        local fieldSettings = typesettings.fields or {}

        --- @type [string, string, FieldFlags, string, ObjectFieldAccessors ][]
        local fields = {}
        for _, subfield in ipairs(meta.fields) do
            local flags = subfield[3]
            if (flags & typecache.fieldFlags.UIEnable) ~= 0 then
                local name = subfield[1]
                local type = subfield[2]
                local overrides = fieldSettings[name]
                local sublabel = format_field_label(overrides and overrides.label or generate_field_label(name), label)
                fields[#fields+1] = { name, type, flags, sublabel, overrides and overrides.accessors or default_accessor }
            end
        end

        -- complex value type
        --- @type UIHandler
        return function (context)
            local value = context.get()
            context.object = value

            for _, subfieldData in ipairs(fields) do
                local subfield = subfieldData[1]
                local subtype = subfieldData[2]
                local flags = subfieldData[3]
                local sublabel = subfieldData[4]
                local access = subfieldData[5]
                local childCtx = create_field_editor(context, classname, subfield, subtype, sublabel, access, settings)

                local isReadonly = (flags & typecache.fieldFlags.ImportEnable) == 0

                local childChanged = childCtx.ui(childCtx)

                if not isReadonly and childChanged then
                    changed = true
                    -- need to reassign over the original struct on any change since value types
                    context.set(value)
                end
            end
            return changed
        end
    end,
    [typecache.handlerTypes.object] = function (meta, classname, label, settings)
        -- print('generating new object UIHandler', container:get_type_definition():get_full_name(), classname)
        if object_handlers[classname] then
            return object_handlers[classname]
        end

        local typesettings = type_settings.type_settings[classname] or {}
        if typesettings.abstract then
            local defaultClass = typesettings.abstract_default or typesettings.abstract[1]
            --- @type UIHandler
            return function (context)
                local value = context.get()
                if value ~= context.object then
                    -- if the instance was changed externally for whatever reason, update the cached instance
                    context.object = value
                end
                if value == nil then
                    imgui.text(context.label .. ': NULL')
                    imgui.same_line()
                    if imgui.button('Create') then
                        value = helpers.create_instance(defaultClass, settings.is_raw_data)
                        context.set(value)
                        return true
                    else
                        return false
                    end
                end

                local previousType = helpers.get_type(value)

                local changed = false
                local newType
                changed, newType, context.data.abstract_filter = ui.combo_filterable('Classname', previousType, typesettings.abstract, context.data.abstract_filter)
                local concreteType = newType or defaultClass
                if changed and newType ~= previousType then
                    ui_context.delete_children(context)
                    context.set(helpers.create_instance(concreteType, settings.is_raw_data))
                    context.data.ui = nil
                end

                if not context.data.ui then
                    local submeta = typecache.get(concreteType)
                    context.data.ui = field_editor_factories[submeta.type](submeta, concreteType, label, settings)
                    context.data.ui = apply_ui_handler_overrides(context.data.ui, context.parent.data.classname, context.field, concreteType)
                end

                return context.data.ui(context) or changed
            end
        else
            local fieldSettings = typesettings.fields or {}

            --- @type [string, string, FieldFlags, string, ObjectFieldAccessors ][]
            local fields = {}
            for _, subfield in ipairs(meta.fields or {}) do
                local flags = subfield[3]
                if (flags & typecache.fieldFlags.UIEnable) ~= 0 then
                    local name = subfield[1]
                    local type = subfield[2]
                    local overrides = fieldSettings[name]
                    local sublabel = format_field_label(overrides and overrides.label or generate_field_label(name), label)
                    fields[#fields+1] = { name, type, flags, sublabel, overrides and overrides.accessors or default_accessor }
                end
            end

            --- @type UIHandler
            return function (context)
                local value = context.get()
                if value ~= context.object then
                    -- if the instance was changed externally for whatever reason, update the cached instance
                    context.object = value
                end
                local changed = false
                if value == nil or value == 'null' then
                    imgui.text(label .. ': NULL')
                    imgui.same_line()
                    if imgui.button('Create') then
                        value = settings.is_raw_data and {} or helpers.create_instance(classname)
                        context.set(value)
                        context.object = value
                        changed = true
                    else
                        return false
                    end
                end

                for fieldIdx, subfieldData in ipairs(fields) do
                    local subfield = subfieldData[1]
                    local subtype = subfieldData[2]
                    local flags = subfieldData[3]
                    local sublabel = subfieldData[4]
                    local access = settings.hide_nonserialized and default_accessor or subfieldData[5]

                    local childCtx = create_field_editor(context, classname, subfield, subtype, sublabel, access, settings)

                    local nonSerialized = (flags & typecache.fieldFlags.ImportEnable) == 0
                    if settings.hide_nonserialized and nonSerialized then
                        goto continue
                    end

                    imgui.push_id(fieldIdx)
                    if nonSerialized then
                        imgui.indent(-14)
                        imgui.text_colored("*", core.get_color('info'))
                        if imgui.is_item_hovered() then
                            imgui.set_tooltip('Field is not serialized\nUsually this means the data is used only during runtime and managed automatically by the game, or the mod automatically handles it for you.')
                        end
                        imgui.same_line()
                        imgui.push_style_color(0, 0xffdddddd)
                    end
                    local childChanged = childCtx.ui(childCtx)
                    imgui.pop_id()

                    if nonSerialized then
                        imgui.pop_style_color(1)
                        imgui.unindent(-14)
                    else
                        changed = childChanged or changed
                    end
                    ::continue::
                end
                return changed
            end
        end
    end,
    [typecache.handlerTypes.array] = function (meta, classname, label, settings)
        local accessor = settings.is_raw_data and helpers.array_accessor('table') or helpers.array_accessor(classname) --[[@as ArrayLikeAccessors]]
        return create_arraylike_ui(meta, classname, label, accessor, settings)
    end,
    [typecache.handlerTypes.genericList] = function (meta, classname, label, settings)
        local accessor = settings.is_raw_data and helpers.array_accessor('table') or helpers.array_accessor(classname) --[[@as ArrayLikeAccessors]]
        return create_arraylike_ui(meta, classname, label, accessor, settings)
    end,
    [typecache.handlerTypes.nullableValue] = function (meta, classname, label, settings)
        --- @type UIHandler
        local handler = function (context)
            local childCtx = create_field_editor(context, classname, '_Value', meta.elementType, 'Value', default_accessor, settings)
            return childCtx.ui(childCtx)
        end
        return common.nullable_valuetype(meta.elementType, handler)
    end,
    [typecache.handlerTypes.readonly] = function ()
        return function (context)
            imgui.text(context.label .. ': ' .. helpers.context_to_string(context) .. ' (*readonly)')
            return false
        end
    end,
}

--- @param parentContext UIContainer
--- @param containerClass string
--- @param field string|integer
--- @param fieldClass string
--- @param label string
--- @param accessors ObjectFieldAccessors|nil
--- @param settings UISettings
--- @param no_expander boolean|nil
--- @return UIContainer
create_field_editor = function(parentContext, containerClass, field, fieldClass, label, accessors, settings, no_expander)
    local ctx = ui_context.get_child(parentContext, field)
    if ctx then
        return ctx
    end

    -- print('Creating new field editor', parentContext, containerClass, field, fieldClass, label, accessors)

    local typesettings = type_settings.type_settings[containerClass] or {}
    local fieldOverrides = typesettings.fields and typesettings.fields[field] or {}
    if not accessors then
        -- for full interchangeability between raw lua table data and REManagedObjects
        if settings.is_raw_data then
            accessors = default_accessor
        else
            accessors = fieldOverrides.accessors or default_accessor
        end
    end

    local submeta = typecache.get(fieldClass)
    local doExpander = false
    if not no_expander and (submeta.type == typecache.handlerTypes.object or submeta.type == typecache.handlerTypes.value) then
        local expanderOverride = fieldOverrides.force_expander
        if expanderOverride == nil then expanderOverride = type_settings.type_settings[fieldClass] and type_settings.type_settings[fieldClass].force_expander end
        if expanderOverride == true or expanderOverride ~= false and submeta.itemCount >= defines.object_expand_minimum_fields then
            doExpander = true
        end
    end

    -- this condition here is kinda hacky but uh, can't really think of better solutions right now
    if not doExpander
        and parentContext.label and parentContext.label ~= '' and parentContext.object ~= parentContext.owner
        and not parentContext.data._has_extra_expander
        and parentContext.data.classname and not helpers.is_arraylike(parentContext) and not helpers.is_arraylike(parentContext.parent) then
        label = parentContext.label .. '.' .. label
    end

    local handler = field_editor_factories[submeta.type](submeta, fieldClass, label, settings)
    handler = apply_ui_handler_overrides(handler, containerClass, field, fieldClass)

    ctx = ui_context.create_child(parentContext, field, accessors.get(parentContext.object, field), label, accessors, fieldClass)

    if doExpander then
        ctx.data._has_extra_expander = true
        handler = expandable_ui(handler)
    end
    ctx.ui = handler
    return ctx
end

-- --- @param obj any
-- --- @param label string
-- --- @param classname string
-- --- @return UIContainer
-- local function create_editor(obj, label, classname)
--     local ctx = ui_context.get_root(obj) or ui_context.create(obj, obj, label, default_accessor)
--     return get_or_create_field_editor_and_context(ctx, classname, '__', classname, label, {
--         get = function(object) return object end,
--         set = function() error('Root editor setter unsupported') end,
--     })
-- end

--- @type table<string, UIContainer>
local root_uis = {}

--- @param target any
--- @param owner DBEntity|nil
--- @param label string|nil
--- @param classname string|nil
--- @param editorId any A key by which to identify this editor. If unspecified, the target object's address will be used.
--- @param accessors ObjectFieldAccessors
--- @param uiSettingOverrides UISettings|nil
local function show_entity_ui_internal(target, owner, label, classname, editorId, accessors, uiSettingOverrides)
    if not target then error('OI! ui needs a target and a parent!') end
    if not classname then
        if target.get_type_definition then
            classname = target:get_type_definition():get_full_name()
        else
            imgui.text_colored('Invalid entity for display: ' .. tostring(target), core.get_color('error'))
            return nil
        end
    end
    if not editorId then
        editorId = target:get_address()
    elseif type(editorId) == 'table' then
        editorId['_id' .. label] = editorId['_id' .. label] or math.random(1, 1000000)
        editorId = editorId['_id' .. label]
    end

    imgui.push_id(editorId)
    --- @type UIContainer|nil
    local rootContext = root_uis[editorId] or ui_context.get_root(editorId)
    if not rootContext then
        rootContext = ui_context.create(target, owner, label or '', editorId)
        --- @type UISettings
        rootContext.data.ui_settings = utils.table_assign({
            is_raw_data = type(target) == 'table',
            hide_nonserialized = type(target) == 'table',
        }, uiSettingOverrides or {})
        rootContext.data._has_extra_expander = true
        rootContext.object = target
        root_uis[editorId] = rootContext
    end

    if rootContext.object ~= target then
        print('root context instance changed', target, rootContext.object)
        root_uis[editorId] = nil
        -- ui_context.delete(rootContext)
        show_entity_ui_internal(target, owner, label, classname, editorId, accessors)
        imgui.pop_id()
        return
    end

    local previousChild = ui_context.get_child(rootContext, '__')

    local meta = typecache.get(classname)
    local childContext = create_field_editor(rootContext, classname, '__', classname, rootContext.label, accessors, rootContext.data.ui_settings, true)
    if not previousChild then
        childContext.data._has_extra_expander = true
        if meta.type ~= typecache.handlerTypes.array and meta.type ~= typecache.handlerTypes.genericList and label ~= nil then
            childContext.ui = expandable_ui(childContext.ui)
        end
    end
    -- ui_context.debug_view(target)
    local changed = childContext.ui(childContext)
    imgui.pop_id()
    if changed and owner then udb.mark_entity_dirty(owner, true) end
end

--- @param target any Edited object
--- @param owner DBEntity|nil
--- @param label string|nil
--- @param classname string|nil Edited object classname, will be inferred from target if not specified
--- @param editorId any A key by which to identify this editor. If unspecified, the target object's address will be used.
local function show_entity_ui(target, owner, label, classname, editorId)
    if not target then error('OI! ui needs a target and a parent!') return end

    show_entity_ui_internal(target, owner, label, classname, editorId, {
        set = function() error('Root editor setter unsupported') end,
        get = function(object) return object end,
    })
end

--- @param target any Edited object
--- @param owner DBEntity|nil
--- @param label string|nil
--- @param classname string|nil Edited object classname, will be inferred from target if not specified
--- @param editorId any A key by which to identify this editor. If unspecified, the target object's address will be used.
local function show_entity_ui_readonly(target, owner, label, classname, editorId)
    if not target then error('OI! ui needs a target!') return end

    show_entity_ui_internal(target, owner, label, classname, editorId, {
        set = function() error('Root editor setter unsupported') end,
        get = function(object) return object end,
    }, {
        is_readonly = true,
        hide_nonserialized = false,
        is_raw_data = false,
    })
end

--- @param targetContainer any An object that contains the target object we actually want to edit
--- @param field string|integer Field of the target object that we actually want to edit
--- @param owner DBEntity|nil
--- @param label string|nil
--- @param classname string|nil Edited object classname, will be inferred from target if not specified
--- @param editorId any A key by which to identify this editor. If unspecified, the target object's address will be used.
--- @return boolean instanceChanged Whether the root field instance was changed
local function show_entity_ui_editable(targetContainer, field, owner, label, classname, editorId)
    if not targetContainer then error('OI! ui needs a target and a parent!') return false end

    if targetContainer[field] == nil then
        imgui.text((label or field) .. ': null')
        if classname then
            imgui.same_line()
            imgui.push_id(editorId or tostring(targetContainer))
            if imgui.button('Create') then
                targetContainer[field] = helpers.create_instance(classname)
                imgui.pop_id()
                return true
            end
            imgui.pop_id()
        end
        return false
    end

    show_entity_ui_internal(targetContainer[field], owner, label, classname, editorId, {
        get = function(object) return object end,
        set = function(oldInstance, newInstance)
            print('updating root entity', oldInstance, newInstance)
            if type(oldInstance) == 'table' then
                print('concrete types:', oldInstance['$type'], newInstance['$type'])
            else
                print('concrete types:', oldInstance:get_type_definition():get_full_name(), newInstance:get_type_definition():get_full_name())
            end
            targetContainer[field] = newInstance
        end,
    })
    return false
end

--- @param owner DBEntity
--- @param containerField string Field of the target object that we actually want to edit
--- @param label string|nil
--- @param containerClassname string Container object classname, used to create a new instance if it's null
--- @param classname string Edited object classname, will be inferred from target if not specified
--- @param allowCreate boolean|nil Whether to allow instantiating the entity
--- @param editorId string|number|nil
--- @return boolean instanceChanged Whether the root container instance was changed
local function show_entity_ui_nullable(owner, containerField, field, label, containerClassname, classname, allowCreate, editorId)
    local container = owner[containerField]
    if not container or not container[field] then
        imgui.text(label .. ': null')
        imgui.same_line()
        if allowCreate == nil or allowCreate == true then
            imgui.push_id(editorId or owner and tostring(owner) or 0)
            if imgui.button('Create ' .. classname) then
                imgui.pop_id()
                owner[containerField] = container or helpers.create_instance(containerClassname)
                if owner[containerField][field] == nil then
                    owner[containerField][field] = helpers.create_instance(classname)
                end
                udb.mark_entity_dirty(owner)
                return true
            end
            imgui.pop_id()
        end
        return false
    end

    show_entity_ui_internal(container[field], owner, label, classname, editorId, {
        get = function(object) return object end,
        set = function(oldInstance, newInstance)
            print('updating root entity', oldInstance, newInstance)
            print('concrete types:', oldInstance.get_type_definition and oldInstance:get_type_definition():get_full_name(), '->', newInstance.get_type_definition and newInstance:get_type_definition():get_full_name())
            container[field] = newInstance
        end,
    })
    return false
end

local function embed_editor()

end

_userdata_DB._ui_handlers = {
    value_handlers = value_type_handler_defs,

    -- get_or_create_editor = create_editor,
    show = show_entity_ui,
    show_readonly = show_entity_ui_readonly,
    show_editable = show_entity_ui_editable,
    show_nullable = show_entity_ui_nullable,

    register_extension = register_extension,
    register_extension_alias = register_extension_alias,

    common = common,

    _internal = {
        apply_overrides = apply_ui_handler_overrides,
        create_field_editor = create_field_editor,
        accessors = {
            default = default_accessor,
            boxed_enum_accessor = boxed_enum_accessor,
            boxed_value_accessor = boxed_value_accessor,
            getter = getter_prop_accessor,
        },
    },
}
return _userdata_DB._ui_handlers
