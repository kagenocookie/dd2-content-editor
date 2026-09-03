# v1.5.0
- Updated code for the latest game version
- Removed option for .pfb based item icons (no idea if anyone even used it instead of straight .tex files)
- Removed unused prefab helper code

## Known issues
Custom item names are displayed as "Invalid" in the item pickup GUI due to a change in how the item lookups work for that. While it's probably possible to work around, I'd rather solve that by integrating the desktop file editing features of REE Content Editor for this so I'll leave it as-is for now. Note that the item icons are correct and they're still fine in the inventory, it's just the pickup name display that's wrong.
