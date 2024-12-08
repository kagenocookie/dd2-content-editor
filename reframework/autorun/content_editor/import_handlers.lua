if type(usercontent) == 'nil' then usercontent = {} end
if usercontent.import_handlers then return usercontent.import_handlers end

local utils = require('content_editor.utils')
local type_settings = require('content_editor.definitions')
local typecache = require('content_editor.typecache')
local helpers = require('content_editor.helpers')

-- helper functions
local type_guid = sdk.find_type_definition('System.Guid')

--- @return ValueImporter
local function vec2(classname)
    --- @type ValueImporter
    return {
        export = function (src, target)
            target = target or {}
            target.x = src.x
            target.y = src.y
            return target
        end,
        import = function (src, target)
            target = target or ValueType.new(sdk.find_type_definition(classname))
            target.x = src.x
            target.y = src.y
            return target
        end,
    }
end

--- @return ValueImporter
local function vec3(classname)
    --- @type ValueImporter
    return {
        export = function (src, target)
            target = target or {}
            target.x = src.x
            target.y = src.y
            target.z = src.z
            return target
        end,
        import = function (src, target)
            if src == nil then return target end
            target = target or ValueType.new(sdk.find_type_definition(classname))
            target.x = src.x
            target.y = src.y
            target.z = src.z
            return target
        end,
    }
end

--- @return ValueImporter
local function resource(resourceClassname)
    --- @type ValueImporter
    return {
        export = function (src)
            if src == nil then return 'null' end
            return src:get_ResourcePath()
        end,
        import = function (src, target)
            if src == nil then return target end
            if src == 'null' then return nil end
            if target ~= nil and target:get_ResourcePath() == src then return target end

            local newres = sdk.create_resource(resourceClassname, src)
            if not newres then return nil end

            newres = newres:add_ref()
            target = sdk.create_instance(resourceClassname .. 'Holder', true):add_ref()
            target:call('.ctor()')
            target:write_qword(0x10, newres:get_address())
            return target
        end,
    }
end

--- @return ValueImporter
local prefab = {
    export = function (src)
        if src == nil then return '' end
        return src:get_Path()
    end,
    import = function (src, target)
        if src == nil or src == '' or src == 'null' then return nil end
        target = target or sdk.create_instance('via.Prefab'):add_ref()
        target:set_Path(src)
        return target
    end
}

--- @type table<string, ValueImporter>
local known_importers = {
    ['via.Position'] = vec3('via.Position'),
    ['via.vec3'] = vec3('via.vec3'),
    ['via.vec2'] = vec2('via.vec2'),
    ['via.Prefab'] = prefab,
    ['via.render.TextureResourceHolder'] = resource('via.render.TextureResource'),
    ['via.gui.GUIResourceHolder'] = resource('via.gui.GUIResource'),
}

--- @type ValueImporter
local import_export_as_is = {
    import = function (src) return src end,
    export = function (src) return src end,
}

local import_export_ignore = {
    import = function() end,
    export = function() end,
}

for _, t in ipairs({'System.UInt32','System.Int32','System.UInt64','System.Int64','System.UInt16','System.Int16','System.Boolean','System.Single','System.Double','System.Byte','System.SByte'}) do
    known_importers[t] = import_export_as_is
end

--- @param handler ValueImporter
--- @return ValueImporter
local function boxed_enum_handler(handler)
    --- @type ValueImporter
    return {
        import = handler.import,
        export = function (src, target)
            if src ~= nil then
                return handler.export(src.value__, target)
            else
                return target
            end
        end,
    }
end

--- @param handler ValueImporter
--- @return ValueImporter
local function boxed_value_handler(handler)
    --- @type ValueImporter
    return {
        import = handler.import,
        export = function (src, target, options)
            if src ~= nil then
                return handler.export(src.m_value, target, options)
            else
                return target
            end
        end,
    }
end

known_importers['System.Guid'] =  {
    import = function (src, current)
        if not src then return current end
        --- @cast src string
        local success, parsed = utils.guid_try_parse(src)
        if success then
            -- note: we can't directly set the new guid, need to copy the backing fields instead
            current.mData1 = parsed.mData1
            current.mData2 = parsed.mData2
            current.mData3 = parsed.mData3
            current.mData4L = parsed.mData4L
            return current
        else
            return current or ValueType.new(type_guid)
        end
    end,
    export = function (src) return src:ToString() end,
}

known_importers['System.String'] = {
    import = function (src)
        --- @cast src string
        return sdk.create_managed_string(src)
    end,
    export = function (src) return src end,
}

