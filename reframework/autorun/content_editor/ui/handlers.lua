if type(usercontent) == 'nil' then usercontent = {} end
if usercontent._ui_handlers then return usercontent._ui_handlers end

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
--- @field no_nonserialized_indicator boolean|nil
--- @field allow_props boolean|nil
--- @field allow_methods boolean|nil

--- @type table<string, UIHandler>
local object_handlers = {
    ['System.String'] = common.string
}

local type_multidelegate = sdk.find_type_definition('System.MulticastDelegate')
--- @type UIHandler
local delegate_handler = function (context)
    local val = context.get()
    if val == nil then
        imgui.text('Delegate ' .. context.label .. ': null')
        imgui.same_line()
        imgui.text_colored('(' .. context.data.classname .. ')', core.get_color('note'))
        return false
    end

    if ui.treenode_suffix('Delegate ' .. context.label, context.data.classname, core.get_color('note')) then
        context.data.isMulti = context.data.isMulti or val:get_type_definition():is_a(type_multidelegate)

        if context.data.target_valid == nil then
            local base_target = val and val.get_Target and val:get_Target()
            if base_target then
                context.data.target_valid = true
                context.data.target_classname = base_target.get_type_definition and base_target:get_type_definition():get_full_name()
            else
                context.data.target_valid = false
            end

            context.data.target_method = val.get_Method and val:get_Method():get_Name() or '<unknown>'
        end

        imgui.text('Method: ' .. context.data.target_method)
        if not context.data.target_valid then
            imgui.text('Target: unknown')
        end
        if context.data.target_valid and ui.treenode_suffix('Target', context.data.target_classname) then
            local child = ui_context.get_child(context, '__target')
            if not child then
                local target = val:get_Target()
                context.data._has_extra_expander = true
                child = usercontent._ui_handlers._internal.create_field_editor(
                    context,
                    context.data.classname,
                    '__target',
                    context.data.target_classname,
                    'Target',
                    { get = function () return target end, set = function () end },
                    context.data.ui_settings,
                    true
                )
            end
            -- imgui.text(child.object:get_type_definition():get_full_name())
            child:ui()
            imgui.tree_pop()
        end

        if not context.data.invocations then
            local invocations = val.GetInvocationList and val:GetInvocationList()
            local invo_count = invocations and invocations:get_Length()

            context.data.invocations = {}
            context.data.invocations_count = invo_count or 0

            if invocations then
                for i = 0, context.data.invocations_count - 1 do
                    context.data.invocations[i + 1] = invocations[i]:add_ref()
                end
            end
        end

        local count = context.data.invocations_count
        if context.data.isMulti and count > 1 and ui.treenode_suffix('Invocations', '(' .. count .. ')' or nil) then
            for i = 1, context.data.invocations_count do
                local target = context.data.invocations[i]
                if not target then
                    imgui.text((i - 1) .. ': null')
                else
                    local child = ui_context.get_child(context, i - 1)
                    if not child then
                        context.data._has_extra_expander = true
                        child = usercontent._ui_handlers._internal.create_field_editor(
                            context,
                            context.data.classname,
                            (i - 1),
                            target:get_type_definition():get_full_name(),
                            tostring(i - 1),
                            { get = function () return target end, set = function () end },
                            context.data.ui_settings,
                            nil
                        )
                    end
                    child:ui()
                end
            end
            imgui.tree_pop()
        end

        imgui.tree_pop()
    end
    return false
end

