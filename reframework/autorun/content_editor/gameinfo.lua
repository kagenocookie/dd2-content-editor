if type(_userdata_DB) == 'nil' then _userdata_DB = {} end
if _userdata_DB._game_controller then return _userdata_DB._game_controller end

local success, ctrl = pcall(require, 'content_editor.' .. reframework:get_game_name() .. '.info')

if not success then
    ctrl = { }
end

if ctrl.game_data_is_ready == nil then ctrl.game_data_is_ready = function () return true end end

if ctrl.setup == nil then ctrl.setup = function () end end

--- Callback will be invoked whenever the game loads up save data (load, reload), but may still be showing a loading screen
--- @type fun(callback: fun(ingame: true))
ctrl.on_game_load_or_reload = ctrl.on_game_load_or_reload or nil

--- Callback will be invoked whenever the game loading screen is requested to end (after load, reload), and the basic game setup is finished; should only trigger on full data loads and not scene/cutscene transitions
--- @type fun(callback: fun(ingame: true))
ctrl.on_game_after_load = ctrl.on_game_after_load or nil

--- Callback will be invoked whenever the game is unloaded (after death, exiting to main menu, ...)
--- @type fun(callback: fun(ingame: false))
ctrl.on_game_unload = ctrl.on_game_unload or nil

--- Check whether the game is unpaused and ingame
--- @type fun(): boolean
ctrl.is_ingame_unpaused = ctrl.is_ingame_unpaused or function() return true end

if ctrl.version == nil then
    local t_ver = sdk.find_type_definition('via.version')
    if t_ver and t_ver:get_method('getMainRevisionString') then
        ctrl.version = t_ver:get_method('getMainRevisionString'):call(nil)
    else
        local t_sys = sdk.find_type_definition('via.SystemService')
        local s_sys = sdk.get_native_singleton('via.SystemService')
        if t_sys and s_sys then
            local hasAppVer, ver = pcall(sdk.call_native_func, s_sys, t_sys, 'get_ApplicationVersion')
            if hasAppVer then ctrl.version = ver end
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

_userdata_DB._game_controller = ctrl
return _userdata_DB._game_controller
