local sysSvc = sdk.get_native_singleton('via.SystemService')
local ver = sdk.call_native_func(sysSvc, sdk.find_type_definition('via.SystemService'), 'get_ApplicationVersion')

return {
    game_data_is_ready = function () return true end,
    version = ver,
}
