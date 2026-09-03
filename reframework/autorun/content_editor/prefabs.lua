if type(usercontent) == 'nil' then usercontent = {} end
if usercontent.prefabs then return usercontent.prefabs end

--- @type table<string, via.GameObject>
local sharedInstances = {}

--- Get an already loaded shared prefab gameobject instance
--- @param path string
--- @return via.GameObject
local function get_shared_instance(path)
    return sharedInstances[path]
end

--- Add or replace a shared instance gameobject
--- @param path string
--- @param gameObject via.GameObject
local function store_shared_instance(path, gameObject)
    sharedInstances[path] = gameObject
end

local hashfunc = sdk.find_type_definition('app.StringExtension'):get_method('hash') -- murmur3 hash

--- @param pfb via.Prefab
--- @param path string
local function set_prefab_path(pfb, path)
    -- note: currently untested
    local addr = pfb:get_address()
    local managed_str = sdk.create_managed_string(path):add_ref_permanent()
    -- note: this might won't work, the real set_Path does some extra stuff in there
    pfb:write_qword(addr + 24, managed_str:get_address())
    -- it _looks_ like the path hash is at offset + 16, which would likely be the PAK lower+upper hash pattern that the pak itself uses
    -- hardcoding prefix and suffix cause I assume those are included there
    -- no idea if this actually works the way the game does, will see when we get there
    local nativePath = 'natives/stm/' .. path .. '.17'
    local hashLower = hashfunc:call(nil, nativePath:lower())
    local hashUpper = hashfunc:call(nil, nativePath:upper())
    pfb:write_dword(addr + 16, hashLower)
    pfb:write_dword(addr + 20, hashUpper)
    -- the method also does some other increments and interlocks, not sure if purely thread safety or actual important stuff like ref counting or engine calls
end

usercontent.prefabs = {
    get_shared_instance = get_shared_instance,
    store_shared_instance = store_shared_instance,
    set_path = set_prefab_path,
}
return usercontent.prefabs