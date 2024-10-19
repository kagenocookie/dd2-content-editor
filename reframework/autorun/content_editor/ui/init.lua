if type(_userdata_DB) == 'nil' then _userdata_DB = {} end
if _userdata_DB.ui then return _userdata_DB.ui end

local ui_core = require('content_editor.ui.imgui_wrappers')
local ext = require('content_editor.ui.ext')
local handlers = require('content_editor.ui.handlers')
local context = require('content_editor.ui.context')

_userdata_DB.ui = {
    core = ui_core,
    editor = ext,
    handlers = handlers,
    context = context,
}
return _userdata_DB.ui
