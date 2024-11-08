require('event_editor.events_main')
require('event_editor.domain_generate_tables')

local core = require('content_editor.core')
if core.editor_enabled then
    require('event_editor.events_editor')
end
