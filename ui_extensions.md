## UI Extensions
The content editor allows modders to define custom UI extensions to be displayed alongside / instead of specific objects or fields.

An new extension can be defined with:
```lua
local ui = require('content_editor.ui')

ui.handlers.register_extension('my_label_extension', function (handler, data)
    local text_param = data.text or 'Hello world!'
    --- @type UIHandler
    return function (ctx)
        local changed = handler(ctx)
        imgui.text(text_param)
        return changed
    end
end)
```
This extension can then be referenced using type overrides with arbitrary custom data provided:
```lua
definitions.override('items', {
    ['app.ClassnameToOverride'] = {
        extensions = {
            { type = 'my_label_extension', text = 'Better hello world!' }
        }
    }
})
```


### List of core extensions
* `tooltip`
    * Shows a tooltip on the right of the extended field.
    * Parameters:
        * text (`string`): The text to display in the tooltop
* `conditional`
    * Shows the field only when a condition is true
    * Parameters:
        * condition (`fun(ctx: UIContainer): boolean`): The text to display in the tooltop
* `parent_field_conditional`
    * Shows the field only when a field on the parent containing object is equal to the given value
    * Parameters:
        * field (`string`): The field on the parent to check
        * showValue (`any`): The value it should be equal to to show
* `object_explorer`
    * Shows an object explorer section below the field (`object_explorer:handle_address(object)`)
* `space_before`
    * Add some spacing before the field (using `imgui.spacing()`)
    * Parameters:
        * count (`integer`, optional): The number of times to call `imgui.spacing()`
* `space_after`
    * Add some spacing after the field (using `imgui.spacing()`)
    * Parameters:
        * count (`integer`, optional): The number of times to call `imgui.spacing()`
* `toggleable`
    * Make the field contents toggleable based on a boolean field within it
    * Parameters:
        * field (`string`): The boolean field to check
        * inverted (`boolean`, default false): Whether the condition should be inverted (true => show if false, false => show if true)
* `sibling_field_toggleable`
    * Make the field toggleable based on another field of the object it's contained in
    * Parameters:
        * field (`string`): The boolean field to check
        * inverted (`boolean`, default false): Whether the condition should be inverted (true => show if false, false => show if true)
* `flag_toggleable`
    * Make the field toggleable based on a flag field
    * Parameters:
        * flagKey (`string`): The field containing the flag
        * flagValue (`integer`): The flag that should be set for this field to show up
* `indent`
    * Add some indent to the right of the field (`imgui.indent(n)`)
    * Parameters:
        * indent (`integer`, default 12): How many pixels to indent
* `rect`
    * Wrap the field in a rectangle (`imgui.begin_rect()`)
    * Parameters:
        * size (`integer`, default 0): How many pixels of padding to add (parameter to `imgui.end_rect(size)`)
* `randomizable`
    * Add a button to randomize the field
    * Parameters:
        * randomizer (`fun(): any`): A function that will return a random value
* `filter`
    * Hide the field if a custom condition is met
    * Parameters:
        * filter (`fun(val: UIContainer): boolean`): A function that will return true if the value should be displayed
* `userdata_picker`
    * Show a userdata file input text field below the field
    * Parameters:
        * allow_new (`boolean`, default true): Whether creating a new instance should be allowed
        * classname (`string`, optional): The class to instantiate as, if unset will try to infer from the existing instance or use via.UserData
* `userdata_dropdown`
    * Show a userdata file dropdown picker below the field
    * Parameters:
        * options (`any`): The list of file options to show
* `linked_entity`
    * Show a separate linked entity editor below the field
    * Parameters:
        * entity_type (`string`): The content database entity type
        * draw_callback (`fun(entity: DBEntity, context: UIContainer)`): The callback for drawing the entity
        * entity_getter (`fun(context: UIContainer): entity: nil|DBEntity`, optional): The function to fetch the linked entity
        * labeler (`fun(entity: DBEntity, context: UIContainer): string`, optional): The function for generating the label displayed for the linked entity
* `getter_property`
    * Show readonly properties for a class
    * Parameters:
        * props (`string[]`): The list of property names to show (should be only the actual name, e.g. `get_DisplayCategoryId()` should be specified as `DisplayCategoryId`)
* `translate_guid`
    * Show a translation of the guid in the field
    * Parameters:
        * prefix (`string`, optional): A prefix to show before the actual translation
* `handler_pre`
    * Trigger custom logic before the field is displayed
    * Parameters:
        * handler (`fun(ctx: UIContainer): nil`): Callback to call
* `handler_post`
    * Trigger custom logic after the field is displayed
    * Parameters:
        * handler (`fun(ctx: UIContainer, changed: boolean): nil`): Callback to call

### Complex extensions
These may need some more effort to make work, possibly also have per-game specifics.

* `custom_script_hookable`
    * Show a custom script editor for fields
    * Needs to be used together with `custom_scripts.define_script_hook()` and `custom_scripts.define_script_hook_editor_override()`
    * Parameters:
        * id_fetcher (`fun(args: any): integer|nil`): Method that will fetch the script ID from an object - should return nil if there is no script
        * change_to_hook (`fun(value: any, hook: boolean)`): Callback to invoke when the object's "Has a custom script hook" option is switched on or off
        * set_id (`fun(value: any, id: integer)`): Callback that will store the ID on an object
        * helpstring (`string|nil`): Additional help text to show in the UI for the user
