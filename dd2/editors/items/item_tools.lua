if type(usercontent) == 'nil' then usercontent = {} end
if usercontent.item_tools then return usercontent.item_tools end

local udb = require('content_editor.database')
local editor = require('content_editor.editor')

local equip_cat_to_style = { [2] = 'HelmStyle', [3] = 'TopsStyle', [4] = 'PantsStyle', [5] = 'MantleStyle', [7] = 'FacewearStyle' }
local equip_cat_to_name = { [0] = 'MainWeapon', [1] = 'SubWeapon', [2] = 'Helm', [3] = 'Tops', [4] = 'Pants', [5] = 'Mantle', [7] = 'Facewear' }

--- @param item ItemDataEntity
--- @return string|nil
local function get_item_style_type(item)
    return equip_cat_to_style[item.runtime_instance._EquipCategory]
end

local ItemManager = sdk.get_managed_singleton('app.ItemManager')
local getItem = sdk.find_type_definition('app.ItemManager'):get_method('getItem(System.Int32, System.Int32, app.CharacterID, System.Boolean, System.Boolean, System.Boolean, app.ItemManager.GetItemEventType)')
--- @param characterId app.CharacterID|nil
--- @param itemId integer
--- @param count integer
local function give_item(characterId, itemId, count)
    getItem:call(ItemManager, itemId, count, characterId, true, false, false, 1)
end

--- @param item ItemDataEntity
--- @return StyleEntity|nil
local function find_item_style_entity(item)
    local styleType = equip_cat_to_style[item.runtime_instance._EquipCategory]
    local style = udb.get_entity(styleType, item.runtime_instance._StyleNo)
    if style and udb.get_entity_bundle(style) == nil then
        style.label = udb.generate_entity_label(style)
        usercontent.database.get_entity_enum(styleType).set_display_label(style.id, style.label)
    end
end

usercontent.item_tools = {
    give_item = give_item,
    find_item_style_entity = find_item_style_entity,
    get_item_style_type = get_item_style_type,
}
return usercontent.item_tools