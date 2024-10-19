require('quest_editor.database')
require('quest_editor.talk_events_editor')

local core = require('content_editor.core')
if core.editor_enabled then
    require('quest_editor.quest_editor')
    require('quest_editor.event_editor')
    require('quest_editor.quest_utils')
    require('quest_editor.quest_processors')
end
