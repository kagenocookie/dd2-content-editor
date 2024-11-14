if type(_userdata_DB) == 'nil' then _userdata_DB = {} end
if _userdata_DB.enums then return _userdata_DB.enums end

local core = require('content_editor.core')
local events = require('content_editor.events')
local utils = require('content_editor.utils')

--- @class EnumSummary
--- @field enumName string
--- @field labels string[]
--- @field displayLabels string[]|nil
--- @field values integer[]
--- @field labelToValue table<string, integer>
--- @field valueToLabel table<integer, string>
--- @field valueToDisplayLabels table<integer, string>|nil
--- @field find_index_by_label fun(label: string): integer
--- @field find_index_by_value fun(value: integer): integer
--- @field get_label fun(value: integer): string
--- @field set_display_labels fun(valueLabelPairs: [integer, string])
--- @field set_display_label fun(value: integer, displayLabel: string)
--- @field orderByValue boolean
--- @field is_virtual boolean
--- @field resort fun()

--- @type table<string, EnumSummary>
local enumsContainer = {} -- Storage for all loaded enums

--- @type table<string, EnumSummary>
local originalEnums = {} -- Storage for the game-original values of enums so we could revert changes later

--- @type table<string, EnumSummary>
local editableEnums = {} -- List of enums that are registered as editable, meaning they can read custom display labels from JSON files on disk

--- @type table<string, table<string, fun(enum: EnumSummary)>>
local enum_deps = {}

--- @param enumName string
local function trigger_enum_dependencies(enumName)
    local enum = enumsContainer[enumName]
    if enum then
        local deps = enum_deps[enumName]
        if deps then
            for dep_name, dep in pairs(deps) do
                -- print('triggering enum dependency', enumName, dep_name)
                dep(enum)
            end
        end
    end
end

--- @param enum EnumSummary
local function _enum_resort(enum)
    -- print('resort', enum.enumName)
    if enum.orderByValue then
        utils.clear_table(enum.values)
        utils.table_assign(enum.values, utils.get_sorted_table_values(enum.labelToValue))
        utils.clear_table(enum.labels)
        enum.displayLabels = enum.valueToDisplayLabels and {} or nil
        enum.valueToLabel = utils.flip_table_keys_values(enum.labelToValue)
        for i, value in ipairs(enum.values) do
            enum.labels[i] = enum.valueToLabel[value]
            if enum.valueToDisplayLabels then
                local val = enum.values[i]
                enum.displayLabels[i] = enum.valueToDisplayLabels[val] or enum.labels[i]
            end
        end
    else
        utils.clear_table(enum.labels)
        utils.table_assign(enum.labels, utils.get_sorted_table_keys(enum.labelToValue))
        utils.clear_table(enum.values)
        enum.displayLabels = enum.valueToDisplayLabels and {} or nil
        for i, label in ipairs(enum.labels) do
            enum.values[i] = enum.labelToValue[label]
            if enum.valueToDisplayLabels then
                local val = enum.values[i]
                enum.displayLabels[i] = enum.valueToDisplayLabels[val] or label
            end
        end
    end
    trigger_enum_dependencies(enum.enumName)
end

--- @param labelToValue table<string, integer>
--- @param enumName string
--- @param orderByValue boolean|nil Whether the enum should order by value (true) or by label (false). If unset, will automatically decide based on enum size (< 10 = order by value)
--- @return EnumSummary
local function create_enum_summary_from_table(labelToValue, enumName, orderByValue)
    if orderByValue == nil then
        local itemCount = 0
        for _, _ in pairs(labelToValue) do itemCount = itemCount + 1 if itemCount >= 10 then break end end
        orderByValue = itemCount < 10
    end
    local valueToLabel = utils.flip_table_keys_values(labelToValue)

    --- @type EnumSummary
    --- @diagnostic disable-next-line: missing-fields
    local result = {
        enumName = enumName,
        labels = {},
        values = {},
        labelToValue = labelToValue,
        valueToLabel = valueToLabel,
        valueToDisplayLabels = nil,
        displayLabels = nil,
        is_virtual = false,
        orderByValue = orderByValue
    }

    result.resort = function() _enum_resort(result) end
    _enum_resort(result)

    result.find_index_by_label = function(label)
        for i = 1, #result.labels do
            if result.labels[i] == label then return i end
        end
        return -1
    end
    result.find_index_by_value = function(value)
        for i = 1, #result.values do
            if result.values[i] == value then return i end
        end
        return -1
    end

    result.get_label = function(value)
        return result.valueToDisplayLabels and result.valueToDisplayLabels[value] or result.displayLabels and result.displayLabels[result.find_index_by_value(value)] or result.valueToLabel[value] or tostring(value)
    end
    result.set_display_labels = function(valueLabelPairs)
        if not result.valueToDisplayLabels then result.valueToDisplayLabels = {} end
        for _, kv in ipairs(valueLabelPairs) do
            result.valueToDisplayLabels[kv[1]] = kv[2]
        end
        result.resort()
    end
    result.set_display_label = function(value, displayLabel)
        if not result.valueToDisplayLabels then result.valueToDisplayLabels = {} end
        if result.valueToLabel[value] then
            result.valueToDisplayLabels[value] = displayLabel
            local idx = result.find_index_by_value(value)
            if idx > 0 then
                if result.displayLabels == nil then result.displayLabels = {} end
                result.displayLabels[idx] = displayLabel
            end
        end
        result.resort()
    end
    return result
