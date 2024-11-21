require('editors.events.events_main')
require('editors.events.domain_generate_tables')

local core = require('content_editor.core')
if core.editor_enabled then
    require('editors.events.events_editor')
end
