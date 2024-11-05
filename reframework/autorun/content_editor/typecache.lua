if type(_userdata_DB) == 'nil' then _userdata_DB = {} end
if _userdata_DB._typecache then return _userdata_DB._typecache end

--- @class TypeCacheData
--- @field type HandlerType
--- @field fields [string, string, FieldFlags][]|nil [fieldName, fieldClass, flags]
--- @field subtypes string[]|nil
--- @field elementType string|nil
--- @field keyType string|nil For dictionary key types, null otherwise
--- @field itemCount integer
--- @field baseTypes string[]|nil
--- @field specialType nil|SpecialType
--- @field no_default_constructor nil|boolean

--- @enum SpecialType
local specialType = {
    userdata = 1,
}

--- @enum HandlerType
local handlerType = {
    readonly = 0,
    value = 1,
    enum = 2,
    object = 3,
    array = 4,
    genericList = 5,
    nullableValue = 6,
    dictionary = 7,
}

--- @enum FieldFlags
local fieldFlags = {
    None = 0,
    ImportEnable = 1,
    UIEnable = 2,
    NotNullable = 4,

    AllNullable = 3,
    All = 7,
}

local core = require('content_editor.core')
local utils = require('content_editor.utils')
local type_definitions = require('content_editor.definitions')
local generic_types = require("content_editor.generic_types")

local info = require('content_editor.gameinfo')

local type_enum = sdk.find_type_definition('System.Enum')
local type_userdata = sdk.find_type_definition('via.UserData')
local currentTypecacheVersion = 1

local readonly_cache_item = { type = handlerType.readonly, itemCount = 1 }
local typeSettings = type_definitions.type_settings

local typecache_path = core.get_path('cache/typecache.json')
local cache = {}

local ignored_types = {
    ["System.MulticastDelegate"] = true,
    ["System.Delegate"] = true,
}

local ignored_parents = {
    ["System.ValueType"] = true,
    ["System.Object"] = true,
    ["System.Enum"] = true,
}

