local consts = {
    custom_weapon_min_id = 1000,
    custom_weapon_max_id = 100000,

    custom_item_min_id = 30000,
    custom_item_max_id = 65000,
}

function consts.is_custom_weapon (id) return id >= consts.custom_weapon_min_id and id < consts.custom_weapon_max_id end
function consts.is_custom_item (id) return id >= consts.custom_item_min_id and id < consts.custom_item_max_id end

return consts