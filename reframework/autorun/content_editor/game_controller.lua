if type(_userdata_DB) == 'nil' then _userdata_DB = {} end
if _userdata_DB._game_controller then return _userdata_DB._game_controller end

local success, ctrl = pcall(require, 'content_editor.' .. reframework:get_game_name() .. '.control')

if not success then
    ctrl = { }
end

if ctrl.game_data_is_ready == nil then ctrl.game_data_is_ready = function () return true end end
if ctrl.version == nil then ctrl.version = '-1' end

_userdata_DB._game_controller = ctrl
return _userdata_DB._game_controller