--- @param typedef RETypeDefinition
--- @param typecache table<string, TypeCacheData>
local function build_typecache(typedef, typecache)
    local fullname = typedef:get_full_name()
    if typecache[fullname] then return end

    if ignored_types[fullname] then
        typecache[fullname] = { type = handlerType.readonly, itemCount = 0 }
        return
    end

    -- print('generating cache', fullname) -- DEBUGGING

    if typedef:is_value_type() then
        if typedef:is_a(type_enum) then
            local itemCount = 0
            for _, val in ipairs(typedef:get_fields()) do
                if val:is_static() then itemCount = itemCount + 1 end
            end
            local runtimeType = typedef:get_runtime_type()
            if runtimeType then
                runtimeType = runtimeType:GetEnumUnderlyingType()
            else
                -- enums nested inside generics don't have proper runtime types...
                -- defaulting to to int32 seems to cause other issues, so just disabling such cases for now
                -- runtimeType = sdk.find_type_definition('System.Int32'):get_runtime_type()
                typecache[fullname] = { type = handlerType.readonly, itemCount = 1 }
                return
            end
            typecache[fullname] = {
                type = handlerType.enum,
                elementType = runtimeType:get_FullName(),
                itemCount = itemCount,
            }
        elseif fullname:sub(1, 18) == 'System.Nullable`1<' then
            local nullableInner = fullname:sub(19, -2)
            local innerType = sdk.find_type_definition(nullableInner)
            if not innerType then
                print('Unsupported nullable inner type ' .. nullableInner)
                return
            end

            if innerType:is_a(type_enum) then
                -- unsure if we're gonna need separate handling for enum nullables
                typecache[fullname] = { type = handlerType.nullableValue, itemCount = 1, elementType = nullableInner }
            else
                typecache[fullname] = { type = handlerType.nullableValue, itemCount = 1, elementType = nullableInner }
            end
        else
            local fields = typedef:get_fields()
            local cacheEntry = { type = handlerType.value, fields = {}, itemCount = 0 }
            typecache[fullname] = cacheEntry
            for _, field in ipairs(fields) do
                if not field:is_static() then
                    local fieldName = field:get_name()
                    local fieldType = field:get_type()
                    -- potential optimization: flatten the array like, field1,type1,flags1,field2,type2,flags3,...
                    cacheEntry.fields[#cacheEntry.fields + 1] = {fieldName, fieldType:get_full_name(), fieldFlags.All}
                    if not typecache[fieldType:get_full_name()] then
                        build_typecache(fieldType, typecache)
                    end
                end
            end
            cacheEntry.itemCount = #cacheEntry.fields
        end
        return
    end

    if fullname:sub(-2) == '[]' then
        local elementType = fullname:sub(1, -3)
        local elemType = sdk.find_type_definition(elementType)
        if elemType then
            if not typecache[elementType] then
                build_typecache(elemType, typecache)
            end
            typecache[fullname] = { type = handlerType.array, elementType = elementType, itemCount = 999 }
        elseif elementType:find('`') then
            elementType = generic_types.get_clean_generic_classname(elementType)
            elemType = sdk.find_type_definition(elementType)
            if elemType then
                if not typecache[elementType] then
                    build_typecache(elemType, typecache)
                end
                typecache[fullname] = { type = handlerType.array, elementType = elementType, itemCount = 999 }
            else
                print('Failed to fix generic array element:', fullname, elementType)
                typecache[fullname] = readonly_cache_item
            end
        else
            -- print('Unsupported array element type', elementType)
            typecache[fullname] = readonly_cache_item
        end
        return
    end

    if fullname:sub(1, 31) == 'System.Collections.Generic.List' then
        local elementType = fullname:sub(35, -2)
        local elemType = sdk.find_type_definition(elementType)
        if elemType then
            if not typecache[elementType] then
                build_typecache(elemType, typecache)
            end

            typecache[fullname] = { type = handlerType.genericList, elementType = elementType, itemCount = 999 }
        else
            print('Unsupported list element type', elementType)
            typecache[fullname] = readonly_cache_item
        end
        return
    end

    if fullname:sub(1, 37) == 'System.Collections.Generic.Dictionary' then
        local genericType = sdk.find_type_definition(fullname)
        local args = genericType:get_generic_argument_types()
        local keyType = args[1]
        local keyTypeStr = args[1]:get_full_name()
        local valueType = args[2]

        local elementType = valueType:get_full_name()
        if not typecache[keyTypeStr] then build_typecache(keyType, typecache) end
        if not typecache[elementType] then build_typecache(valueType, typecache) end

        typecache[fullname] = { type = handlerType.dictionary, elementType = elementType, keyType = keyTypeStr, itemCount = 999 }
        return
    end

    local fields = {} --- @type REField[]
    local parents = {} --- @type string[]
    local parenttype = typedef:get_parent_type()
    local parentFieldFlags = {}
    while parenttype do
        local parentfull = parenttype:get_full_name()
        if ignored_types[parentfull] then
            typecache[fullname] = { type = handlerType.readonly, itemCount = 0 }
            return
        end
        if ignored_parents[parentfull] then break end
        build_typecache(parenttype, typecache)
        local parentCache = typecache[parentfull]
        if parentCache and parentCache.fields then
            for iii, pf in ipairs(parentCache.fields) do
                local nameInParent = pf[1]
                if nameInParent and not parentFieldFlags[nameInParent] then
                    parentFieldFlags[nameInParent] = pf[3]
                end
            end
        end

        for _, pf in ipairs(parenttype:get_fields()) do
            fields[#fields+1] = pf
        end
        parents[#parents+1] = parentfull
        parenttype = parenttype:get_parent_type()
    end
    for _, ff in ipairs(typedef:get_fields()) do
        fields[#fields+1] = ff
    end
    --- @type TypeCacheData
    local objectCacheEntry = { type = handlerType.object, fields = {}, itemCount = 0, baseTypes = parents }
    typecache[fullname] = objectCacheEntry

    local methods = typedef:get_methods()
    local ctorCount = 0
    local hasDefaultCtor = false
    for _, method in ipairs(methods) do
        local mname = method:get_name()
        if mname:sub(1, 5) == '.ctor' then
            ctorCount = ctorCount + 1
            if method:get_num_params() == 0 then
                hasDefaultCtor = true
                break
            end
        end
    end
    if not hasDefaultCtor and ctorCount > 0 then
        objectCacheEntry.no_default_constructor = true
    end

    local typeOverrides = typeSettings[fullname] or {}

    local order = typeOverrides.fieldOrder or typeOverrides.import_field_whitelist or {}
    local next_field_i = #order + 1
    local addedFields = {}
    local import_whitelist = typeOverrides.import_field_whitelist

    for _, field in ipairs(fields) do
        if not field:is_static() then
            local fieldName = field:get_name()
            local fieldType = field:get_type()
            -- handle fields that are defined in both any base class and a subclass
            if addedFields[fieldName] then
                local previousField = addedFields[fieldName]
                local prevtype = previousField:get_type()
                if fieldType == prevtype then
                    -- redeclared with same field name same type, safe to ignore
                    goto continue
                elseif fieldType:is_a(prevtype) then
                    -- subclass overrides the baseclass field type with a subclass of the original, perfectly valid and acceptable c#
                    -- prefer the subclass's type here
                    local baseIdx = utils.table_find_index(objectCacheEntry.fields, function (item) return item[1] == addedFields[fieldName] end)
                    -- print('OVERRIDDEN field type in subclass! ', fullname, 'base', prevtype:get_full_name(), 'sub', fieldType:get_full_name(), 'replace index', baseIdx)
                    if baseIdx ~= 0 then table.remove(objectCacheEntry.fields, baseIdx) end
                    addedFields[fieldName] = field
                else
                    -- do we need customizable base field override behavior?
                    -- case where we need the base field (for storage): app.quest.action.NpcControl
                    -- adding at least UI read-only access to both might be helpful, but at best nice-to-have
                    print('Ignoring redefined subclass field', fieldName, 'base:', prevtype:get_full_name(), 'sub:', fieldType:get_full_name())
                    goto continue
                end
            end

            local insert_index = utils.table_index_of(order, fieldName)
            if insert_index == 0 then
                insert_index = next_field_i
                next_field_i = next_field_i + 1
            end

            -- merge all parent's definitions for this field into one
            local typeOverridesForCurrentField = {} --- @type UserdataEditorSettings
            for i = #(parents or {}), 1, -1 do
                local parent = parents[i]
                local parentSettings = typeSettings[parent]
                if parentSettings then
                    type_definitions.merge_type_override(parentSettings, typeOverridesForCurrentField)
                end
            end
            type_definitions.merge_type_override(typeOverrides, typeOverridesForCurrentField)

            local fieldOverrides = typeOverridesForCurrentField.fields and typeOverridesForCurrentField.fields[fieldName]
            local fieldEffectiveType = nil
            if fieldOverrides and fieldOverrides.classname then
                fieldEffectiveType = fieldOverrides.classname
            else
                fieldEffectiveType = fieldType:get_full_name()
            end

            local flags = fieldFlags.AllNullable
            local parentFlag = parentFieldFlags[fieldName]
            if fieldOverrides and fieldOverrides.import_ignore or (import_whitelist ~= nil and not utils.table_contains(import_whitelist, fieldName)) or (parentFlag and parentFlag & fieldFlags.ImportEnable == 0) then
                flags = flags - fieldFlags.ImportEnable
            end
            if fieldOverrides and fieldOverrides.ui_ignore then
                flags = flags - fieldFlags.UIEnable
            elseif (not fieldOverrides or fieldOverrides.ui_ignore ~= true) and parentFlag and (parentFlag & fieldFlags.UIEnable == 0) then
                flags = flags - fieldFlags.UIEnable
            end
            if fieldOverrides and (fieldOverrides.not_nullable or fieldType:is_value_type()) then
                flags = flags + fieldFlags.NotNullable
            end

            -- we need to do this because uhh... sometimes lua decides that it's an associative table for no good fucking reason when serializing
            while #objectCacheEntry.fields < insert_index do
                objectCacheEntry.fields[#objectCacheEntry.fields+1] = {}
            end

            -- potential optimization: flatten the array like, field1,type1,flags1,field2,type2,flags3,...
            addedFields[fieldName] = field
            objectCacheEntry.fields[insert_index] = {fieldName, fieldEffectiveType, flags}
        end
        ::continue::
    end

    objectCacheEntry.itemCount = next_field_i - 1

    for iii, field in ipairs(objectCacheEntry.fields) do
        local fieldTypename = field[2]
        if not fieldTypename then
            print('missing field type wtf', fullname, field[1], field[2], field[3], 'field index', iii)
        elseif not typecache[fieldTypename] then
            local fieldType = sdk.find_type_definition(fieldTypename)
            build_typecache(fieldType, typecache)
        end
    end

    if typeOverrides and typeOverrides.abstract then
        local largest_abstract_field_count = 0
        for _, concrete in pairs(typeOverrides.abstract) do
            local subtype = sdk.find_type_definition(concrete)
            if subtype then
                build_typecache(subtype, typecache)
                largest_abstract_field_count = math.max(largest_abstract_field_count, typecache[concrete].itemCount)
            else
                print('WARNING: invalid abstract subtype', concrete, 'for base class', fullname)
            end
        end
        objectCacheEntry.itemCount = objectCacheEntry.itemCount + largest_abstract_field_count
    end

    if typedef:is_a(type_userdata) then
        objectCacheEntry.specialType = 1
    end
end

local cacheInvalidated = false

local function load_type_cache()
    local hash = core.VERSION_STR .. ' ' .. info.version .. ' ' .. type_definitions._hash
    local newCache = json.load_file(typecache_path)
    if newCache and newCache.__VERSION == currentTypecacheVersion and newCache.__HASH == hash then
        cache = newCache
    else
        -- auto-invalidate if the cache isn't the right version
        cache = {}
        cache.__VERSION = currentTypecacheVersion
        cache.__HASH = hash
        cacheInvalidated = true
    end
end

local function save_type_cache()
    cache.__VERSION = currentTypecacheVersion
    json.dump_file(typecache_path, cache)
end

local function save_if_invalid()
    if cacheInvalidated then
        save_type_cache()
    end
end

local function clear_type_cache()
    fs.write(typecache_path, 'null')
end

--- @param classname string
--- @return TypeCacheData
local function get_typecache_entry(classname)
    local cacheEntry = cache[classname]
    if not cacheEntry then
        local type = sdk.find_type_definition(classname)
        if not type then
            print("ERROR: can't generate type cache for unknown type " .. classname)
            return readonly_cache_item
        end
        build_typecache(type, cache)
        cacheEntry = cache[classname]
    end
    return cacheEntry
end

local function process_rsz()
    local rszData = json.load_file('rsz/rsz' .. reframework.get_game_name() .. '.json')
    if not rszData then print('rsz data not found') return end

    -- force clean data in the rsz json for this
    _userdata_DB.editor.set_need_script_reset()
    cache = {}
    type_definitions.type_settings = {}

    local outputDefinitions = {}
    for _, data in pairs(rszData) do
        local name = data.name
        -- ignore system types, enums, arrays, generics, compiler thingies, also via unless we find a way to handle them
        local ignoredType = name == ''
            or (name:find('System.') == 1)
            or (name:find('via.') == 1)
            or (#data.fields == 1 and data.fields[1].name == 'value__')
            or name:sub(-2) == '[]'
            or name:find('!')
            or name:find('<')
            or name:find('%[%[')
            or name:find('<>c') ~= nil
        if not ignoredType then
            local fields = {}
            local t = sdk.find_type_definition(name)
            local tc = t and get_typecache_entry(name)

            if tc and tc.type ~= handlerType.readonly then
                if data.fields then
                    for _, field in ipairs(data.fields) do
                        local fname = field.name---@type string
                        local ignore = fname:find('^v%d+$') or fname:match('^v%d+_')
                        if not ignore then
                            if fname:find('STRUCT_') == 1 then
                                local realname = fname:gsub('^STRUCT_', ''):gsub('_+[^_]+$', '')
                                if not utils.table_contains(fields, realname) then
                                    if utils.table_find(tc.fields, function (item) return item[1] == realname end) then
                                        fields[#fields+1] = realname
                                    else
                                        print('struct did not match any TDB fields', name, fname, '=>', realname)
                                    end
                                end
                            else
                                fields[#fields+1] = fname
                            end
                        end
                    end
                end

                if tc.baseTypes then
                    -- move any fields that belong to the parent class, to the parent class
                    -- god help me
                    for i = #tc.baseTypes, 1, -1 do
                        local parent = tc.baseTypes[i]
                        local parentTc = get_typecache_entry(parent)
                        if parentTc and parentTc.type ~= handlerType.readonly and parentTc.fields then
                            if not outputDefinitions[parent] then
                                outputDefinitions[parent] = { import_field_whitelist = {} }
                                local parentFields = outputDefinitions[parent].import_field_whitelist
                                for _, pFieldData in ipairs(parentTc.fields) do
                                    local pfield = pFieldData[1]
                                    -- print('checking for field', pfield)
                                    if utils.table_contains(fields, pfield) then
                                        parentFields[#parentFields+1] = pfield
                                        -- print('moving field', pfield, '=>', parent)
                                        table.remove(fields, utils.table_index_of(fields, pfield))
                                    end
                                end
                            else
                                -- print('existing parent merge', name, parent)
                                local parentFields = outputDefinitions[parent].import_field_whitelist
                                for _, pfield in ipairs(parentFields) do
                                    local idx = utils.table_index_of(fields, pfield)
                                    if idx ~= 0 then table.remove(fields, idx) end
                                end
                            end
                        end
                    end
                end
                local fieldcount = tc.fields and #tc.fields
                if fieldcount ~= #fields then
                    outputDefinitions[name] = {
                        import_field_whitelist = fields,
                    }
                end
            end
        end
    end

    local outfn = core.get_path('rsz/' .. reframework.get_game_name() .. '.json')
    local outjson = json.dump_string(outputDefinitions, 2)
    outjson = outjson:gsub('"import_field_whitelist": null', '"import_field_whitelist": []')
    fs.write(outfn, outjson)
end

_userdata_DB._typecache = {
    get = get_typecache_entry,
    load = load_type_cache,
    clear = clear_type_cache,
    save = save_type_cache,
    save_if_invalid = save_if_invalid,

    process_rsz_data = process_rsz,

    handlerTypes = handlerType,
    fieldFlags = fieldFlags,
}
return _userdata_DB._typecache