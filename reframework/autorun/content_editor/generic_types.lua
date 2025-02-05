if type(usercontent) == 'nil' then usercontent = {} end
if usercontent.generics then return usercontent.generics end

--- Generic arrays and type definitions have stupid full-namespaced type names like
--- System.Collections.Generic.Dictionary`2.Entry[[via.effect.ProviderData, System, Version=1.0.0.0, Culture=neutral, PublicKeyToken=null],[ ...][]
--- do some regex magic to turn them into the more normal <> syntax
--- @param typename string
--- @return string
local function clean_generic_type_definition_name(typename)
    typename = typename:gsub('%[%[', '<['):gsub('%]%]', ']>') -- turn all [[ and ]] into <[ and ]>
    typename = typename:gsub(', [%a%d_\\.]+, [%a%d, =.]+%]', ']') -- remove all namespace+version+culture+token segments
    typename = typename:gsub('%[([%a%d+_,`<>\\.]+)%]', '%1') -- remove single [...] brackets around types
    typename = typename:gsub('%[([%a%d+_,`<>\\.]+)%]', '%1') -- repeat above to also handle nested generics
    typename = typename:gsub('%[([%a%d+_,`<>\\.]+)%]', '%1') -- repeat above to also handle nested generics
    typename = typename:gsub('%[([%a%d+_,`<>\\.]+)%[%]%]', '%1[]') -- a few types also have an array value for the last generic, handle that too
    return typename
end

--- @param typename string
--- @return string
local function clean_generic_type_name(typename)
    -- this does some aditional replacements that may be required for custom runtime types compared to clean_generic_type_definition_name
    typename = clean_generic_type_definition_name(typename)
    typename = typename:gsub('%+', '.') -- a few types also have an array value for the last generic, handle that too
    typename = typename:gsub(', [%a%d_\\.]+, [%a%d, =.]+$', '') -- remove all namespace+version+culture+token segments
    return typename
end

--- @type table<string, System.Type>
local generic_runtime_types = {}
--- @type table<string, System.Type>
local generic_runtime_types_by_base_path = {}

local basepathRegex = '^[a-zA-Z0-9+_.]*`%d<'

local has_setup_generics = false

local function setup_generic_type_assemblies()
    local timer = os.clock()
    has_setup_generics = true
    local asms = sdk.find_type_definition('System.AppDomain'):get_method('get_CurrentDomain'):call(nil):GetAssemblies()
    for _, asm in pairs(asms) do
        for _, t in pairs(asm:GetTypes()) do
            if t:get_IsGenericType() then
                local fullname = t:get_FullName()
                local cleanName = clean_generic_type_definition_name(fullname)
                generic_runtime_types[cleanName] = t
                local basePath = cleanName:match(basepathRegex)
                if basePath then
                    generic_runtime_types_by_base_path[basePath] = t
                else
                    -- NOTE: there are many cases that fail the regex
                    -- but they're mostly nested types within generics (e.g. List<T>.Enumerator) or lambdas, which we can't or have little reason to instantiate anyway
                    -- print('invalid basepath pattern', cleanName)
                end
            end
        end
    end
    local setup_end = os.clock()
    print('Generic type lookup setup in ' .. (setup_end - timer))
end

--- Find the runtime type for a generic classname (because REF doesn't natively know how to do that)<br>
--- Currently supported: classes NOT nested inside generic types, with any number of NON-generic parameters<br>
--- e.g. List<>, Dictionary<,>, ClassSelector<>
--- @param classname string
--- @return System.Type|nil
local function get_generic_typedef(classname)
    local t = generic_runtime_types[classname]
    if t then return t end

    if not has_setup_generics then
        usercontent.core.log_debug('Generating generic type data because of type', classname)
        setup_generic_type_assemblies()
    end

    local needCleaning = false
    local nestingCount = select(2, classname:gsub('<', ''))
    if nestingCount == 0 then
        nestingCount = select(2, classname:gsub('%[%[', ''))
        needCleaning = true
    end
    if nestingCount == 0 then
        print('Not a generic type you dummy, why are you calling this method?', classname)
        return sdk.typeof(classname)
    end

    if nestingCount > 1 then
        print('ERROR: multi level generic types not yet supported automatically', classname)
        print("p.s. it's possible to manually define a runtime type via lua, which can resolve this issue")
        return nil
    end

    if nestingCount == 1 then
        -- start off by figuring out what inner types we need
        local effectiveClassname = classname
        if needCleaning then
            effectiveClassname = clean_generic_type_definition_name(classname)
        end
        local innerTypes = {}
        local innerClassnames = effectiveClassname:gsub('^[a-zA-Z0-9_.]+`%d+<', '')
        for inner in innerClassnames:gmatch('([a-zA-Z0-9_.%[%]]+)[,>]') do
            innerTypes[#innerTypes+1] = inner
        end

        -- next, find the generic definition string
        local base = effectiveClassname:match(basepathRegex)
        if base and generic_runtime_types_by_base_path[base] then
            local baseType = generic_runtime_types_by_base_path[base]
            types = sdk.create_managed_array('System.Type', #innerTypes)
            for i = 1, #innerTypes do
                types[i - 1] = sdk.typeof(innerTypes[i])
                -- print('generic argument type ', classname, types[i - 1], types[i - 1]:get_FullName())
            end
            -- now we can construct the concrete type out of the definition
            t = baseType:MakeGenericType(types)
        end
        if not t then
            -- local genDefPattern = classname:gsub('([<,])([a-zA-Z0-9-.])', '$1[a-zA-Z0-9_]+')
            print('ez generic type resolution attempt failed, try bruteforce maybe?', classname, effectiveClassname, base)
        end
        generic_runtime_types[effectiveClassname] = t
        generic_runtime_types[classname] = t
    end

    return t
end

--- Manually define a classname mapping into a runtime type, in case the automatic magic doesn't resolve a type properly
--- @param runtimeType System.Type
--- @param classname string|nil
--- @return string classname
local function add_generic_typedef(runtimeType, classname)
    if classname == nil then
        classname = clean_generic_type_name(runtimeType:get_FullName()--[[@as string]])
    end
    generic_runtime_types[classname] = runtimeType
    return classname
end

usercontent.generics = {
    get_clean_generic_classname = clean_generic_type_name,
    typedef = get_generic_typedef,
    add = add_generic_typedef,
}
return usercontent.generics