end

--- @param typename string
--- @param filter nil|fun(key: string, value: integer): boolean
--- @return table<string, integer>
local function generate_enum_label_to_value(typename, filter)
    local t = sdk.find_type_definition(typename)
    if not t then return {} end

    local fields = t:get_fields()
    local enum = {}

    for _, field in ipairs(fields) do
        if field:is_static() then
            local name = field:get_name()
            local raw_value = field:get_data(nil)
            if not filter or filter(name, raw_value) then
                enum[name] = raw_value
            end
        end
    end

    return enum
end

--- @param typename string
--- @param orderByValue boolean|nil
--- @return EnumSummary
local function generate_enum_utils(typename, orderByValue)
    local enum = generate_enum_label_to_value(typename)
    local result = create_enum_summary_from_table(enum, typename, orderByValue)
    return result
end

--- comment
--- @param sourceEnum string
--- @param key string
--- @param callback fun(enum: EnumSummary)
local function add_enum_dependency(sourceEnum, key, callback)
    local deps = enum_deps[sourceEnum]
    if not deps then
        deps = {}
        enum_deps[sourceEnum] = deps
    end
    deps[key] = callback
end

--- @param enum EnumSummary
--- @param filter fun(label: string, value: integer): boolean
--- @return EnumSummary
local function generate_enum_subset(enum, name, filter)
    -- print('generating subset', enum.enumName, name)
    local labelToValue = {}
    for label, value in pairs(enum.labelToValue) do
        if filter(label, value) then
            labelToValue[label] = value
        end
    end

    add_enum_dependency(enum.enumName, 'subset_' .. name, function (updatedEnum)
        generate_enum_subset(updatedEnum, name, filter)
    end)

    local newEnum = enumsContainer[name]
    if not newEnum then
        newEnum = create_enum_summary_from_table(labelToValue, name)
        enumsContainer[name] = newEnum
    end
    newEnum.set_display_labels(utils.map(newEnum.values, function (value)
        return { value, enum.get_label(value) }
    end))

    return newEnum
end



--- Load enum override data into an enum summary
--- @param enum EnumSummary
--- @param enumData EnumDefinitionFile
local function load_enum(enum, enumData)
    if enumData.values then
        -- add any values from the data that are missing from the enum, keep anything that's already there as is
        for label, value in pairs(enumData.values) do
            if not enum.labelToValue[label] then
                enum.labelToValue[label] = value
            end
        end
    end
    if enumData.displayLabels then
        if not enum.valueToDisplayLabels then enum.valueToDisplayLabels = {} end
        for label, display in pairs(enumData.displayLabels) do
            local value = enum.labelToValue[label]
            if value ~= nil then
                enum.valueToDisplayLabels[value] = display
            else
                print('Unknown enum label', enum.enumName, label)
            end
        end
    end
    if enumData.orderByValue ~= nil then
        enum.orderByValue = enumData.orderByValue
    end
    enum.resort()
    return enum
end

---@param enum EnumSummary
---@return table
local function generate_enum_dump(enum)
    --- @type EnumDefinitionFile
    local data = {
        enumName = enum.enumName,
        values = {},
        displayLabels = {},
        isVirtual = enum.is_virtual,
    }

    for label, value in pairs(enum.labelToValue) do
        local displayLabel = enum.get_label(value)
        if label ~= displayLabel then
            data.displayLabels[label] = displayLabel
        end
        data.values[label] = value
    end
    return data
end

--- @param name string
local function dump_single_enum(name)
    local enum = enumsContainer[name]
    local dump_path = core.resolve_file('dump', 'enums'):gsub('.json', '/' .. name .. '.json');
    json.dump_file(dump_path, generate_enum_dump(enum))
end

local function dump_all_enums()
    for name, enum in pairs(enumsContainer) do
        dump_single_enum(name)
    end
end

--- @param name string
local function save_enum(name)
    local enum = enumsContainer[name]
    local dump_path = core.resolve_file('enum', name);
    json.dump_file(dump_path, generate_enum_dump(enum))
end

--- Find or generate an enum by its classname
---@param enumName string
---@param default_sort_by_value boolean|nil
---@return EnumSummary
local function get_or_generate_enum(enumName, default_sort_by_value)
    local enum = enumsContainer[enumName]
    if not enum then
        enum = generate_enum_utils(enumName, default_sort_by_value)
        enumsContainer[enumName] = enum
    end
    return enum
