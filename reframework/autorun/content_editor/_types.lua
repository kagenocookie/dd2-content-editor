-- DB types
--- @class DBEntity
--- @field id integer
--- @field type string
--- @field label string|nil

--- Internal entity tracking data
--- @class EntityData
--- @field entity DBEntity
--- @field dirty boolean
--- @field bundle string|nil
--- @field type EntityType

-- data storage types
--- @class UserdataEditorSettings
--- @field fields nil|table<string, ObjectFieldDefinition>
--- @field fieldOrder nil|string[]
--- @field toString nil|fun(value: any, context: UIContainer|nil): string
--- @field abstract nil|string[]
--- @field abstract_default nil|string
--- @field force_expander boolean|nil
--- @field array_expander_disable boolean|nil
--- @field import_handler ValueImporter|nil
--- @field import_field_whitelist string[]|nil
--- @field extensions FieldExtension[]|nil
--- @field uiHandler UIHandler|nil

--- @class ObjectFieldDefinition
--- @field label string|nil
--- @field uiHandler UIHandler|nil
--- @field import_handler ValueImporter|nil
--- @field import_ignore boolean|nil
--- @field not_nullable boolean|nil
--- @field ui_ignore boolean|nil
--- @field accessors ObjectFieldAccessors|nil
--- @field force_expander boolean|nil
--- @field extensions FieldExtension[]|nil
--- @field classname string|nil Override the type used for a field, not sure if we have actual use for it now

--- @class FieldExtension : table
--- @field type string

--- @class ObjectFieldAccessors
--- @field get fun(object: REManagedObject, fieldname: string|integer): any
--- @field set fun(object: REManagedObject, value: any, fieldname: string|integer)

--- @alias ArrayLikeObject SystemArray|REManagedObject|table
--- @class ArrayLikeAccessors
--- @field length fun(arr: ArrayLikeObject): integer
--- @field get_elements fun(arr: ArrayLikeObject): table<integer, any> Get all array items in game indices (usually starting at 0)
--- @field get_elements_indexed fun(arr: ArrayLikeObject): any[] Get all array items in a lua numeric-indexed table (starting at 1)
--- @field remove_at fun(arr: ArrayLikeObject, index: integer): ArrayLikeObject Returns the new (or same) array-like object instance
--- @field add nil|fun(arr: ArrayLikeObject, object: any, arrayClassname: string): ArrayLikeObject Returns the new (or same) array-like object instance
--- @field create nil|fun(classname: string): ArrayLikeObject Returns a new array-like object instance of the correct type

--- @class UISettings
--- @field tooltip string|nil
--- @field show_nested boolean|nil

--- @class ValueImporter
--- @field import fun(src: table, currentValue: nil|(REManagedObject|any)): any
--- @field export fun(src: any, target: table|nil, options: any): any


--- Data for creating a new enum
--- @class EnumDefinitionFile
--- @field isVirtual boolean|nil Denotes that this enum is not based on an ingame enum class but used only for editor display purposes
--- @field enumName string
--- @field orderByValue boolean|nil
--- @field values nil|table<string, integer>
--- @field displayLabels nil|table<string, string>

--- @class BundleInfo
--- @field name string
--- @field author string
--- @field created_at string
--- @field updated_at string

--- @class BundleRuntimeData
--- @field info BundleInfo
--- @field dirty boolean
--- @field entities DBEntity[]
--- @field modifications table<DBEntity, ImportActionType>
--- @field initial_insert_ids table<string, integer>
--- @field next_insert_ids table<string, integer>

--- import data structures
--- @class DataBundle
--- @field name string
--- @field author string
--- @field created_at string
--- @field updated_at string
--- @field game_version string
--- @field data EntityImportData[]
--- @field initial_insert_ids table<string, integer>

--- Data for importing an enum
--- @class EnumEnhancement
--- @field enumName string
--- @field labelToValue table<string, integer>

--- @class EntityImportData
--- @field id integer Object's unique ID
--- @field type string Object's entity type
--- @field label string Display label
--- @field data table
