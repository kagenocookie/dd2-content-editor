print('Initializing content database...')
require('content_editor.database')
require('content_editor.editors.messages')
local core = require('content_editor.core')

if core.editor_enabled then
    print('Initializing content editor...')
    require('content_editor.editor')
    require('content_editor.editors.console')
end