end

local function refresh_modded_enums()
    local enums = fs.glob(core.get_glob_regex('enum'))
    local pathlen = core._basepath:len() + 7 -- /enums/
    for _, enumPath in ipairs(enums) do
        local enumData = json.load_file(enumPath) --- @type nil|EnumDefinitionFile
        if enumData then
            local enumName = enumPath:sub(pathlen, -6)
            local enum
            if enumData.isVirtual then
                enum = enumsContainer[enumName] or create_enum_summary_from_table(enumData.values or {}, enumName, enumData.orderByValue)
                enum.is_virtual = true
            else
                enum = get_or_generate_enum(enumName)
            end

            load_enum(enum, enumData)
            events.emit('enum_updated', enum)
            -- print('Updated enum', enumName)
        end
    end
end

--- Find or generate a virtual enum (not an actual ingame enum, but still a set of data that can be treated as one for editor purposes)
--- Virtual enums can define label overrides
---@param enumName string
---@param labelToValue table<string, integer>
---@param default_sort_by_value boolean|nil
---@return EnumSummary
local function get_or_generate_virtual_enum(enumName, labelToValue, default_sort_by_value)
    if enumsContainer[enumName] then return enumsContainer[enumName] end

    local enum = create_enum_summary_from_table(labelToValue, enumName, default_sort_by_value)
    enum.is_virtual = true
    enumsContainer[enumName] = enum
    return enum
end


--- @param source EnumSummary
--- @return EnumSummary
local function clone_enum(source)
    local newEnum = create_enum_summary_from_table(utils.clone_table(source.labelToValue), source.enumName)
    newEnum.displayLabels = utils.clone_table(source.displayLabels)
    return newEnum
end

--- @param targetEnumName string
--- @param data EnumEnhancement
local function enhance_enum(targetEnumName, data)
    local enum = enumsContainer[targetEnumName]
    if not enum then
        print('ERROR: attempted to enhance unknown enum ' .. targetEnumName .. '. Maybe you called enhance_enum() too fast?')
        return
    end

    if not originalEnums[targetEnumName] then
        originalEnums[targetEnumName] = clone_enum(enum)
    end

    utils.table_assign(enum.labelToValue, data.labelToValue)
    utils.table_assign(enum.valueToLabel, utils.flip_table_keys_values(data.labelToValue))
    enum.resort()
end

--- Replace all values and labels of an existing enum
--- @param targetEnum EnumSummary
--- @param items [integer, string, string|nil][]
--- @param resort boolean|nil Whether the enum's default sort should be executed after, or false if the newly given order should be kept
local function replace_enum_items(targetEnum, items, resort)
    utils.clear_table(targetEnum.values)
    utils.clear_table(targetEnum.labels)
    if not items[1] then
        utils.clear_table(targetEnum.valueToLabel)
        utils.clear_table(targetEnum.labelToValue)
        targetEnum.displayLabels = nil
        return targetEnum
    end
    targetEnum.displayLabels = items[1][3] and {} or nil
    for idx, item in ipairs(items) do
        targetEnum.values[idx] = item[1]
        targetEnum.labels[idx] = item[2]
        if targetEnum.displayLabels then
            targetEnum.displayLabels[idx] = item[3] or item[2]
        end
        targetEnum.valueToLabel[item[1]] = item[2]
        targetEnum.labelToValue[item[2]] = item[1]
    end
    if resort then targetEnum.resort() end
    return targetEnum
end

--- Link / shallow copy all of an enum into another enum. Any changes made to either of them will affect the other one.
--- @param name string
--- @param enum EnumSummary
local function override_enum(name, enum)
    -- am not yet sure whether we want to keep the objects separated (so the names can differ), or just hard replace the object
    -- separate objects is a bit more effort since we can't reassign any values; unless we restructure the enum summary type
    enumsContainer[name] = enum
    -- local defaultEnum = get_or_generate_enum(name)
    -- defaultEnum.labelToValue = enum.labelToValue
    -- defaultEnum.valueToDisplayLabels = enum.valueToDisplayLabels
    -- defaultEnum.valueToLabel = enum.valueToLabel
    -- defaultEnum.labels = enum.labels
    -- defaultEnum.values = enum.values
end

_userdata_DB.enums = {
    all = enumsContainer,

    get_enum = get_or_generate_enum,
    get_virtual_enum = get_or_generate_virtual_enum,
    refresh = refresh_modded_enums,
    enhance_enum = enhance_enum,
    load_enum = load_enum,
    replace_items = replace_enum_items,
    dump_all_enums = dump_all_enums,
    dump_enum = dump_single_enum,
    save_enum = save_enum,
    override_enum = override_enum,

    create_enum = create_enum_summary_from_table,
    create_subset = generate_enum_subset,
}

return _userdata_DB.enums