---@param wrappedHandler ValueImporter
---@param exportCondition fun(src: any, target: any): useDefaultExport: boolean, defaultExportValue: string
---@return ValueImporter
local function conditional(wrappedHandler, exportCondition, importCondition)
    --- @type ValueImporter
    return {
        import = function (src, target)
            local defaultImport, importValue = importCondition(src, target)
            if defaultImport then
                return wrappedHandler.import(src, target)
            else
                return importValue
            end
        end,
        export = function (src, target, options)
            local defaultExport, exportValue = exportCondition(src, target)
            if defaultExport then
                return wrappedHandler.export(src, target, options)
            else
                return exportValue
            end
        end,
    }
end

--- @type ObjectFieldAccessors
local default_accessors = {
    get = function (object, fieldname) return object[fieldname] end,
    set = function (object, val, fieldname) object[fieldname] = val end,
}

local importer_factories
local get_handler

--- @type table<HandlerType, fun(meta: TypeCacheData, fullname: string): ValueImporter>
importer_factories = {
    [typecache.handlerTypes.readonly] = function ()
        return import_export_ignore
    end,

    [typecache.handlerTypes.value] = function (meta, fullname)
        local typedef = sdk.find_type_definition(fullname)

        --- @type [string, ValueImporter][]
        local fields = {}
        if meta.fields then
            -- we need to check for nil fields because the stupid JSON dump saves {} as null, sigh.
            for _, fieldData in ipairs(meta.fields) do
                local fieldName = fieldData[1]
                local fieldClass = fieldData[2]
                local submeta = typecache.get(fieldClass)
                local subhandler = get_handler(fieldClass, submeta)
                fields[#fields+1] = { fieldName, subhandler }
            end
        end

        --- @type ValueImporter
        return {
            export = function (src, target, options)
                target = target or {}
                for _, fieldData in ipairs(fields) do
                    local fn = fieldData[1]
                    target[fn] = fieldData[2].export(src[fn], options)
                end
                return target
            end,
            import = function (src, value)
                value = value or ValueType.new(typedef)
                for _, fieldData in ipairs(fields) do
                    local fn = fieldData[1]
                    value[fn] = fieldData[2].import(src[fn], value[fn])
                end
                return value
            end,
        }
    end,

    [typecache.handlerTypes.nullableValue] = function (meta, fullname)
        local typedef = sdk.find_type_definition(fullname)
        local implicit = typedef:get_method('op_Implicit')
        local innerHandler = get_handler(meta.elementType, typecache.get(meta.elementType))
        --- @type ValueImporter
        return {
            export = function (src, target, options)
                if src._HasValue then
                    return innerHandler.export(src._Value, nil, options)
                else
                    return 'null'
                end
            end,
            import = function (src, target)
                if target == nil then
                    print('WARNING: original nullable value was nil, this will likely not work...', fullname)
                    target = ValueType.new(typedef)
                end
                if src == 'null' or src == nil then
                    target._HasValue = false
                    return target
                else
                    target._HasValue = true
                    target._Value = innerHandler.import(src, target)
                    return target
                end
            end,
        }
    end,

    [typecache.handlerTypes.enum] = function (meta, fullname)
        return import_export_as_is
    end,

    [typecache.handlerTypes.array] = function (meta, fullname)
        local elementMeta = typecache.get(meta.elementType)
        local elementHandler = get_handler(meta.elementType, elementMeta)
        if elementMeta.type == typecache.handlerTypes.enum then
            elementHandler = boxed_enum_handler(elementHandler)
        elseif elementMeta.type == typecache.handlerTypes.value then
            elementHandler = boxed_value_handler(elementHandler)
        end
        --- @type ValueImporter
        return {
            export = function (src, target, options)
                if src == nil then return nil end
                local result = {}
                for idx, el in pairs(src) do
                    result[idx + 1] = elementHandler.export(el, nil, options)
                end
                return result
            end,
            import = function (src, target)
                if src and target and #src == target:get_size() then
                    for i, vv in ipairs(src) do
                        target[i - 1] = elementHandler.import(vv, target[i - 1])
                    end
                    return target
                end
                return helpers.create_array(meta.elementType, nil, utils.map(src or {}, function (itemData)
                    return elementHandler.import(itemData)
                end))
            end,
        }
    end,

    [typecache.handlerTypes.genericList] = function (meta, fullname)
        local elementHandler = get_handler(meta.elementType, typecache.get(meta.elementType))
        --- @type ValueImporter
        return {
            export = function (src, target, options)
                if src == nil then return nil end
                local result = {}
                if not src then return result end
                if src.get_Count == nil then
                    print('lol get count is nil wtf ', helpers.get_type(src), src:get_type_definition():get_full_name())
                end
                for idx = 0, src:get_Count() - 1 do
                    local el = src[idx]
                    result[idx + 1] = elementHandler.export(el, nil, options)
                end
                return result
            end,
            import = function (src, target)
                if not src then return target end
                if target == nil then
                    return target
                end

                while target:get_Count() > #src do
                    target:RemoveAt(target:get_Count() - 1)
                end
                local curcount = target:get_Count()
                for i, item in ipairs(src) do
                    if i <= curcount then
                        target[i - 1] = elementHandler.import(item, target[i - 1])
                    else
                        target:Add(elementHandler.import(item))
                    end
                end
                return target
            end,
        }
    end,

    [typecache.handlerTypes.dictionary] = function (meta, fullname)
        local typedef = usercontent.generics.typedef(fullname)
        if not typedef then return import_export_ignore end
        local keyMeta = typecache.get(meta.keyType)

        -- only allow strings and integer key types, ignore the rest
        local isIntegerKey = helpers.is_integer_type(meta.keyType)
        if meta.keyType ~= 'System.String' and not isIntegerKey then
            return import_export_ignore
        end

        local valueHandler = get_handler(meta.elementType, typecache.get(meta.elementType))

        return {
            import = function (src, target)
                target = target or helpers.create_generic_instance(typedef)
                -- remove any keys that aren't present in our import data
                local it = target:GetEnumerator()
                -- local keysToRemove = {}
                local handledKeys = {}
                while it:MoveNext() do
                    local key = it._current.key
                    local importValue = src[tostring(key)]
                    if importValue == nil then
                        -- we can't modify collections while iterating through them, need to do that in a separate loop
                        -- I'm thinking we want to keep existing values as is most of the time for mods, skip removal for now
                        -- keysToRemove[#keysToRemove+1] = key
                    else
                        handledKeys[key] = true
                        valueHandler.import(importValue, it._current.value)
                    end
                end
                -- for _, key in ipairs(keysToRemove) do target:Remove(key) end
                for key, valueData in pairs(src) do
                    local realKey = isIntegerKey and tonumber(key) or key
                    if not handledKeys[realKey] then
                        if target:ContainsKey(realKey) then
                            valueHandler.import(valueData, target[realKey])
                        else
                            target[realKey] = valueHandler.import(valueData)
                        end
                    end
                end
                return target
            end,
            export = function (src, target, options)
                if src == nil then return 'null' end
                target = target or {}

                for pair in utils.enumerate(src) do
                    target[pair.key] = valueHandler.export(pair.value, nil, options)
                end
                return target
            end,
        }
        -- return import_export_ignore
    end,

    [typecache.handlerTypes.object] = function (meta, fullname)
        if meta.specialType == 2 then
            local resourceClass = fullname:gsub('Holder$', '')
            known_importers[fullname] = resource(resourceClass)
            return known_importers[fullname]
        end

        local typeOverrides = type_settings.type_settings[fullname]

        -- immediately store the handler so we don't die of recursion
        local resultHandler = {}
        known_importers[fullname] = resultHandler

        if typeOverrides and typeOverrides.abstract then
            --- @type table<string, ValueImporter>
            local subtype_lookup = {}
            for _, concrete in pairs(typeOverrides.abstract) do
                if concrete == fullname then re.msg('Oi! Invalid abstract self-reference ' .. fullname) end
                local subhandler = get_handler(concrete)
                local subtype = sdk.find_type_definition(concrete)
                if not subtype then
                    print('ERROR: invalid abstract subtype', fullname, concrete)
                else
                    subtype_lookup[subtype:get_full_name()] = subhandler
                end
            end

            resultHandler.export = function (src, target, options)
                target = target or {}
                local typename = src:get_type_definition():get_full_name()
                target['$type'] = typename
                return subtype_lookup[typename].export(src, target, options)
            end
            resultHandler.import = function (src, target)
                if not src then return target end
                local subtype = src['$type']
                if not subtype then
                    print('ERROR: import missing subtype for abstract class', fullname)
                    return target
                end
                if target and target.get_type_definition and target:get_type_definition():get_full_name() ~= subtype then
                    print('Must re-create, instance type does not match:', target:get_type_definition():get_full_name(), ' should be', subtype)
                    target = helpers.create_instance(subtype)
                end
                return subtype_lookup[subtype].import(src, target)
            end
            return resultHandler
        end

        --- @type [string, ValueImporter, ObjectFieldAccessors, string ][]
        local fields = {}
        local fieldOverrides = typeOverrides and typeOverrides.fields
        if meta.fields then
            -- we need to check for empty fields because the stupid JSON dump saves {} as null, sigh.

            for _, fieldData in ipairs(meta.fields) do
                local fieldName = fieldData[1]
                local flags = fieldData[3]
                local override = fieldOverrides and fieldOverrides[fieldName] or {}

                if (flags & typecache.fieldFlags.ImportEnable) ~= 0 then
                    local fieldClass = fieldData[2]
                    if override.import_handler then
                        fields[#fields+1] = { fieldName, override.import_handler, override and override.accessors or default_accessors, fieldClass }
                    else
                        local submeta = typecache.get(fieldClass)
                        -- print('fetching field handler', fullname .. ':', fieldClass, fieldName) -- DEBUGGING
                        local subhandler = get_handler(fieldClass, submeta)
                        fields[#fields+1] = { fieldName, subhandler, override and override.accessors or default_accessors, fieldClass }
                    end
                end
            end
        end

        resultHandler.export = function (src, target, options)
            if src == nil then return 'null' end
            target = target or {}
            for _, fieldData in ipairs(fields) do
                local field = fieldData[1]
                local acc = fieldData[3]
                local val = acc.get(src, field)
                if val == nil then
                    target[field] = 'null'
                else
                    target[field] = fieldData[2].export(val, target[field], options)
                end
            end
            return target
        end

        resultHandler.import = function (src, target)
            if src == nil then return target end
            if src == 'null' then return nil end

            target = target or helpers.create_instance(fullname)
            for _, fieldData in ipairs(fields) do
                local field = fieldData[1]
                local acc = fieldData[3]
                local fieldCur = acc.get(target, field)
                local fieldNewval = fieldData[2].import(src[field], fieldCur)
                acc.set(target, fieldNewval, field)
            end
            return target
        end

        if meta.specialType == 1 then
            local fullImport, fullExport = resultHandler.import, resultHandler.export
            resultHandler.import = function (src, target)
                if type(src) == 'string' then
                    if src == 'null' then
                        return nil
                    else
                        return sdk.create_userdata(fullname, src):add_ref()
                    end
                else
                    return fullImport(src, target)
                end
            end
            resultHandler.export = function (src, target, options)
                if src == nil then
                    return {}
                end
                if not options or not options.raw then
                    local uri = src:get_URI()
                    if uri and uri ~= '' then
                        -- URI or path? are they equivalent?
                        return uri
                    end
                end
                -- TODO need to test whether propagating options is fine for all cases, or do we want to only propagate for whitelisted fields?
                return fullExport(src, target, options)
            end
        end

        return resultHandler
    end,
}

--- @param classname string
--- @param meta TypeCacheData|nil
--- @return ValueImporter
get_handler = function(classname, meta)
    local handler = known_importers[classname]
    if not handler then
        meta = meta or typecache.get(classname)
        if not meta then print('ERROR: invalid import handler type', classname) return nil end

        local stg = type_settings.type_settings[classname]
        if stg and stg.import_handler then
            known_importers[classname] = stg.import_handler
            return stg.import_handler
        else
            local factory = importer_factories[meta.type]
            handler = factory(meta, classname)
            known_importers[classname] = handler
            return handler
        end
    end
    return handler
end

--- @param classname string Classname of the target object
--- @param importData any The data to import from
--- @param targetInstance any An optional existing instance to import the data into
--- @return any
local function import(classname, importData, targetInstance)
    local handler = get_handler(classname)
    if not handler then return {} end
    return handler.import(importData, targetInstance)
end

--- Export a single managed object to lua table data
--- @param object any The object to export
--- @param classname string|nil Will be inferred from the given object if not specified
--- @param options ExportOptions|nil
--- @return any
local function get_exported(object, classname, options)
    classname = classname or helpers.get_type(object)
    if classname == nil then return {} end

    local handler = get_handler(classname)
    if not handler then return {} end
    return handler.export(object, nil, options)
end

--- Export a lua table of items, each of the items will be exported individually and returned in a new table.
--- @param table table The object to export
--- @param classname string|nil Will be inferred from the given object if not specified
--- @return table
local function get_exported_array(table, classname)
    local list = {}
    for i, item in pairs(table) do
        list[i] = get_exported(item, classname)
    end
    return list
end

usercontent.import_handlers = {
    get_handler = get_handler,
    export = get_exported,
    export_table = get_exported_array,
    import = import,

    create_conditional = conditional,
    common = {
        resource = resource,
    }
}

return usercontent.import_handlers