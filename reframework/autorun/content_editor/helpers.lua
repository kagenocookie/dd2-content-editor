if type(usercontent) == 'nil' then usercontent = {} end
if usercontent._ui_utils then return usercontent._ui_utils end

local core = require('content_editor.core')
local utils = require('content_editor.utils')
local enums = require('content_editor.enums')
local generic_types = require("content_editor.generic_types")

local type_settings = require('content_editor.definitions')
local typecache = require('content_editor.typecache')

local function to_hashset(list)
    local lk = {}
    for _, v in ipairs(list) do lk[v] = true end
    return lk
end

local integer_types = to_hashset({'System.Int32', 'System.UInt32', 'System.Int16', 'System.UInt16', 'System.Int64', 'System.UInt64', 'System.Byte', 'System.SByte'})
local float_types = to_hashset({'System.Single', 'System.Double'})

local create_new_instance

--- @param meta TypeCacheData
--- @param classname string
local function create_lua_object(meta, classname)
    local obj = { ['$type'] = classname }
    if meta.fields then
        for _, fieldData in ipairs(meta.fields) do
            local field = fieldData[1]
            local fieldClass = fieldData[2]
            local flags = fieldData[3]
            -- pre-create only serialized, not-nullable types
            if flags & typecache.fieldFlags.ImportEnable ~= 0 and flags & typecache.fieldFlags.NotNullable ~= 0 then
                obj[field] = create_new_instance(fieldClass, true)
                -- print('creating child field', classname, field, fieldClass, obj[field])
            end
        end
    end
    return obj
end

local systemActivator = sdk.find_type_definition('System.Activator'):get_method('CreateInstance')
local arrayActivator = sdk.find_type_definition('System.Array'):get_method('CreateInstance')

--- @param classname string|System.Type|RETypeDefinition Classname, should be the element type if array and not the array type itself
--- @param arrayLength integer|nil If nil, creates a normal class instance, if a number then creates an array with that length
--- @return REManagedObject|SystemArray|nil
local function create_generic(classname, arrayLength)
    local genType = type(classname) == 'string' and generic_types.typedef(classname)
        or classname.get_runtime_type and generic_types.typedef(classname:get_full_name())
        or classname
    if genType == nil or not classname then
        return nil
    end

    if arrayLength ~= nil then return arrayActivator:call(nil, genType, arrayLength):add_ref() end
    return systemActivator:call(nil, genType):add_ref()
end

--- Create a managed array, seamlessly handle generic types
--- @param elementClassname string
--- @param length integer|nil
--- @param items any[]|nil
--- @return SystemArray
local function create_array(elementClassname, length, items)
    local array
    local len = length and length >= 0 and length or items and #items or 0
    if elementClassname:find('`') then
        array = create_generic(elementClassname, len)
    else
        array = sdk.create_managed_array(elementClassname, len):add_ref()
    end

    if items then
        for i, item in ipairs(items) do
            if i > len then break end
            array[i - 1] = item
        end
    end
    return array--[[@as SystemArray]]
end