--- @type table<string, UIHandler>
local value_type_handler_defs = {
    ["System.UInt32"] = common.int(0.1, 0, 4294967295),
    ["System.Int32"] = common.int(0.1, -2147483648, 2147483647),
    ["System.UInt64"] = common.int(0.1, 0, 18446744073709551616),
    ["System.Int64"] = common.int(0.1, -9223372036854775808, 9223372036854775807),
    ["System.UInt16"] = common.int(0.1, 0, 65535),
    ["System.Int16"] = common.int(0.1, -32767, 32767),
    ["System.Byte"] = common.int(0.1, 0, 255),
    ["System.SByte"] = common.int(0.1, -128, 127),
    ["System.Boolean"] = common.bool,
    ["System.Single"] = common.float(0.1, -9999999999, 9999999999),
    ["System.Double"] = common.float(0.1, -9999999999, 9999999999),
    ['via.vec2'] = common.vec2,
    ['via.vec3'] = common.vec3,
    ['via.vec4'] = common.vec4,
    ['via.mat4'] = common.mat4,
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
            value.mData4L = math.random(-4611686018427387904, 4611686018427387904)
        end
        ctx.set(value)
        randomized = true
    end
    imgui.same_line()
    imgui.set_next_item_width(w - 66)
    local changed, newGuidStr = imgui.input_text(ctx.label, helpers.to_string(value, 'System.Guid'))
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

object_handlers['via.GameObject'] = function (context)
    local go = context.get() ---@type via.GameObject
    if not go then
        imgui.text('GameObject is null')
        return false
    end
    if not go:get_Valid() then
        imgui.text(context.label .. ': Invalid GameObject')
        return false
    end

    local labelAppend = go:get_Name()
    local tag = go:get_Tag()
    if tag and tag ~= '' then labelAppend = labelAppend .. ' #' .. tag end
    imgui.text(context.label .. ': GameObject ' .. labelAppend)

    changed, val = imgui.checkbox('UpdateSelf', go:get_UpdateSelf())
    if changed then go:set_UpdateSelf(val) end

    changed2, val = imgui.checkbox('DrawSelf', go:get_DrawSelf())
    if changed2 then go:set_DrawSelf(val) end

    local folder = go.get_FolderSelf and go:get_FolderSelf() or go.get_Folder and go:get_Folder()
    if folder and imgui.tree_node('Folder') then
        usercontent._ui_handlers.show_nested(folder, context, 'Folder', 'via.Folder', false)
        imgui.tree_pop()
    end

    local comps = context.data.components
    if ui.treenode_suffix('Components', comps and '(' .. tostring(#comps) .. ')' or '') then
        imgui.same_line()
        if imgui.button('Refresh components') then context.data.components = nil end
        context.data.filter = select(2, imgui.input_text('Filter components', context.data.filter or ''))
        if not context.data.components then
            comps = go:get_Components():get_elements()
            context.data.components = comps
        end
        context.data.compdata = context.data.compdata or {}
        for i, comp in ipairs(comps) do
            context.data.compdata[i] = context.data.compdata[i] or {}
            local compType = comp:get_type_definition()
            local compName = compType:get_full_name()
            if not context.data.filter or context.data.filter == '' or compName:find(context.data.filter) then
                usercontent._ui_handlers.show_nested(comp, context, compType:get_name(), compName, true)
            end
        end
        imgui.tree_pop()
    end

    return changed or changed2
end

object_handlers['via.Folder'] = function (context)
    local folder = context.get() ---@type via.Folder
    if not folder then return false end
    imgui.text(folder:get_Name()--[[@as string]])
    local changed, changed2, val
    changed, val = imgui.checkbox('UpdateSelf', folder:get_UpdateSelf())
    if changed then folder:set_UpdateSelf(val) end

    changed2, val = imgui.checkbox('DrawSelf', folder:get_DrawSelf())
    if changed2 then folder:set_DrawSelf(val) end

    local parent = folder:get_Parent()
    if parent and imgui.tree_node('Parent: ' .. parent:get_Name()) then
        usercontent._ui_handlers.show_nested(parent, context, 'Parent', 'via.Folder', false)
        imgui.tree_pop()
    end

    local subfolders = context.data.subfolders
    if ui.treenode_suffix('Subfolders', subfolders and '(' .. tostring(#subfolders) .. ')' or '') then
        imgui.same_line()
        if imgui.button('Refresh components') then context.data.subfolders = nil end
        if not context.data.subfolders then
            context.data.subfolders = utils.folder.get_subfolders(folder)
            subfolders = context.data.subfolders
        end
        for i, comp in ipairs(subfolders) do
            local name = comp:get_Name()
            usercontent._ui_handlers.show_nested(comp, context, 'folder__' .. name, 'via.Folder', name)
        end
        imgui.tree_pop()
    end

    local children = context.data.children
    if ui.treenode_suffix('GameObjects', children and '(' .. tostring(#children) .. ')' or '') then
        imgui.same_line()
        if imgui.button('Refresh list') then context.data.children = nil end
        if not context.data.children then
            context.data.children = utils.folder.immediate_children(folder)
            children = context.data.children
        end
        for i, comp in ipairs(children) do
            local name = comp:get_GameObject():get_Name()
            local addr = comp:get_address()
            imgui.push_id(addr)
            usercontent._ui_handlers.show_nested(comp, context, tostring(addr), 'via.Transform', name)
            imgui.pop_id()
        end
        imgui.tree_pop()
    end

    local all_children = context.data.all_children
    if ui.treenode_suffix('All Children', all_children and '(' .. tostring(#all_children) .. ')' or '') then
        imgui.same_line()
        if imgui.button('Refresh list') then context.data.all_children = nil end
        if not context.data.all_children then
            context.data.all_children = utils.folder.get_children(folder)
            all_children = context.data.all_children
        end
        for i, comp in ipairs(all_children) do
            local name = comp:get_GameObject():get_Name()
            local addr = comp:get_address()
            imgui.push_id(addr)
            usercontent._ui_handlers.show_nested(comp, context, tostring(addr), 'via.Transform', name)
            imgui.pop_id()
        end
        imgui.tree_pop()
    end

    return changed or changed2
end

object_handlers['via.Transform'] = function (context)
    local transform = context.get() ---@type via.Transform
    if not transform then
        imgui.text('Transform is null')
        return false
    end

    if imgui.tree_node('GameObject') then
        local go = transform:get_GameObject()
        if go then
            usercontent._ui_handlers.show_nested(go, context, 'gameObject', 'via.GameObject')
        else
            imgui.text('GameObject is null')
        end
        imgui.tree_pop()
    end

    local parent = transform:get_Parent()
    if parent then
        if ui.treenode_suffix('Parent', parent:ToString()--[[@as string]]) then
            usercontent._ui_handlers.show_nested(parent, context, 'parent', 'via.Transform')
            imgui.tree_pop()
        end
    end

    local children = context.data.children
    if ui.treenode_suffix('Children', (children and '(' .. tostring(#children) .. ')') or '') then
        imgui.same_line()
        if imgui.button('Refresh children') then context.data.children = nil end
        if not context.data.children then
            context.data.children = {}
            local c = transform:get_Child()
            while c do
                context.data.children[#context.data.children + 1] = c
                c = c:get_Next()
            end
        end
        children = context.data.children

        for i, child in ipairs(children) do
            usercontent._ui_handlers.show_nested(child, context, i, 'via.Transform', true)
        end
        imgui.tree_pop()
    end

    if not context.children.LocalPosition then
        local child = ui_context.create_child(context, 'UniversalPosition', transform, 'Universal Position', {
            get = function (object) return object:get_UniversalPosition() end,
            set = function (object, val) object:set_UniversalPosition(val) end,
        }, 'via.Position')
        child.ui = common.vec3

        local child = ui_context.create_child(context, 'LocalPosition', transform, 'Local Position', {
            get = function (object) return object:get_LocalPosition() end,
            set = function (object, val) object:set_LocalPosition(val) end,
        }, 'via.vec3')
        child.ui = common.vec3

        child = ui_context.create_child(context, 'LocalEulerAngle', transform, 'Local Euler Angle', {
            get = function (object) return object:get_LocalEulerAngle() end,
            set = function (object, val) object:set_LocalEulerAngle(val) end,
        }, 'via.vec3')
        child.ui = common.vec3

        child = ui_context.create_child(context, 'LocalScale', transform, 'Local Scale', {
            get = function (object) return object:get_LocalScale() end,
            set = function (object, val) object:set_LocalScale(val) end,
        }, 'via.vec3')
        child.ui = common.vec3
    end
    context.children.UniversalPosition:ui()
    context.children.LocalPosition:ui()
    context.children.LocalEulerAngle:ui()
    context.children.LocalScale:ui()
    return false
end

object_handlers['via.Prefab'] = function (context)
    local pfb = context.get()
    if not pfb then
        imgui.text(context.label .. ' Prefab null')
        imgui.same_line()
        if imgui.button('Create') then
            context.set(sdk.create_instance('via.Prefab'):add_ref())
            return true
        end
        return false
    end
    local changed = false
    local path = pfb:get_Path()
    context.data.newpath = select(2, imgui.input_text('Path', context.data.newpath or path or ''))
    if context.data.newpath and context.data.newpath ~= path then
        if imgui.button('Change') then
            pfb:set_Path(context.data.newpath)
            context.data.newpath = nil
            changed = true
        end
        imgui.same_line()
        if imgui.button('Cancel') then
            context.data.newpath = nil
        end
    end

    return changed
end

--- @type ObjectFieldAccessors
local default_accessor = {
    get = function (object, fieldname)
        if object ~= nil then return object[fieldname]
        else return nil end
    end,
    set = function (object, value, fieldname) object[fieldname] = value end,
}

--- @type ObjectFieldAccessors
local boxed_value_accessor = {
    get = function (object, fieldname) return object[fieldname][typecache.boxed_value_field()] end,
    set = function (object, value, fieldname) object[fieldname] = value end
}

--- @type ObjectFieldAccessors
local boxed_enum_accessor = {
    get = function (object, fieldname) return object[fieldname][typecache.boxed_enum_field()] end,
    set = function (object, value, fieldname) object[fieldname] = value end
}

--- @type ObjectFieldAccessors
local getter_prop_accessor = {
    get = function (object, propGetter) return object:call(propGetter) end,
    set = function (object, value, fieldname) print('WARNING: Attempted to set read-only prop', object, fieldname, value) end
}

--- @type ObjectFieldAccessors
local hashset_accessor = {
    get = function (object, fieldname) return fieldname end,
    set = function (object, newValue, current) object--[[@as any]]:Remove(current) object--[[@as any]]:Add(newValue) end
}

--- @type ObjectFieldAccessors
local component_go_accessor = {
    get = function (object) return object and object:get_Valid() and object--[[@as any]]:get_GameObject() or nil end,
    set = function () print('Error: GameObject reference not editable') end
}

local prop_invalid_error_value_constant = { message = '' }

--- @param typedef RETypeDefinition
--- @param getter string|nil
--- @param setter string|nil
local function create_prop_accessor(typedef, getter, setter)
    local getf, setf
    local cachedValue, didfail
    if getter then
        local get_method = typedef:get_method(getter)
        -- since we don't know what kind of bullshit the getter might be doing, call the get method once and cache the value
        -- it should get reset when the tree item is reopened since that would clear up the ui context
        getf = get_method and function (object)
            if cachedValue == nil then
                local success, cv = pcall(get_method.call, get_method, object)
                if not success then
                    print(getter .. ' property getter error: ' .. tostring(cv))
                    cachedValue = 'ERROR: ' .. tostring(cv)
                    prop_invalid_error_value_constant.message = cachedValue
                    didfail = true
                    return prop_invalid_error_value_constant
                else
                    cachedValue = cv
                    if type(cachedValue) == 'userdata' and cachedValue.add_ref then cachedValue = cachedValue:add_ref() end
                end
            elseif didfail then
                prop_invalid_error_value_constant.message = cachedValue
                return prop_invalid_error_value_constant
            end
            return cachedValue
        end
        if not get_method then print('invalid getter', typedef:get_full_name(), getter) end
    end
    if setter then
        local set_method = typedef:get_method(setter)
        if getf then
            setf = set_method and function (object, newValue) set_method:call(object, newValue) cachedValue = newValue end
        else
            setf = set_method and function (object, newValue) set_method:call(object, newValue) end
        end
    end

    getf = getf or function () return 'unkown' end
    setf = setf or function (object, value, fieldname) print('WARNING: Attempted to set read-only prop', object, value, fieldname) end
    --- @type ObjectFieldAccessors
    return {
        get = getf,
        set = setf
    }
end

local editorConfig

--- @param label string
--- @param isProperty boolean|nil
--- @return string
local function generate_field_label(label, isProperty)
    if label:sub(1,1) == '_' then label = label:sub(2) end
    if label:sub(1,1) == '<' then
        local name = isProperty or label:match('<([a-zA-Z0-9_]+)>k__BackingField')
        if name then
            if not editorConfig then editorConfig = usercontent.__internal.config.data.editor end
            if editorConfig.show_prop_labels then
                return 'Prop/' .. (isProperty and label or name)
            end
            return (isProperty and label or name)
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
--- @param containerClassOrSettings string|UserdataEditorSettings
--- @param field string|integer
--- @param fieldClass string
--- @return UIHandler
local function apply_ui_handler_overrides(handler, containerClassOrSettings, field, fieldClass)
    local typesettings = type(containerClassOrSettings) == 'string' and type_settings.type_settings[containerClassOrSettings] or containerClassOrSettings
    if type(typesettings) == 'boolean' then
        print('bool lol', typesettings, containerClassOrSettings)
    end
    local fieldOverrides = typesettings and typesettings.fields and typesettings.fields[field] or {}
    local fieldTypeOverrides = field ~= '__element' and type_settings.type_settings[fieldClass]

    if fieldOverrides and fieldOverrides.uiHandler then
        handler = fieldOverrides.uiHandler
    elseif fieldTypeOverrides and fieldTypeOverrides.uiHandler then
        handler = fieldTypeOverrides.uiHandler
    elseif fieldTypeOverrides and fieldTypeOverrides.uiHandlerDeferred then
        handler = fieldTypeOverrides.uiHandlerDeferred()
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
    if not meta.elementType then error('INVALID ARRAY: ' .. classname) return function () end end
    if expand_per_element == nil then
        local elementMeta = typecache.get(meta.elementType)
        expand_per_element = elementMeta.type ~= typecache.handlerTypes.enum and elementMeta.itemCount >= defines.array_expand_minimum_fields
    end
    local skip_root_tree_node = typesettings and typesettings.array_expander_disable or false
    local elementAccessor = default_accessor
    if not settings.is_raw_data then
        if meta.type == typecache.handlerTypes.array then
            local elementMeta = typecache.get(meta.elementType)
            if elementMeta.type == typecache.handlerTypes.value then
                elementAccessor = boxed_value_accessor
            elseif elementMeta.type == typecache.handlerTypes.enum then
                elementAccessor = boxed_enum_accessor
            end
        elseif meta.type == typecache.handlerTypes.genericEnumerable and classname:find('HashSet') then
            elementAccessor = hashset_accessor
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
            local index = 0
            for element, key in array_access.foreach(array) do
                index = index + 1
                if element == nil then goto continue end
                imgui.begin_rect()
                imgui.push_id(type(key or element) == 'userdata' and index or (key or element))
                if imgui.button('X') then
                    -- delete all child element containers and re-create them next iteration, that's the easiest way of ensuring we don't mess up the children index keys
                    ui_context.delete_children(context)
                    local newArray = array_access.remove(array, key, element)
                    if newArray ~= array then
                        context.set(newArray)
                    end
                    imgui.tree_pop()
                    return true
                end

                imgui.same_line()
                local isNewChildCtx = context.children[key or element] == nil
                local childCtx = create_field_editor(context, classname, key or element, meta.elementType, tostring(key or element), elementAccessor, settings, not expand_per_element)
                if isNewChildCtx then
                    childCtx.ui = apply_ui_handler_overrides(childCtx.ui, classname, "__element", meta.elementType)
                end

                local childChanged = childCtx:ui()
                changed = childChanged or changed

                imgui.pop_id()
                imgui.end_rect(1)
                ::continue::
            end
            imgui.pop_id()

            if array_access.add and imgui.button('Add') then
                local newElement = settings.is_raw_data and {} or helpers.create_instance(meta.elementType)
                local newArray = array_access.add(array, newElement, classname)
                if newArray ~= array then
                    array = newArray
                    context.set(newArray)
                end
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

--- @param meta TypeCacheData
--- @param classname string
--- @param label string
--- @param settings UISettings
--- @return UIHandler
local function dictionary_ui(meta, classname, label, settings)
    --- @type UIHandler
    return function (context)
        local dict = context.get()
        if not dict then
            imgui.text('Dictionary is null')
            if imgui.button('Create') then
                local newInst = settings.is_raw_data and {} or helpers.create_generic_instance(classname)
                if newInst then
                    context.set(newInst)
                    return true
                else
                    print('ERROR: could not instantiate instance of dictionary', classname)
                end
            end
            return false
        end
        local items = context.data.elements
        local refreshBtn = false
        local changed = false
        if context.data._has_extra_expander or ui.treenode_suffix(context.label, classname) then
            if items then
                imgui.same_line()
                refreshBtn = imgui.button('Refresh list')
                for idx, pair in ipairs(items) do
                    local keyStr = helpers.to_string(pair[1], meta.keyType)
                    local valueStr = helpers.to_string(pair[2], meta.elementType)

                    imgui.begin_rect()
                    imgui.push_id(idx)
                    if not settings.is_readonly and imgui.button('X') then
                        -- delete all child element containers and re-create them next iteration, that's the easiest way of ensuring we don't mess up the children index keys
                        ui_context.delete_children(context)
                        if type(dict) == 'table' then
                            dict[pair[1]] = nil
                        else
                            dict:Remove(pair[1])
                        end
                        imgui.pop_id()
                        imgui.end_rect(1)
                        imgui.tree_pop()
                        imgui.tree_pop()
                        imgui.tree_pop()
                        context.data.elements = nil
                        return true
                    end
                    if not settings.is_readonly then imgui.same_line() end

                    if ui.treenode_suffix(keyStr, valueStr) then
                        local isNewChildCtx = context.children[pair[1]] == nil
                        local childCtx = create_field_editor(context, classname, pair[1], meta.elementType, valueStr, default_accessor, settings, true)
                        if isNewChildCtx then
                            childCtx.data._has_extra_expander = true
                            childCtx.ui = apply_ui_handler_overrides(childCtx.ui, classname, "__element", meta.elementType)
                        end

                        local childChanged = childCtx:ui()
                        changed = childChanged or changed

                        imgui.tree_pop()
                    end
                    imgui.pop_id()
                    imgui.end_rect(1)
                end
                if imgui.tree_node('New entry') then
                    local newCtx = ui_context.get_or_create_child(context, '__new', {}, '', nil, '')
                    if newCtx.object.new_key == nil then newCtx.object.new_key = helpers.create_instance(meta.keyType) end
                    if newCtx.object.new_value == nil then newCtx.object.new_value = helpers.create_instance(meta.elementType) end
                    create_field_editor(newCtx, '__none', 'new_key', meta.keyType, 'Key', nil, settings, true):ui()
                    create_field_editor(newCtx, '__none', 'new_value', meta.elementType, 'Value', nil, settings, true):ui()

                    local newkey = newCtx.children.new_key.get()
                    local curKeyExists = false
                    if newkey then
                        if type(dict) == 'userdata' then
                            curKeyExists = dict:ContainsKey(newkey)
                        else
                            curKeyExists = dict[newkey]
                        end
                    end
                    if newkey and not curKeyExists and imgui.button('Add entry') then
                        local newvalue = newCtx.children.new_value.get()
                        dict[newkey] = newvalue:add_ref()
                        items = nil
                        changed = true
                        ui_context.delete_child(context, '__new')
                    end
                    if imgui.is_item_hovered() then imgui.set_tooltip('If the entry already exists, it will be replaced with a new instance') end
                    imgui.tree_pop()
                else
                    ui_context.delete_child(context, '__new')
                    context.data.new_key = nil
                    context.data.new_value = nil
                end
            end

            if refreshBtn or not items then
                if type(dict) == 'userdata' then
                    local it = dict:GetEnumerator()
                    items = {}
                    while it:MoveNext() do
                        local key = type(it._current.key) == 'userdata' and it._current.key.add_ref and it._current.key:add_ref() or it._current.key
                        local value = type(it._current.value) == 'userdata' and it._current.value.add_ref and it._current.value:add_ref() or it._current.value
                        items[#items+1] = { key, value }
                    end
                elseif type(dict) == 'table' then
                    items = {}
                    for k, v in pairs(dict) do
                        items[#items+1] = { k, v }
                    end
                end
                context.data.elements = items
            end

            if not items then
                imgui.text('Dictionary is null or invalid')
                imgui.tree_pop()
                return false
            end

            if not context.data._has_extra_expander then
                imgui.tree_pop()
            end
        end

        return changed
    end
end

--- @type table<HandlerType, UIHandlerFactory>
local field_editor_factories

--- @type table<HandlerType, UIHandlerFactory>
field_editor_factories = {
    [typecache.handlerTypes.enum] = function (meta, classname)
        return common.enum(classname)
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

                local childChanged = childCtx:ui()

                if not isReadonly and childChanged then
                    changed = true
                    -- need to reassign over the original struct on any change since value types
                    context.set(value)
                end
            end
            return changed
        end
    end,
    [typecache.handlerTypes.delegate] = function (meta, classname, label, settings)
        return delegate_handler
    end,
    [typecache.handlerTypes.object] = function (meta, classname, label, settings)
        -- print('generating new object UIHandler', container:get_type_definition():get_full_name(), classname)
        if object_handlers[classname] then
            return object_handlers[classname]
        end
        if meta.specialType == typecache.specialType.resource then
            local resourceClass = classname:gsub('Holder$', '')
            object_handlers[classname] = common.resource_holder(resourceClass)
            return object_handlers[classname]
        end

        local mainHandler
        local typesettings = type_settings.type_settings[classname] or {}
        if typesettings.abstract then
            local defaultClass = typesettings.abstract_default or typesettings.abstract[1]
            --- @type UIHandler
            mainHandler = function (context)
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
                changed, newType, context.data.abstract_filter = ui.combo_filterable(context.label .. ' Classname', previousType, typesettings.abstract, context.data.abstract_filter)
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
            local fieldCount = 0
            for _, subfield in ipairs(meta.fields or {}) do
                local flags = subfield[3]
                if (flags & typecache.fieldFlags.UIEnable) ~= 0 then
                    local name = subfield[1]
                    local type = subfield[2]
                    local overrides = fieldSettings[name]
                    local sublabel = format_field_label(overrides and overrides.label or generate_field_label(name), label)
                    fieldCount = fieldCount + 1
                    fields[fieldCount] = { name, type, flags, sublabel, overrides and overrides.accessors or default_accessor }
                end
            end
            local fieldsFilterable = fieldCount > 10

            --- @type UIHandler
            mainHandler = function (context)
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

                if meta.specialType == typecache.specialType.component then
                    create_field_editor(context, classname, '__go', 'via.GameObject', 'GameObject', component_go_accessor, settings):ui()
                    imgui.spacing()
                end
                if fieldsFilterable then
                    imgui.indent(6)
                    if imgui.calc_item_width() > 300 then imgui.set_next_item_width(300) end
                    context.data.field_filter = select(2, imgui.input_text('<Filter fields>', context.data.field_filter or ''))
                    imgui.unindent(6)
                end
                if fieldCount == 0 and context.data._has_extra_expander then
                    imgui.text_colored('<no fields to be found here>', core.get_color('disabled'))
                end
                for fieldIdx, subfieldData in ipairs(fields) do
                    local subfield = subfieldData[1]
                    local subtype = subfieldData[2]
                    local flags = subfieldData[3]
                    local sublabel = subfieldData[4]
                    local access = settings.hide_nonserialized and default_accessor or subfieldData[5]
                    if context.data.field_filter and context.data.field_filter ~= '' and not sublabel:lower():find(context.data.field_filter:lower()) then
                        goto continue
                    end

                    local childCtx = create_field_editor(context, classname, subfield, subtype, sublabel, access, settings)

                    local nonSerialized = (flags & typecache.fieldFlags.ImportEnable) == 0
                    if settings.hide_nonserialized and nonSerialized then
                        goto continue
                    end

                    imgui.push_id(fieldIdx)
                    local showUnserializedIndicator = nonSerialized and not settings.no_nonserialized_indicator
                    if showUnserializedIndicator then
                        imgui.indent(-14)
                        imgui.text_colored("*", core.get_color('info'))
                        if imgui.is_item_hovered() then
                            imgui.set_tooltip('Field is not serialized\nUsually this means the data is used only during runtime and managed automatically by the game, or the mod automatically handles it for you.')
                        end
                        imgui.same_line()
                        imgui.push_style_color(0, 0xfff3f3f3)
                    end
                    local childChanged = childCtx:ui()
                    imgui.pop_id()

                    if showUnserializedIndicator then
                        imgui.pop_style_color(1)
                        imgui.unindent(-14)
                    else
                        changed = childChanged or changed
                    end
                    ::continue::
                end
                return changed
            end

            if settings.allow_props and meta.props and #meta.props > 0 then
                mainHandler = ui_extensions['props'](mainHandler, { } --[[@as any]])
            end

            if settings.allow_methods then
                mainHandler = ui_extensions['methods'](mainHandler, { } --[[@as any]])
            end

            if meta.specialType == typecache.specialType.gui then
                mainHandler = ui_extensions['gui_tree'](mainHandler, { } --[[@as any]])
            end
        end

        return mainHandler
    end,
    [typecache.handlerTypes.array] = function (meta, classname, label, settings)
        local accessor = settings.is_raw_data and helpers.array_accessor('table') or helpers.array_accessor(classname) --[[@as ArrayLikeAccessors]]
        return create_arraylike_ui(meta, classname, label, accessor, settings)
    end,
    [typecache.handlerTypes.genericList] = function (meta, classname, label, settings)
        local accessor = settings.is_raw_data and helpers.array_accessor('table') or helpers.array_accessor(classname) --[[@as ArrayLikeAccessors]]
        return create_arraylike_ui(meta, classname, label, accessor, settings)
    end,
    [typecache.handlerTypes.genericEnumerable] = function (meta, classname, label, settings)
        local accessor = settings.is_raw_data and helpers.array_accessor('table') or helpers.array_accessor(classname) --[[@as ArrayLikeAccessors]]
        return create_arraylike_ui(meta, classname, label, accessor, settings)
    end,
    [typecache.handlerTypes.dictionary] = function (meta, classname, label, settings)
        return dictionary_ui(meta, classname, label, settings)
    end,
    [typecache.handlerTypes.nullableValue] = function (meta, classname, label, settings)
        if settings.is_raw_data then
            local valueMeta = typecache.get(meta.elementType)
            local handler = field_editor_factories[valueMeta.type](valueMeta, meta.elementType, label, settings)
            return common.toggleable(handler, function (value) return value ~= nil end, function (context, toggle)
                if toggle then
                    context.set(helpers.create_instance(meta.elementType, true))
                else
                    context.set(nil)
                end
            end, nil, true)
        else
            --- @type UIHandler
            local handler = function (context)
                local childCtx = create_field_editor(context, classname, '_Value', meta.elementType, 'Value', default_accessor, settings)
                return childCtx:ui()
            end
            return common.nullable_valuetype(meta.elementType, handler)
        end
    end,
    [typecache.handlerTypes.readonly] = function ()
        return function (context)
            imgui.text(context.label .. ': ' .. helpers.context_to_string(context) .. ' (*readonly)')
            return false
        end
    end,
}

--- @param ctx UIContainer
--- @param classname string
--- @param label string
--- @param expander boolean
--- @param settings UISettings
--- @param field string|integer|nil
--- @param containerClassOrSettings UserdataEditorSettings|string|nil
local function setup_context_ui(ctx, classname, label, settings, expander, field, containerClassOrSettings)
    local meta = typecache.get(classname)
    local handler = field_editor_factories[meta.type](meta, classname, label, settings)
    if field and containerClassOrSettings then
        handler = apply_ui_handler_overrides(handler, containerClassOrSettings, field, classname)
    end
    ctx.data.ui_settings = settings

    if expander then
        ctx.data._has_extra_expander = true
        ctx.ui = expandable_ui(handler)
    else
        ctx.ui = handler
    end
end

--- @param parentContext UIContainer|nil
--- @param classname string
--- @param childKey string|integer
--- @param label string
--- @param doExpander boolean|nil
--- @param settings UISettings|nil
--- @return UIContainer ctx, boolean isNew
local create_editor = function(parentContext, childKey, currentValue, classname, label, doExpander, settings)
    local ctx, newCtx = ui_context.get_or_create_child(parentContext, childKey, currentValue, label, nil, classname)
    if newCtx then
        settings = utils.table_assign({
            is_raw_data = type(currentValue) == 'table',
            hide_nonserialized = type(currentValue) == 'table',
        }, settings or (parentContext and parentContext.data.ui_settings) or {})
        setup_context_ui(ctx, classname, label, settings, doExpander or false)
        -- print('Created new editor context', ui_context.get_absolute_path(ctx), tostring(currentValue))
    end
    return ctx, newCtx
end

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
    if ctx then return ctx end

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

        local childCount = submeta.itemCount
        if settings.allow_props and submeta.props and next(submeta.props) then
            childCount = childCount + #submeta.props
        end

        if expanderOverride == true or expanderOverride ~= false and childCount >= defines.object_expand_minimum_fields then
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

    ctx = ui_context.create_child(parentContext, field, accessors.get(parentContext.object, field), label, accessors, fieldClass)
    setup_context_ui(ctx, fieldClass, label, settings, doExpander == nil and true or doExpander, field, typesettings)
    return ctx
end

--- @param editorId any
--- @param target any
--- @param label string|nil
--- @param owner DBEntity|nil
--- @param fallback any
--- @return string|integer
local function get_editor_id(editorId, target, label, owner, fallback)
    if editorId then
        if type(editorId) == 'string' or type(editorId) == 'number' then return editorId end
        if type(editorId) == 'table' then
            local idKey = '_id' .. label
            editorId[idKey] = editorId[idKey] or (target and type(target) == 'userdata' and target.get_address and target:get_address()) or math.random(1, 1000000)
            return editorId[idKey]
        end
        print('Could not determine editor id', editorId, owner, label)
        return tostring(editorId)
    else
        if target ~= nil and type(target) == 'userdata' then return target:get_address() end
        -- print('Could not determine editor id', owner, label)
        return tostring(fallback or 0) .. label
    end
end

--- @param target any
--- @param context UIContainer
--- @param key string|integer
--- @param classname string|nil
--- @param label boolean|string|nil
--- @return boolean objectChanged
local function show_object_nested_ui(target, context, key, classname, label)
    classname = classname or helpers.get_type(target) or error('Missing classname')
    if type(label) == 'string' then
        return create_editor(context, key, target, classname, label, true):ui()
    else
        return create_editor(context, key, target, classname, tostring(label and key or ''), label or false):ui()
    end
end

--- @param target any
--- @param owner DBEntity|nil
--- @param label string|nil
--- @param classname string|nil
--- @param editorId any A key by which to identify this editor. If unspecified, the target object's address will be used.
--- @param setter nil|fun(oldValue: any, newValue: any)
--- @param uiSettingOverrides UISettings|nil
--- @return boolean changed
local function show_root_entity(target, owner, label, classname, editorId, setter, uiSettingOverrides, preventLoop)
    if not target then error('OI! ui needs a target and a parent!') end
    classname = classname or helpers.get_type(target)
    if not classname then
        imgui.text_colored('Invalid entity for display: ' .. tostring(target), core.get_color('error'))
        return false
    end
    editorId = get_editor_id(editorId, target, label or classname, owner)

    local rootContext, isNew = create_editor(nil, editorId, target, classname, label or '', label and label ~= '' or false, uiSettingOverrides)

    if isNew then
        if setter then rootContext.set = setter end
    elseif rootContext.object ~= target then
        ui_context.delete(rootContext, editorId)
        if preventLoop then
            imgui.pop_id()
            print('root context instance changed', target, rootContext.object, editorId)
            return true
        else
            return show_root_entity(target, owner, label, classname, editorId, setter, uiSettingOverrides, true)
        end
    end

    imgui.push_id(editorId)
    -- ui_context.debug_view(target)
    local changed = rootContext:ui()
    imgui.pop_id()
    if changed and owner then udb.mark_entity_dirty(owner, true) end
    return changed
end

--- @param target any Edited object
--- @param owner DBEntity|nil
--- @param label string|nil
--- @param classname string|nil Edited object classname, will be inferred from target if not specified
--- @param editorId any A key by which to identify this editor or a table. If unspecified, the label or target object's address will be used as a key.
--- @param settings UISettings|nil
--- @return boolean changed
local function show_entity_ui(target, owner, label, classname, editorId, settings)
    if not target then imgui.text_colored((label or 'Target') .. ' is null', core.get_color('error')) return false end

    return show_root_entity(target, owner, label, classname, editorId, nil, settings)
end

--- Show an entity in a read-only state (read only not yet fully implemented)
--- @param target REManagedObject|ValueType Edited object
--- @param owner DBEntity|nil
--- @param label string|nil
--- @param classname string|nil Edited object classname, will be inferred from target if not specified
--- @param editorId any A key by which to identify this editor or a table. If unspecified, the label or target object's address will be used as a key.
--- @return boolean changed
local function show_entity_ui_readonly(target, owner, label, classname, editorId)
    if not target then imgui.text_colored((label or 'Target') .. ' is null', core.get_color('error')) return false end

    return show_root_entity(target, owner, label, classname, editorId, nil, {
        is_readonly = true,
        hide_nonserialized = false,
        is_raw_data = false,
    })
end

--- Show object whose instance can be modified (e.g. abstract or nullable fields)
--- @param targetContainer any An object that contains the target object we actually want to edit
--- @param field string|integer Field of the target object that we actually want to edit
--- @param owner DBEntity|nil
--- @param label string|nil
--- @param classname string|nil Edited object classname, will be inferred from target if not specified
--- @param editorId any A key by which to identify this editor. If unspecified, the target object's address will be used.
--- @param settings UISettings|nil
--- @return boolean instanceChanged Whether the root field instance was changed
local function show_entity_ui_editable(targetContainer, field, owner, label, classname, editorId, settings)
    if not targetContainer then error('OI! ui needs a target and a parent!') return false end

    local target = targetContainer[field]
    if target == nil then
        imgui.text((label or field) .. ': null')
        if classname then
            imgui.same_line()
            imgui.push_id(get_editor_id(editorId, targetContainer, label or classname, owner, targetContainer))
            if imgui.button('Create') then
                targetContainer[field] = helpers.create_instance(classname)
                imgui.pop_id()
                return true
            end
            imgui.pop_id()
        end
        return false
    end

    local changed = show_root_entity(target, owner, label, classname, editorId, function(oldInstance, newInstance)
        print('updating root entity', oldInstance, newInstance)
        if type(oldInstance) == 'table' then
            print('concrete types:', oldInstance['$type'], newInstance['$type'])
        else
            print('concrete types:', oldInstance:get_type_definition():get_full_name(), newInstance:get_type_definition():get_full_name())
        end
        targetContainer[field] = newInstance
    end, settings)
    return changed
end

--- Show an editable lua table of entities
--- @param targetContainer any The object containing the table
--- @param field string|integer Field on the object for the table
--- @param owner DBEntity|nil
--- @param label string|nil
--- @param classname string Edited object classname
--- @param editorId any A key by which to identify this editor. If unspecified, the target object's address will be used.
--- @param settings UISettings|nil
--- @param onAdd nil|fun(obj: any, owner: DBEntity|nil)
--- @param onRemove nil|fun(obj: any, owner: DBEntity|nil)
--- @return boolean instanceChanged Whether the root field instance was changed
local function show_object_list(targetContainer, field, owner, label, classname, editorId, settings, onAdd, onRemove)
    if not targetContainer then error('OI! ui needs a target and a parent!') return false end

    local target = targetContainer[field]
    if target == nil then
        imgui.text((label or field) .. ': null')
        if classname then
            imgui.same_line()
            imgui.push_id(get_editor_id(editorId, targetContainer, label or classname, owner, targetContainer))
            if imgui.button('Create') then
                targetContainer[field] = {}
                imgui.pop_id()
                return true
            end
            imgui.pop_id()
        end
        return false
    end

    editorId = get_editor_id(editorId, targetContainer, label or classname, owner)
    local rootCtx, isNew = ui_context.get_or_create_child(nil, field, target, label or '', nil, classname)
    if rootCtx.object ~= target then
        rootCtx.object = target
    end
    if isNew then
        rootCtx.owner = owner
        rootCtx.set = function (value) targetContainer[field] = value end
        -- to simplify the code, use a lua table wrapper and pretend it's an array type
        -- with added callbacks so we can trigger partial data imports in real-time
        local arrayClassname = classname .. '[]'
        local accessorWrapper = helpers.array_accessor_wrapped('table', {
            add = onAdd and function (obj) onAdd(obj, owner) end or nil,
            remove = onRemove and function (obj) onRemove(obj, owner) end or nil,
        })
        rootCtx.ui = create_arraylike_ui(typecache.get(arrayClassname), arrayClassname, label or arrayClassname, accessorWrapper, settings or {})
    end
    changed = rootCtx:ui() or changed
    return changed
end

--- Show an object for the way too specific case where two nullable fields are present before the main instance type. Will likely be removed at some point.
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

    show_root_entity(container[field], owner, label, classname, editorId, function(oldInstance, newInstance)
        print('updating root entity', oldInstance, newInstance)
        print('concrete types:', oldInstance.get_type_definition and oldInstance:get_type_definition():get_full_name(), '->', newInstance.get_type_definition and newInstance:get_type_definition():get_full_name())
        container[field] = newInstance
    end)
    return false
end

usercontent._ui_handlers = {
    value_handlers = value_type_handler_defs,

    show = show_entity_ui,
    show_nested = show_object_nested_ui,
    show_readonly = show_entity_ui_readonly,
    show_editable = show_entity_ui_editable,
    show_object_list = show_object_list,
    show_nullable = show_entity_ui_nullable,

    register_extension = register_extension,
    register_extension_alias = register_extension_alias,

    common = common,

    _internal = {
        apply_overrides = apply_ui_handler_overrides,
        create_field_editor = create_field_editor,
        generate_field_label = generate_field_label,
        prop_invalid_error_value_constant = prop_invalid_error_value_constant,
        arraylike = create_arraylike_ui,
        accessors = {
            default = default_accessor,
            boxed_enum_accessor = boxed_enum_accessor,
            boxed_value_accessor = boxed_value_accessor,
            getter = getter_prop_accessor,
            create_prop = create_prop_accessor,
        },
    },
}
return usercontent._ui_handlers
