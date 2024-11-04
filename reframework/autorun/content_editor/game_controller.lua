if type(_userdata_DB) == 'nil' then _userdata_DB = {} end
if _userdata_DB._game_controller then return _userdata_DB._game_controller end

local success, ctrl = pcall(require, 'content_editor.' .. reframework:get_game_name() .. '.control')

if not success then
    ctrl = { }
end

if ctrl.game_data_is_ready == nil then ctrl.game_data_is_ready = function () return true end end

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

_userdata_DB._game_controller = ctrl
return _userdata_DB._game_controller