---@param list_classname string Classname - e.g. System.Collections.Generic.List`1<System.String>
---@param items any[]
---@return nil|REManagedObject System.Collections.Generic.List<{typename}>
local function create_generic_list(list_classname, items)
    local list = create_generic(list_classname)
    if not list then return nil end

    for _, item in ipairs(items) do
        list--[[@as any]]:Add(item)
    end
    return list
end

--- @param org_array SystemArray
--- @param appended_items REManagedObject[]
--- @param elementType string|nil
--- @param prepend boolean|nil
--- @return SystemArray
local function expand_system_array(org_array, appended_items, elementType, prepend)
    local added_len = #appended_items
    if added_len == 0 then return org_array end

    elementType = elementType or org_array:get_type_definition():get_full_name():sub(1, -3)
    local arr_len = org_array:get_size()
    if arr_len == 0 then return create_array(elementType, added_len, appended_items) end

    local newElements = org_array:get_elements()
    if prepend then
        for i = 1, added_len do
            table.insert(newElements, arr_len + i, appended_items[i])
        end
        return create_array(elementType, arr_len + added_len, newElements)
    else
        local arr = create_array(elementType, arr_len + added_len, newElements)
        --- @cast arr SystemArray
        for i = 1, added_len do
            arr[arr_len + i - 1] = appended_items[i]
        end
        return arr
    end
end

--- @param org_array SystemArray
--- @param remove_index number 0-based index to remove from the array
--- @param elementType string|nil
--- @return SystemArray
local function system_array_remove_at(org_array, remove_index, elementType)
    local arr_len = org_array:get_size()

    local typename = elementType or org_array:get_type_definition():get_full_name():sub(1, -3)
    local arr = create_array(typename, arr_len - 1)
    --- @cast arr SystemArray
    for i = 0, remove_index - 1 do
        arr[i] = org_array[i]
    end

    for i = remove_index + 1, arr_len - 1 do
        arr[i - 1] = org_array[i]
    end
    return arr
end

--- @param org_array SystemArray
--- @param item any
--- @param elementType string|nil
--- @return SystemArray
local function system_array_remove(org_array, item, elementType)
    for i, v in pairs(org_array) do
        if v == item then return system_array_remove_at(org_array, i, elementType) end
    end
    return org_array
end

--- @param org_array SystemArray
--- @param filter fun(item: REManagedObject): boolean
--- @param elementType string|nil
--- @return SystemArray
local function system_array_filtered(org_array, filter, elementType)
    local newlist = {}
    elementType = elementType or org_array:get_type_definition():get_full_name():sub(1, -3)

    local len = org_array:get_size()
    for i = 0, len - 1 do
        local item = org_array[i]
        if filter(item) then newlist[#newlist+1] = item end
    end

    if len == #newlist then return org_array end
    return create_array(elementType, #newlist, newlist)
end

--- @param arrayContainer REManagedObject
--- @param arrayField string
--- @param item any
--- @param elementClassname string
local function ensure_item_in_array(arrayContainer, arrayField, item, elementClassname)
    if item and not utils.table_contains(arrayContainer[arrayField], item) then
        arrayContainer[arrayField] = expand_system_array(arrayContainer[arrayField], {item}, elementClassname)
    end
end

--- Create a new instance of an arbitrary engine type
--- @param classname string
--- @param luaValue boolean|nil Whether we want a raw lua value and not a game compatible instance
--- @return any|nil
create_new_instance = function(classname, luaValue)
    local meta = typecache.get(classname)
    if meta.type == typecache.handlerTypes.object then
        if classname == 'System.String' then return luaValue and '' or sdk.create_managed_string('') end
        local ts = type_settings.type_settings[classname]
        if ts and ts.abstract then
            if luaValue then
                return create_lua_object(meta, ts.abstract_default or ts.abstract[1])
            else
                return sdk.create_instance(ts.abstract_default or ts.abstract[1]):add_ref()
            end
        else
            if classname:find('`') then
                return create_generic(classname)
            end
            if luaValue then
                return create_lua_object(meta, classname)
            elseif meta.no_default_constructor then
                -- print('creating non-abstract simplify', classname)
                return sdk.create_instance(classname, true):add_ref()
            else
                -- print('creating non-abstract non-simplify', classname)
                return sdk.create_instance(classname):add_ref()
            end
        end
    end
    if meta.type == typecache.handlerTypes.enum then
        return enums.get_enum(classname).values[1] or 0
    end
    if meta.type == typecache.handlerTypes.value then
        if integer_types[classname] then
            return 0
        end
        if float_types[classname] then
            return 0.0
        end
        if classname == 'System.Boolean' then return false end
        if luaValue then return {} end
        return ValueType.new(sdk.find_type_definition(classname))
    end
    if luaValue then return {} end
    if meta.type == typecache.handlerTypes.array then
        return create_array(meta.elementType, 0)
    end
    if meta.type == typecache.handlerTypes.genericList or meta.type == typecache.handlerTypes.dictionary then
        return create_generic(classname)
    end
    if meta.type == typecache.handlerTypes.readonly then
        return sdk.create_instance(classname):add_ref()
    end
    if meta.type == typecache.handlerTypes.nullableValue then
        return sdk.create_instance(classname):add_ref()
    end
end

--- @type ArrayLikeAccessors
local array_accessors = {
    length = function (arr)
        --- @cast arr SystemArray
        return arr and arr.get_size and arr:get_size() or 0
    end,
    foreach = function (arr)
        local i = -1
        return function ()
            i = i + 1
            if i < arr:get_size() then
                return arr[i] or 'null', i
            end
        end
    end,
    get_elements = function (arr) return arr and arr.get_elements and arr--[[@as SystemArray]]:get_elements() or {} end,
    remove = function (arr, idx)
        --- @cast arr SystemArray
        return system_array_remove_at(arr, idx)
    end,
    add = function (arr, element, classname)
        --- @cast arr SystemArray
        local newarr = expand_system_array(arr, {element}, typecache.get(classname).elementType)
        return newarr
    end,
}

