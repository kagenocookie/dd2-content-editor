if type(usercontent) == 'nil' then usercontent = {} end
if usercontent.ui then return usercontent.ui end

local core = require('content_editor.core')
if not core.editor_enabled then
    print('Content editor UI requested despite being disabled')
end

local basic = require('content_editor.ui.imgui_wrappers')
local translation = require('content_editor.ui.translation')
local editor_ext = require('content_editor.ui.ext')
local handlers = require('content_editor.ui.handlers')
local context = require('content_editor.ui.context')

usercontent.ui = {
    basic = basic,
    editor = editor_ext,
    handlers = handlers,
    context = context,
    translation = translation,
}
return usercontent.ui
