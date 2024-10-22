if type(_shadowcookie_utils) ~= 'nil' then return _shadowcookie_utils end

local MessageManager = sdk.get_managed_singleton('app.MessageManager')
local CharacterManager = sdk.get_managed_singleton('app.CharacterManager')

--- @param str string
--- @param substr string
local function str_starts_with(str, substr)
    if str == nil then
        print('cannot check starts with, str is nil', str, substr)
        return false
    end
    return string.sub(str, 1, #substr) == substr
end

--- @param n number
--- @param decimals integer|nil
local function float_round(n, decimals)
    if decimals == nil then decimals = 0 end
    local mult = 10 ^ decimals
    return math.floor(n * mult + 0.5) / mult
end

local function dictionary_get_values(dict)
    local result = {}
    local entries = dict:get_field('_entries')
    -- an empty dictionary can have a null entries field
    if not entries then return {} end

    for k, entry in pairs(entries) do
        -- the key is the dictionary hash, if it's 0 then it's an empty entry
        if entry:get_field('key') ~= 0 then
            local item = entry:get_field('value')
            -- print_type_info(item)
            result[k] = item
        end
    end

    return result
end

local function dictionary_to_table(dict)
    local result = {}
    local enumerator = dict:GetEnumerator()
    while enumerator:MoveNext() do
        local current = enumerator:get_Current()
        result[current.key] = current.value
    end

    return result
end

local function table_index_of(table, value)
    for i, v in ipairs(table) do
        if v == value then return i end
    end
    return 0
end

--- Find the index of a table element, or 0 if not found
--- @generic T
--- @param table T[]
--- @param func fun(item: T, index: integer): boolean
--- @return integer
local function table_find_index(table, func)
    for i, v in ipairs(table) do
        if func(v, i) then return i end
    end
    return 0
end

--- @generic T
--- @param table T[]
--- @param func fun(item: T, index: integer): boolean
--- @return T|nil
local function table_find(table, func)
    for i, v in ipairs(table) do
        if func(v, i) then return v end
    end
    return nil
end

local function assoc_table_count(tbl)
    if tbl == nil then return -1 end
    local cnt = 0
    for _,_ in pairs(tbl) do cnt = cnt + 1 end
    return cnt
end

local function table_binary_search(table, value)
    local iStart, iEnd, iMid = 1, #table, 0
    while iStart <= iEnd do
        iMid = math.floor((iStart + iEnd) / 2)
        local value2 = table[iMid]
        if value == value2 then return iMid end

        if value2 > value then
            iEnd = iMid - 1
        else
            iStart = iMid + 1
        end
    end
    return 0
    -- return table_binary_search_inner(table, value, 1, #table)
end
local function table_binary_insert(tt, value)
    --  Initialise numbers
    local a, b, mid, iState = 1, #tt, 1, 0
    -- Get insert position
    while a <= b do
        -- calculate middle
        mid = math.floor((a + b) / 2)
        -- compare
        if value < tt[mid] then
            b, iState = mid - 1, 0
        else
            a, iState = mid + 1, 1
        end
    end
    table.insert(tt, (mid + iState), value)
    return (mid + iState)
end

local function flip_table_keys_values(table)
    local l = {}
    for k, v in pairs(table) do
        l[v] = k
    end
    return l
end

---Get an associative table keys, sorted
local function get_sorted_table_keys(table)
    local list = {}
    local n = 1
    for k, v in pairs(table) do
        list[n] = k
        n = n + 1
    end
    for i = 1, n - 1 do
        for j = i + 1, n - 1 do
            if list[i] > list[j] then
                list[i], list[j] = list[j], list[i]
            end
        end
    end
    return list
end

---Get an associative table values, sorted
local function get_sorted_table_values(table)
    local list = {}
    local n = 1
    for _, k in pairs(table) do
        list[n] = k
        n = n + 1
    end
    for i = 1, n - 1 do
        for j = i + 1, n - 1 do
            if list[i] > list[j] then
                list[i], list[j] = list[j], list[i]
            end
        end
    end
    return list
end

---Sort an index-base table by values
local function get_sorted_list_table(tbl, sortKey)
    local tbl_out = {}
    for _, item in ipairs(tbl) do
        tbl_out[#tbl_out+1] = item
    end

    table.sort(tbl_out, function (a, b) return a[sortKey] > b[sortKey] end)
    return tbl_out
end

local function is_assoc_table(tbl)
    return type(tbl) == 'table' and next(tbl) ~= 1
end

---@param source table
---@param target table
---@return table
local function merge_into_table(source, target)
    target = target or {}
    for key, targetVal in pairs(target) do
        local newval = source[key]
        if newval ~= nil then
            if newval == 'null' then newval = nil end
            if type(targetVal) == 'table' then
                if type(newval) ~= 'table' then newval = {} end
                if is_assoc_table(newval) then
                    target[key] = merge_into_table(newval, targetVal or {})
                else
                    target[key] = newval
                end
            else
                target[key] = newval
            end
        end
    end
    return target
end

---@generic TSrc : table
---@generic TTarget : table
---@param target TTarget
---@param source TSrc
---@return TTarget|TSrc
local function table_assign(target, source)
    if target == nil and source == nil then return nil end
    target = target or {}
    for key, sourceValue in pairs(source) do
        if sourceValue ~= nil then
            if sourceValue == 'null' then sourceValue = nil end
            target[key] = sourceValue
        end
    end
    return target
end

--- Remove all elements of a table while keeping the same instance
local function clear_table(tbl)
    if tbl then
        for k, _ in pairs(tbl) do
            tbl[k] = nil
        end
    end
end

---@generic T : table
---@param source T : table
---@return T
local function clone_table(source)
    local target = {}
    for key, newval in pairs(source) do
        if type(newval) == 'table' then
            target[key] = clone_table(newval)
        else
            target[key] = newval
        end
    end
    return target
end

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

local function generic_list_to_managed_array(list)
    return list:call('ToArray')
end

local function table_remove(tbl, element)
    for i, v in ipairs(tbl) do
        if v == element then
            table.remove(tbl, i)
            return true
        end
    end
    return false
end

--- @generic T : table
--- @param table table<any, T>
--- @return T[]
local function table_values(table)
    local out = {}
    for i, v in pairs(table) do
        out[#out+1] = v
    end
    return out
end

local function generic_list_to_itable(list)
    if type(list) == 'table' then return list end
    local count = list:call('get_Count')
    local items = list:get_field('_items')
    local arr = {}
    for i = 1, count do
        arr[#arr + 1] = items[i - 1]
    end
    return arr
end

---@param typename string
---@param source REManagedObject An existing instance of a list, because REF doesn't support creating generic instances
---@param items table
---@return REManagedObject System.Collections.Generic.List<{typename}>
local function create_generic_list(typename, source, items)
    local arr = sdk.create_managed_array(typename, #items):add_ref()
    for i, item in ipairs(items) do
        arr:set_Item(i, item)
    end
    local copy = source:MemberwiseClone():add_ref()
    copy._items = arr
    copy._size = #items
    return copy
end

---@param typename string
---@param items table
---@return SystemArray
local function create_array(typename, items)
    if typename:find('`') then
        return nil
    end
    local arr = sdk.create_managed_array(typename, #items):add_ref()
    for i, item in ipairs(items) do
        arr[i - 1] = item
    end
    return arr
end

---@param odds number [0-1] value of how likely a chance you want
local function chance(odds)
    return math.random() < odds
end

---@generic T : any
---@generic TRes : any
---@param tbl T[]
---@param func fun(value: T, index: number): TRes
---@return TRes[]
local function map(tbl, func)
    if not tbl then return {} end
    local outtbl = {}
    local outi = 1
    for i, v in ipairs(tbl) do
        if v ~= nil then
            outtbl[outi] = func(v, i)
            outi = outi + 1
        end
    end
    return outtbl
end

---@param tbl table[]
---@param field string
---@return any[]
local function pluck(tbl, field)
    if not tbl then return {} end
    local outtbl = {}
    local outi = 1
    for i, v in ipairs(tbl) do
        if v ~= nil then
            outtbl[outi] = v[field]
            outi = outi + 1
        end
    end
    return outtbl
end

---@generic T : any
---@generic TRes : any
---@param tbl table<integer|string, T>
---@param func fun(value: T, index: number|string): TRes
---@return table<integer|string, TRes>
local function map_assoc(tbl, func)
    if not tbl then return {} end
    local outtbl = {}
    for i, v in pairs(tbl) do
        if v ~= nil then
            outtbl[i] = func(v, i)
        end
    end
    return outtbl
end

---@generic T : any
---@param tbl T[]
---@param func nil|fun(value: T): boolean
---@return T[]
local function filter(tbl, func)
    local outtbl = {}
    local cnt = 1
    for i, v in ipairs(tbl) do
        if v ~= nil and (not func or func(v)) then
            outtbl[cnt] = v
            cnt = cnt + 1
        end
    end
    return outtbl
end

local function table_contains(tbl, item)
    for _, v in pairs(tbl) do
        if v == item then return true end
    end
    return false
end

---@generic T : any
---@param tbl T[]
---@param func fun(value: T): boolean
---@return T|nil
local function first_where(tbl, func)
    for i, v in pairs(tbl) do
        if func(v) then return v end
    end
    return nil
end

---Get the first element VALUE of a list/array/table. Seamlessly handles 0-indexex array (RE engine system array)
---@generic T : any
---@param list T[]
---@return T|nil
local function first(list)
    if not list then return nil end
    if list[0] ~= nil then return list[0] end
    for _, v in ipairs(list) do return v end
    return nil
end

---@generic T : any
---@param tbl T[]
---@param func fun(value: T): boolean
---@return boolean
local function exists(tbl, func)
    for i, v in ipairs(tbl) do
        if func(v) then return true end
    end
    return false
end

---@generic T : table
---@param tbl T[]
---@param groupKey string|integer
---@param valKey string|integer|nil
---@return table<any, T>
local function group_by_unique(tbl, groupKey, valKey)
    local outtbl = {}
    for i = 1, #tbl do
        local item = tbl[i]
        if outtbl[item[groupKey]] then
            print('WARNING: Non-unique group key', item[groupKey], item, valKey and item[valKey])
        else
            outtbl[item[groupKey]] = (valKey == nil and item or item[valKey])
        end
    end
    return outtbl
end

---@generic T : table
---@param tbl T[]
---@param groupKey string
---@param valKey string|nil
---@return table<any, T[]>
local function group_by(tbl, groupKey, valKey)
    local outtbl = {}
    for i = 1, #tbl do
        local item = tbl[i]
        local key = item[groupKey]
        local grp = outtbl[key] or {}
        grp[#grp+1] = valKey and item[valKey] or item
        outtbl[key] = grp
    end
    return outtbl
end

local type_guid = sdk.find_type_definition('System.Guid')
local guidParse = type_guid:get_method('Parse(System.String)')

--- @param str string
local function try_parse_guid(str)
    local success, guid = pcall(function() return guidParse:call(nil, str) end)
    -- NOTE: might be better to figure out how to use TryParse instead
    success = success and str == guid:ToString()
    return success, guid
end

--- @param str string
local function parse_guid(str)
    return guidParse:call(nil, str)
end

---@param messageGuid System.Guid A GUID string
---@param args any[]|nil
---@return string
local function translate_message_guid(messageGuid, args)
    if not args or #args == 0 then
        return MessageManager:getMessage(messageGuid)
    end
    print("WARNING: function doesn't support args yet.")
    args = {}
    return messageGuid:ToString()
    -- local arr = sdk.create_managed_array('System.Object', #args)
    -- local guiManager = sdk.get_managed_singleton('app.GuiManager')
    -- return guiManager:call('get_Dialog'):call('getFormatMsg', messageGuid, arr)
end

---@param messageGuid string A GUID string
---@param args any[]|nil
---@return string
local function translate_message(messageGuid, args)
    return translate_message_guid(parse_guid(messageGuid), args)
end

local getCharaName = sdk.find_type_definition("app.GUIBase"):get_method("getName(app.CharacterID)")
local function translate_character_name(characterId)
    return getCharaName:call(nil, characterId)
end

local ItemManager = sdk.get_managed_singleton('app.ItemManager')
local getItemData = sdk.find_type_definition('app.ItemManager'):get_method('getItemData(System.Int32)')
local function translate_item_name(itemId)
    local id = getItemData:call(ItemManager, itemId)
    return id and id:call('get_Name')
end

--- Better toJson function that returns an actual value instead of nil for empty tables
---@param obj table
---@param tableIsArray boolean|nil
---@return string
local function tojson(obj, tableIsArray)
    if type(obj) == 'table' and next(obj) == nil then
        return tableIsArray and '[]' or '{}'
    else
        return json.dump_string(obj)
    end
end

-- workaround since lua doesn't let us delete files
local function file_delete(fn)
    fs.write(fn, 'null')
end

-- workaround since lua doesn't let us properly see if a file exists
local function file_exists(fn)
    local previousContents = fs.read(fn)
    return previousContents and previousContents ~= ''
end

local function log_all(...)
    local out = '__LOG__'
    for _, arg in ipairs({...}) do
        out = out .. ' ' .. tostring(arg)
    end
    log.info(out)
    print(out)
end

local function string_join(sep, ...)
    return table.concat({...}, sep)
end

--- @param withTimezone boolean|nil
--- @return string
local function get_irl_timestamp(withTimezone)
    local timenow = os.date(withTimezone and '!%Y-%m-%d %H:%M:%S UTC' or '!%Y-%m-%d %H-%M-%S')
    --- @cast timenow string
    return timenow
end

local function is_in_title_screen()
    return CharacterManager:get_ManualPlayer() == nil
end

--- @param folder REManagedObject via.Folder
--- @return via.Transform[] children
local function folder_get_children(folder)
    local it = folder:call('get_Children') -- returns a: via.Folder.<get_Children>d__2
    local enumerator = it:call('System.Collections.IEnumerable.GetEnumerator')
    local getCurrent = enumerator:get_type_definition():get_method('System.Collections.Generic.IEnumerator<via.Transform>.get_Current')
    local list = {}
    while enumerator:MoveNext() do
        list[#list+1] = getCurrent:call(enumerator)
    end
    it:call('System.IDisposable.Dispose')
    return list
end

local getComponent = sdk.find_type_definition('via.GameObject'):get_method('getComponent(System.Type)')
local function get_gameobject_component(gameObject, componentType)
    return getComponent:call(gameObject, sdk.typeof(componentType))
end

--- comment
--- @param array SystemArray
--- @param itemType RETypeDefinition|string
--- @return REManagedObject[]
local function system_array_of_type(array, itemType)
    if type(itemType) == 'string' then itemType = sdk.find_type_definition(itemType) end
    local list = {}
    for _, e in pairs(array) do
        if e:get_type_definition() == itemType then list[#list+1] = e end
    end
    return list
end

local function enumerator_to_table(enumerator)
    local list = {}
    while enumerator:MoveNext() do
        list[#list+1] = enumerator:get_Current()
    end

    return list
end

_shadowcookie_utils = {
    log = log_all,
    string_join = string_join,
    get_irl_timestamp = get_irl_timestamp,

    str_starts_with = str_starts_with,
    float_round = float_round,
    chance = chance,

    file_delete = file_delete,
    file_exists = file_exists,

    generate_enum = generate_enum_label_to_value,

    generic_list_to_itable = generic_list_to_itable,
    generic_list_to_managed_array = generic_list_to_managed_array,
    get_sorted_table_keys = get_sorted_table_keys,
    get_sorted_table_values = get_sorted_table_values,
    get_sorted_list_table = get_sorted_list_table,
    flip_table_keys_values = flip_table_keys_values,
    dictionary_get_values = dictionary_get_values,
    dictionary_to_table = dictionary_to_table,
    merge_into_table = merge_into_table,
    table_assign = table_assign,
    clone_table = clone_table,
    table_index_of = table_index_of,
    table_find_index = table_find_index,
    table_find = table_find,
    assoc_table_count = assoc_table_count,
    is_assoc_table = is_assoc_table,
    table_binary_search = table_binary_search,
    table_sorted_insert = table_binary_insert,
    group_by_unique = group_by_unique,
    group_by = group_by,
    clear_table = clear_table,
    first = first,
    first_where = first_where,
    exists = exists,
    filter = filter,
    table_contains = table_contains,
    table_values = table_values,
    table_remove = table_remove,
    map = map,
    pluck = pluck,
    map_assoc = map_assoc,

    tojson = tojson,

    create_array = create_array,
    create_generic_list = create_generic_list,
    system_array_of_type = system_array_of_type,
    enumerator_to_table = enumerator_to_table,

    is_in_title_screen = is_in_title_screen,

    translate_guid = translate_message_guid,
    translate = translate_message,
    guid_try_parse = try_parse_guid,
    guid_parse = parse_guid,
    translate_character_name = translate_character_name,
    translate_item_name = translate_item_name,
    get_gameobject_component = get_gameobject_component,
    folder_get_children = folder_get_children,
}

return _shadowcookie_utils
