--- @class ContentEditorGameController
--- @field version string
--- @field get_root_scene fun(): via.Scene|nil
--- @field game_data_is_ready fun(): boolean
--- @field is_ingame_unpaused fun(): boolean Check whether the game is unpaused and ingame
--- @field on_game_load_or_reload fun(callback: fun(is_ingame: boolean))
--- @field on_game_unload fun(callback: fun(is_ingame: boolean))
--- @field on_game_after_load fun(callback: fun(is_ingame: boolean))

local game_name = reframework:get_game_name()
local hasSetup, gameSetup = pcall(require, 'editors.core.setup')
--- @type ContentEditorGameController
local ctrl = hasSetup and gameSetup or {}

if ctrl.game_data_is_ready == nil then ctrl.game_data_is_ready = function () return true end end

--- Callback will be invoked whenever the game loads up save data (load, reload), but may still be showing a loading screen
--- @type fun(callback: fun(ingame: true))
ctrl.on_game_load_or_reload = ctrl.on_game_load_or_reload or nil

--- Callback will be invoked whenever the game loading screen is requested to end (after load, reload), and the basic game setup is finished; should only trigger on full data loads and not scene/cutscene transitions
--- @type fun(callback: fun(ingame: true))
ctrl.on_game_after_load = ctrl.on_game_after_load or nil

--- Callback will be invoked whenever the game is unloaded (after death, exiting to main menu, ...)
--- @type fun(callback: fun(ingame: false))
ctrl.on_game_unload = ctrl.on_game_unload or nil

ctrl.is_ingame_unpaused = ctrl.is_ingame_unpaused or function() return true end

if ctrl.version == nil then
    local t_sys = sdk.find_type_definition('via.SystemService')
    local s_sys = sdk.get_native_singleton('via.SystemService')
    if t_sys and s_sys then
        -- example: Product:3.0.1.0,File:3.0.1.0
        local hasAppVer, ver = pcall(sdk.call_native_func, s_sys, t_sys, 'get_ApplicationVersion')
        if hasAppVer then
            local versions = {}
            local versionNums = {}
            for part in tostring(ver):gmatch('[%w%d:.]+') do
                local sep = part:find(':')
                local subver
                if sep then
                    subver = part:sub(sep + 1)
                    versions[part:sub(1, sep - 1)] = subver
                else
                    subver = part
                    versions[#versions + 1] = part
                end
                local isnew = true
                for _, vn in ipairs(versionNums) do
                    if vn == subver then isnew = false break end
                end
                if isnew then
                    versionNums[#versionNums + 1] = subver
                end
            end
            print('Detected game version', json.dump_string(versions))
            ctrl.version = table.concat(versionNums, '/')
        end
    end

    if ctrl.version == nil then
        print('Content editor could not determine game version')
        log.info('Content editor could not determine game version')
        ctrl.version = '-1'
    end
end

if ctrl.get_root_scene == nil then
    local rootScene
    ctrl.get_root_scene = function()
        if rootScene then return rootScene end
        success, scene = pcall(sdk.call_native_func, sdk.get_native_singleton("via.SceneManager"), sdk.find_type_definition("via.SceneManager"), "get_CurrentScene()")
        if success then
            rootScene = scene
            return scene
        else
            rootScene = nil
        end
    end
end

--- @type ContentEditorGameController
return ctrl
