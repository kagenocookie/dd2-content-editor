if type(usercontent) == 'nil' then usercontent = {} end
if usercontent.__internal and usercontent.__internal.config then return usercontent.__internal end

require('content_editor.core')
return usercontent.__internal
