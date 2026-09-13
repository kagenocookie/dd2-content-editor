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

local warned_missing_method_lib = false
--- @param pfb via.Prefab
--- @param path string
local function set_prefab_path(pfb, path)
    if pfb.set_Path then
        -- set it directly for games that have it still available
        pfb:set_Path(path)
        return
    end

    if type(MethodLibrary) == 'nil' then
        if not warned_missing_method_lib then
            warned_missing_method_lib = true
            re.msg('You are missing the required MethodLibrary plugin.\nYou have to install it for all functionality to work.')
        end
        return
    end
    MethodLibrary.prefab_set_path(pfb,  sdk.create_managed_string(path))
end

usercontent.prefabs = {
    get_shared_instance = get_shared_instance,
    store_shared_instance = store_shared_instance,
    set_path = set_prefab_path,
}
return usercontent.prefabs