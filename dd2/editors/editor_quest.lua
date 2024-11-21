require('editors.quests.database')
require('editors.quests.talk_events')

local core = require('content_editor.core')
if core.editor_enabled then
    require('editors.quests.quest_editor')
    require('editors.quests.quest_utils')
    require('editors.quests.quest_processors')
end
