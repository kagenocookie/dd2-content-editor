if type(usercontent) == 'nil' then usercontent = {} end
if usercontent.utils then return usercontent.utils end

local MessageManager = sdk.get_managed_singleton('app.MessageManager')

--- @param n number
--- @param decimals integer|nil
local function float_round(n, decimals)
    if decimals == nil then decimals = 0 end
    local mult = 10 ^ decimals
    return math.floor(n * mult + 0.5) / mult
end

local function dictionary_get_values(dict)
    local result = {}
    local enumerator = dict:GetEnumerator()
    while enumerator:MoveNext() do
        local current = enumerator:get_Current()
        result[#result+1] = current.value
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

--- Find the index of a table element, or 0 if not found
--- @generic T
--- @param table T[]
--- @return T[]
local function table_reverse(table)
    local out = {}
    for i = #table, 1, -1 do
        out[#out+1] = table[i]
    end
    return out
end

---Get an associative table keys, sorted
local function get_sorted_table_keys(tbl)
    local list = {}
    local n = 1
    for k, v in pairs(tbl) do
        list[n] = k
        n = n + 1
    end
    table.sort(list)
    return list
end

---Get an associative table values, sorted
local function get_sorted_table_values(tbl)
    local list = {}
    local n = 1
    for _, k in pairs(tbl) do
        list[n] = k
        n = n + 1
    end
    table.sort(list)
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

---Shallow copy data from the source table into the target table.
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

--- Remove all elements of a table while maintaining the same instance reference
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

---@param defaults table
---@param target table
---@return table
local function merge_table_defaults(defaults, target)
    target = target or {}
    for key, sourceVal in pairs(defaults) do
        if target[key] == nil then
            if type(sourceVal) == 'table' then
                target[key] = clone_table(sourceVal)
            else
                target[key] = sourceVal
            end
        elseif type(sourceVal) == 'table' and type(target[key]) == 'table' then
            merge_table_defaults(sourceVal, target[key])
        end
    end
    return target
end

---@param source table
---@param target table
---@return table
local function merge_into_table(source, target)
    target = target or {}
    for key, targetVal in pairs(target) do
        local newval = source[key]
        if newval ~= nil then
            if type(newval) == 'table' then
                if type(targetVal) == 'table' then
                    target[key] = merge_into_table(newval, targetVal)
                else
                    target[key] = clone_table(newval)
                end
            else
                target[key] = newval
            end
        end
    end
    for key, sourceVal in pairs(source) do
        if sourceVal ~= nil and target[key] == nil then
            if type(sourceVal) == 'table' then
                target[key] = clone_table(sourceVal)
            else
                target[key] = sourceVal
            end
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

--- Iterates through a System.Collections.Generic.List like ipairs()
--- @param list REManagedObject System.Collections.Generic.List<{typename}>
--- @return fun(): item: REManagedObject, index: integer
local function list_iterator(list)
---@diagnostic disable
    local count = list and list.get_Count and list:get_Count()
    if count == nil or count == 0 then return function () end end

    local index = -1
    return function ()
        index = index + 1
        if index >= count then return end
        return list[index], index
    end
---@diagnostic enable
end

--- Enumerates through any REManagedObject that has a GetEnumerator() method
--- @param list REManagedObject System.Collections.Generic.List<{typename}>
--- @param enumerator_method string|nil Defaults to `GetEnumerator()`
--- @return fun(): REManagedObject|any iterator
local function enumerate(list, enumerator_method)
    local it = list:call(enumerator_method or 'GetEnumerator()')
    return function ()
        if it:MoveNext() then
            return it._current
        else
            pcall(it.call, it, 'Dispose')
            return (nil)--[[@type any]]
        end
    end
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
    return messageGuid:ToString()--[[@as string]]
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

--- @param folder via.Folder|via.Transform
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

--- @param folder via.Folder|via.Transform
--- @return via.Transform[] children
local function folder_get_immediate_children(folder)
    local it = folder:call('get_Children') -- returns a: via.Folder.<get_Children>d__2
    local enumerator = it:call('System.Collections.IEnumerable.GetEnumerator')
    local getCurrent = enumerator:get_type_definition():get_method('System.Collections.Generic.IEnumerator<via.Transform>.get_Current')
    local list = {}
    while enumerator:MoveNext() do
        local child = getCurrent:call(enumerator)---@type via.Transform
        local childFolder = child:get_GameObject():get_Folder() or child:get_GameObject():get_FolderSelf()
        if childFolder and childFolder:get_address() == folder:get_address() then
            list[#list+1] = child
        end
    end
    it:call('System.IDisposable.Dispose')
    return list
end

--- @param folder via.Folder
--- @return via.Folder[]
local function folder_get_subfolders(folder)
    local subfolders = {}
    local child = folder:get_Child()
    while child do
        subfolders[#subfolders+1] = child
        child = child:get_Next()
    end
    return subfolders
end

local function split_timestamp_components(time)
    local time_int = math.floor(time)
    local days = math.floor(time_int / 86400)
    time_int = time_int % 86400
    local hrs = math.floor(time_int / 3600)
    time_int = time_int % 3600
    local mins = math.floor(time_int / 60)
    time_int = time_int % 60
    local sec = time_int
    return days, hrs, mins, sec
end

local function format_timestamp(timeSeconds)
    local days, hrs, mins, sec = split_timestamp_components(timeSeconds)
    if days > 0 then
        return string.format('%d:%02d:%02d:%02d', days, hrs, mins, sec)
    elseif hrs > 0 then
        return string.format('%02d:%02d:%02d', hrs, mins, sec)
    else
        return string.format('%02d:%02d', mins, sec)
    end
end

local createGameobj = sdk.find_type_definition('via.GameObject'):get_method('create(System.String)')
local createGameobjInFolder = sdk.find_type_definition('via.GameObject'):get_method('create(System.String, via.Folder)')
--- @param name string
--- @param folder via.Folder|nil
--- @return via.GameObject
local function create_gameobject(name, folder)
    if folder then
        return createGameobjInFolder:call(nil, name, folder):add_ref()
    else
        return createGameobj:call(nil, name):add_ref()
    end
end

local getComponent = sdk.find_type_definition('via.GameObject'):get_method('getComponent(System.Type)')
--- @param gameObject via.GameObject
--- @param componentType string|RETypeDefinition
--- @return via.Component|nil
local function get_gameobject_component(gameObject, componentType)
    return getComponent:call(gameObject, type(componentType) == 'string' and sdk.typeof(componentType) or componentType--[[@as RETypeDefinition]]:get_runtime_type())
end

local createComponent = sdk.find_type_definition('via.GameObject'):get_method('createComponent(System.Type)')
--- @param gameObject via.GameObject
--- @param componentType string|RETypeDefinition
--- @return via.Component|nil
local function add_gameobject_component(gameObject, componentType)
    return createComponent:call(gameObject, type(componentType) == 'string' and sdk.typeof(componentType) or componentType--[[@as RETypeDefinition]]:get_runtime_type())
end

local function create_go_with_component(nameString, componentTypeString, folder)
    local go = create_gameobject(nameString, folder)
    local component = add_gameobject_component(go, componentTypeString)
    return go, component
end

local m_gui_get_object = sdk.find_type_definition("via.gui.Control"):get_method("getObject(System.String)")
--- @param gui via.gui.Control
--- @param path string
--- @return via.gui.PlayObject|nil
local function get_gui_by_path(gui, path)
    return m_gui_get_object:call(gui, path)
end

--- @param gui via.gui.PlayObject
--- @return string
local function get_gui_absolute_path(gui)
    local path = gui:get_Name()--[[@as string]]
    local parent = gui:get_Parent()
    while parent do
        path = parent:get_Name() .. '/' .. path
        parent = parent:get_Parent()
    end
    return path
end

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

local t_enum = sdk.find_type_definition('System.Enum')
--- Return a converter for converting an enum value to a string using the game's native enum handling. Alternative to constructing whole enum lookups when only a single value is needed
--- @param enum_type string
--- @return nil|fun(value: integer): string
local function enum_to_string(enum_type)
    local t = sdk.find_type_definition(enum_type)
    if not t or not t_enum:is_a(t_enum) then return nil end
    local v = t:create_instance()--[[@as any]]
    -- assumption: all enums have the non-static value field as their first field
    -- we could just assume "value__" but I'm not sure if it is the same in all games and will be the same forever
    local valueField = t:get_fields()[1]:get_name()
    return function (value)
        v[valueField] = value
        return v:ToString()
    end
end

--- @param str string
--- @return integer
function string_hash(str)
    h = 5381;

    for c in str:gmatch"." do
        h = math.fmod(((h << 5) + h) + string.byte(c), 2147483648)
    end
    return h
end

local create_performance_timer = function ()
    return {
        _timestamps = {
            { label = 'start', time = os.clock() }
        },
        _extras = nil,
        --- @param label string
        add = function(self, label)
            self._timestamps[#self._timestamps+1] = { label = label, time = os.clock() }
        end,
        get_total = function(self) return self._timestamps[#self._timestamps].time - self._timestamps[1].time end,
        group = function(self, from, to, label)
            self._extras = self._extras or {}
            local from_item = table_find(self._timestamps, function (item) return item.label == from end)
            local to_item = table_find(self._timestamps, function (item) return item.label == to end)
            if from_item and to_item then
                self._extras[#self._extras+1] = (label or (from .. '-' .. to)) .. ': ' .. (to_item.time - from_item.time)
            end
        end,
        --- @param threshold number|nil
        to_string = function(self, threshold)
            local output = 'Total time: ' .. (self._timestamps[#self._timestamps].time - self._timestamps[1].time) .. ' ['

            for i, cur in ipairs(self._timestamps) do
                local next = self._timestamps[i + 1]
                if next then
                    local diff = (next.time - cur.time)
                    if not threshold or diff >= threshold then
                        if i ~= 1 then output = output .. ', ' end
                        output = output .. next.label .. ': ' .. diff
                    end
                end
            end
            output = output .. ']'
            if self._extras then
                output = output .. ' / ' .. table.concat(self._extras, ', ')
            end
            return output
        end,
        print = function(self, label, threshold)
            local str = (label and label .. ': ' or '') .. self:to_string(threshold)
            log.info(str)
            print(str)
        end,
        print_total = function(self, label)
            local str = (label and label .. ': ' or '') .. self:get_total() .. ' s'
            log.info(str)
            print(str)
        end
    }
end

usercontent.utils = {
    log = log_all,
    get_irl_timestamp = get_irl_timestamp,

    float_round = float_round,
    chance = chance,
    create_performance_timer = create_performance_timer,

    string_join = string_join,
    string_hash = string_hash,

    file_delete = file_delete,
    file_exists = file_exists,

    generate_enum = generate_enum_label_to_value,

    list_iterator = list_iterator,
    enumerate = enumerate,
    generic_list_to_itable = generic_list_to_itable,
    generic_list_to_managed_array = generic_list_to_managed_array,
    get_sorted_table_keys = get_sorted_table_keys,
    get_sorted_table_values = get_sorted_table_values,
    get_sorted_list_table = get_sorted_list_table,
    flip_table_keys_values = flip_table_keys_values,
    table_reverse = table_reverse,
    dictionary_get_values = dictionary_get_values,
    dictionary_to_table = dictionary_to_table,
    merge_into_table = merge_into_table,
    merge_table_defaults = merge_table_defaults,
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
    system_array_of_type = system_array_of_type,
    enumerator_to_table = enumerator_to_table,

    format_timestamp = format_timestamp,

    enum_to_string = enum_to_string,
    translate_guid = translate_message_guid,
    translate = translate_message,
    guid_try_parse = try_parse_guid,
    guid_parse = parse_guid,
    gameobject = {
        create = create_gameobject,
        get_component = get_gameobject_component,
        add_component = add_gameobject_component,
        create_with_component = create_go_with_component,
    },
    folder = {
        get_subfolders = folder_get_subfolders,
        get_children = folder_get_children,
        immediate_children = folder_get_immediate_children,
    },
    gui = {
        find = get_gui_by_path,
        get_path = get_gui_absolute_path,
    },
}

_G.ce_utils = usercontent.utils
return usercontent.utils