--- @type ArrayLikeAccessors
local list_accessors = {
    length = function (list) return list:get_Count() end,
    foreach = utils.list_iterator,
    get_elements = function (list)
        local items = {}
        for i = 0, list:get_Count() - 1 do items[i + 1] = list[i] end
        return items
    end,
    remove = function (list, idx) list:RemoveAt(idx) return list end,
    add = function (list, element) list:Add(element) return list end,
}

--- @type ArrayLikeAccessors
local ienumerable_accessors = {
    length = function (list) return list:get_Count() end,
    foreach = utils.enumerate,
    get_elements = function (list)
        local items = {}
        local it = list:GetEnumerator()
        while it:MoveNext() do
            items[#items+1] = it._current
        end
        pcall(items.call, items, 'Dispose')
        return items
    end,
    remove = function (list, idx, value) if list.Remove then list:Remove(value) else print('Cannot remove from ', list:get_type_definition():get_full_name()) end return list end,
    add = function (list, element) list:Add(element) return list end,
}

--- @type ArrayLikeAccessors
local table_accessors = {
    length = function (tbl) return #tbl end,
    foreach = function (tbl)
        local k, v
        return function ()
            k, v = next(tbl, k)
            if k then
                return v, k
            end
        end
    end,
    get_elements = function (tbl)
        local out = {}
        for _, v in pairs(tbl) do
            out[#out+1] = v
        end
        return out
    end,
    remove = function (tbl, idx) table.remove(tbl, idx) return tbl end,
    add = function (tbl, element) tbl[#tbl+1] = element return tbl end,
}

--- Get the target type classname of an object. Should seamlessly handle raw lua data (for abstract types) or REManagedObject instances.
--- @param obj table|REManagedObject|nil
--- @return string|nil
local function get_type(obj)
    if obj == nil then return nil end
    if type(obj) == 'table' then return obj['$type'] end
    if type(obj) == 'userdata' and obj--[[@as REManagedObject]].get_type_definition then return obj--[[@as REManagedObject]]:get_type_definition():get_full_name() end
    return nil
end

--- @param classname string An engine classname or 'table' to get a lua accessor wrapper
--- @return ArrayLikeAccessors
local function get_arraylike_accessor(classname)
    if classname == 'table' then
        return table_accessors
    end

    local meta = typecache.get(classname)
    if meta.type == typecache.handlerTypes.array then
        return array_accessors
    elseif meta.type == typecache.handlerTypes.genericList then
        return list_accessors
    elseif meta.type == typecache.handlerTypes.genericEnumerable then
        return ienumerable_accessors
    else
        print('ERROR: Unknown array-like classname: ' .. classname)
        return table_accessors
    end
end

--- @param classname string An engine classname or 'table' to get a lua accessor wrapper
--- @param wrapper { add: nil|fun(obj: any), remove: nil|fun(obj: any) }
--- @return ArrayLikeAccessors
local function get_wrapped_arraylike_accessor(classname, wrapper)
    local accessor = get_arraylike_accessor(classname)
    --- @type ArrayLikeAccessors
    local wrapped = {
        foreach = accessor.foreach,
        get_elements = accessor.get_elements,
        length = accessor.length,
        create = accessor.create,
        remove = function (arr, index, value)
            if wrapper.remove then wrapper.remove(value) end
            return accessor.remove(arr, index, value)
        end,
        add = function (arr, object, arrayClassname)
            if wrapper.add then wrapper.add(object) end
            return accessor.add(arr, object, arrayClassname)
        end
    }
    return wrapped
end

--- @param item any
--- @param classname string|nil
--- @param context UIContainer|nil
--- @return string
local function _object_to_string_internal(item, classname, context)
    if item == nil then
        return classname and ('null (' .. classname .. ')') or 'null'
    end

    if not classname then
        classname = get_type(item)
        if not classname then
            if type(item) == 'userdata' and item.ToString then return item:ToString() end
            return tostring(item)
        end
    else
        if type(item) == 'number' then
            local meta = typecache.get(classname)
            if meta.type == typecache.handlerTypes.enum then
                local enum = enums.get_enum(classname)
                local enumLabel = enum and enum.get_label(item)
                if enumLabel then
                    return enumLabel
                else
                    return tostring(item) .. ' [enum mismatch '..classname..']'
                end
            end
        end
        -- in case of abstract classes, our input classname would've been the base class
        -- try and fetch the actual class and use that one's toString
        -- if that fails, fallback to whatever base classname we received
        local realClassname = get_type(item)
        if realClassname then
            classname = realClassname
        end
        if realClassname and realClassname ~= classname then
            local realSettings = type_settings.type_settings[realClassname]
            if realSettings and realSettings.toString then
                return realSettings.toString(item, context)
            end
        end
    end

    local typesettings = type_settings.type_settings[classname]
    if typesettings and typesettings.toString then
        return typesettings.toString(item, context)
    end

    local meta = typecache.get(classname)
    if type(item) == 'userdata' and item.ToString then
        local success, str = pcall(item.call, item, 'ToString()')
        if success then
            if str == classname then
                if not typesettings then
                    typesettings = {}
                    type_settings.type_settings[classname] = typesettings
                end
                if meta.itemCount == 1 then
                    local field, class = meta.fields[1][1], meta.fields[1][2]
                        typesettings.toString = function (value)
                            return field .. '=' .. _object_to_string_internal(value[field], class, context)
                        end
                    return typesettings.toString(item, context)
                else
                    typesettings.toString = function () return classname end
                end
            end
            return str
        else
            return item:get_type_definition():get_full_name() .. ' [ToString() failed]'
        end
    end
    if type(item) == 'table' then
        if meta.specialType == 1 and item and item['$uri'] then
            return classname .. ' (raw data) - ' .. tostring(item['$uri'])
        else
            return classname .. ' (raw data)'
        end
    end
    return tostring(item)
end

--- @param item any
--- @param classname string|nil
--- @return string
local function object_to_string(item, classname)
    return _object_to_string_internal(item, classname, nil)
end

--- @param context UIContainer
local function context_to_string(context)
    local item = context.get()
    local classname = context.data.classname
    return _object_to_string_internal(item, classname, context)
end

--- @param array table|REManagedObject
--- @param separator string
--- @param arrayClassname string|nil
--- @param emptyString string|nil
--- @return string
local function array_to_string(array, separator, arrayClassname, emptyString)
    if array == nil then return 'null' end

    local items
    if type(array) == 'table' then
        items = array
    else
        arrayClassname = arrayClassname or array:get_type_definition():get_full_name()
        local accessor = get_arraylike_accessor(arrayClassname)
        if not accessor then return 'invalid array type ' .. arrayClassname end
        items = accessor.get_elements(array)
    end
    local str = table.concat(utils.map(items, function (item) return object_to_string(item) end), separator)
    if str == '' then return emptyString or 'empty' end
    return str
end

--- Get a function that will concatenate all fields for a specific classname using the to_string function
--- @param classname string
--- @param whitelistedFlags FieldFlags
--- @param includeClassname boolean|integer|nil false/0 = no class prefix, true/1/default = base name only, 2 = full namespaced classname
--- @param fieldWhitelist string[]|nil List of fields to include
--- @return fun(target: REManagedObject): string
local function to_string_concat_fields(classname, whitelistedFlags, includeClassname, fieldWhitelist)
    whitelistedFlags = whitelistedFlags or typecache.fieldFlags.All
    local meta = typecache.get(classname)
    local funcs = {}
    for _, f in ipairs(meta.fields) do
        local name = f[1]
        local fc = f[2]
        local flags = f[3]
        if (flags & whitelistedFlags) ~= 0 or (fieldWhitelist and utils.table_contains(fieldWhitelist, name)) then
            funcs[#funcs+1] = function (target)
                return name .. '=' .. object_to_string(target[name], fc)
            end
        end
    end

    local baseString = includeClassname == 2 and classname
        or (includeClassname == false or includeClassname == 0) and ''
        or classname:find('.') and classname:gmatch('%.[^.]+$')():sub(2)
        or classname

    return function(target)
        local str = baseString
        for _, f in ipairs(funcs) do
            str = str .. (str ~= '' and ' ' or '') .. f(target)
        end
        return str
    end
end

--- Get all elements of an array-like object (system array, generic list, lua table), in a 1-indexed lua table
--- @param array any
--- @param classname string
--- @return any[]
local function array_elements(array, classname)
    local accessor = get_arraylike_accessor(classname)
    return accessor.get_elements(array)
end

--- comment
--- @param context UIContainer|nil
--- @return boolean
local function is_arraylike(context)
    if context == nil then return false end
    local cls = context.data.classname
    if not cls then return false end
    local meta = typecache.get(cls)
    return meta.type == typecache.handlerTypes.array or meta.type == typecache.handlerTypes.genericList
end

--- Get the target type of an object. Should seamlessly handle raw lua data or REManagedObject instances, as well as mod-provided accessor overrides.
--- @param obj table|REManagedObject|nil
--- @param field string
--- @return any|nil
local function get_field(obj, field)
    if not obj then return obj end
    if type(obj) == 'table' then return obj[field] end

    local type = get_type(obj)
    if type == nil then return nil end

    -- local meta = typecache.get(type)
    -- local info = meta.fields[field]
    local typesettings = type_settings.type_settings[type]
    if typesettings and typesettings.fields and typesettings.fields[field] then
        if typesettings.fields[field].accessors then
            return typesettings.fields[field].accessors.get(obj, field)
        end
    end

    return obj[field]
end

--- Get the target type of an object. Should seamlessly handle raw lua data or REManagedObject instances, as well as mod-provided accessor overrides.
--- @param obj table|REManagedObject|nil
--- @param field string
--- @param value any
local function set_field(obj, field, value)
    if not obj then return end
    if type(obj) == 'table' then obj[field] = value return end

    local type = get_type(obj)
    if type == nil then return end

    local typesettings = type_settings.type_settings[type]
    if typesettings and typesettings.fields and typesettings.fields[field] then
        if typesettings.fields[field].accessors then
            typesettings.fields[field].accessors.set(obj, value, field)
            return
        end
    end

    obj[field] = value
end

--- @generic T : table|REManagedObject
--- @param object T
--- @param classname string|nil
--- @param raw boolean|nil
--- @return T|table clone Returns table type if raw is true, otherwise returns a full REManagedObject clone
local function clone_object(object, classname, raw)
    if type(object) == 'table' then return utils.clone_table(object) end
    if type(object) ~= 'userdata' then return object end

    classname = classname or get_type(object)
    if classname == nil then return nil end

    local handler = usercontent.import_handlers.get_handler(classname)
    if handler == nil then return nil end

    local data = handler.export(object, nil, { raw = true })
    if raw then return data end

    return handler.import(data)
end

--- Create a new object retaining the current values of an existing instance
--- @generic T : table|REManagedObject
--- @param object T
--- @param classname string|nil
--- @param raw boolean|nil
--- @return REManagedObject|table clone Returns table type if raw is true, otherwise returns a full REManagedObject clone
local function change_type(object, classname, raw)
    if type(object) == 'table' then
        local cloned = utils.clone_table(object)
        cloned['$type'] = classname
        return cloned
    end
    if type(object) ~= 'userdata' then return object end

    classname = classname or get_type(object)
    if classname == nil then return nil end

    local handler = usercontent.import_handlers.get_handler(classname)
    if handler == nil then return nil end

    local raw_data = usercontent.import_handlers.export(object)
    local newObj = handler.import(raw_data)
    if raw then
        newObj = handler.export(object, nil, { raw = true })
    end
    return newObj
end

--- For games that have support for it, hook to whatever it has available that lets us know that the game state done an ingame<->out of game transition (loaded, reloaded, died, returned to menu, ...)
--- Can be used to clear any custom gameplay effects
--- @param callback fun(is_ingame: boolean)
local function hook_game_load_or_reset(callback)
    if core.game.on_game_after_load then
        core.game.on_game_after_load(callback)
    end
    if core.game.on_game_unload then
        core.game.on_game_unload(callback)
    end
end

usercontent._ui_utils = {
    create_instance = create_new_instance,
    create_generic_instance = create_generic,
    create_generic_list = create_generic_list,

    is_integer_type = function (classname) return integer_types[classname] end,
    is_float_type = function (classname) return float_types[classname] end,

    create_array = create_array,
    is_arraylike = is_arraylike,
    array_accessor = get_arraylike_accessor,
    array_accessor_wrapped = get_wrapped_arraylike_accessor,
    array_elements = array_elements,
    expand_system_array = expand_system_array,
    system_array_remove_at = system_array_remove_at,
    system_array_remove = system_array_remove,
    ensure_item_in_array = ensure_item_in_array,
    system_array_filtered = system_array_filtered,
    clone = clone_object,
    change_type = change_type,

    to_string = object_to_string,
    context_to_string = context_to_string,
    array_to_string = array_to_string,
    to_string_concat_fields = to_string_concat_fields,

    get_type = get_type,
    get_field = get_field,
    set_field = set_field,

    hook_game_load_or_reset = hook_game_load_or_reset,
}
return usercontent._ui_utils
