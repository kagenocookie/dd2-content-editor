function PrepareFiles {
    param (
        [string] $Folder,
        [string[]] $FileList
    )
    Write-Output "Preparing submod $Folder ..."

    foreach ($file in $FileList)
    {
        $outpath = "_build/$Folder/$file"
        $targetfolder = Split-Path $outpath -Parent
        if (!(Test-Path $targetfolder -PathType Container)) {
            New-Item -Path $targetfolder -ItemType Directory -Force
        }
        Copy-Item -Path $file -Recurse -Destination $outpath -Force -Container:$false
    }
}

function MakeModinfo {
    param (
        [string] $Folder,
        [string] $Name,
        [string] $Version,
        [string] $Description
    )
    $outpath = "_build/$Folder/modinfo.ini"
    $targetfolder = Split-Path $outpath -Parent
    if (!(Test-Path $targetfolder -PathType Container)) {
        New-Item -Path $targetfolder -ItemType Directory -Force
    }
    $content = $(Get-Content .\addon_template.ini)
    $content = $content.Replace("_VERSION_", "$Version").Replace("_NAME_", "$Name").Replace("_DESCRIPTION_", "$Description")
    Out-File -FilePath $outpath -InputObject $content
    ((Get-Content $outpath) -join "`n") + "`n" | Set-Content -NoNewline $outpath
}

$Version = "v1.0.0"

PrepareFiles -Folder "dd2_content_editor" -FileList (
    "reframework/autorun/content_editor",
    "reframework/autorun/content_editor.lua",
    "readme.md",
    "campfire.jpg",
    "reframework/autorun/content_editor/definitions/dd2.lua",
    "reframework/data/usercontent"
)
Copy-Item -Path modinfo_dd2.ini -Destination "_build/dd2_content_editor/modinfo.ini"

MakeModinfo "quest_editor" "Quest editor" "v0.1.0" "DD2 quest editor addon for Content editor"
PrepareFiles -Folder "quest_editor" -FileList (
    "reframework/autorun/quest_editor",
    "reframework/autorun/editor_quest.lua",
    "natives/stm/appdata/quest/qu8000/qu8000.scn.20",
    "natives/stm/appdata/quest/qu8000/resident.scn.20"
    # "natives/stm/appsystem/scene/quest.scn.20"
)

MakeModinfo "event_editor" "Event editor" $Version "DD2 events editor addon for Content editor"
PrepareFiles -Folder "event_editor" -FileList ("reframework/autorun/editor_events.lua")

MakeModinfo "shop_editor" "Shop editor" $Version "DD2 shops editor addon for Content editor"
PrepareFiles -Folder "shop_editor" -FileList ("reframework/autorun/editor_shops.lua")

MakeModinfo "param_editor" "Parameter editor" $Version "DD2 human, job parameter editor addon for Content editor"
PrepareFiles -Folder "param_editor" -FileList ("reframework/autorun/editor_human_params.lua")

MakeModinfo "item_editor" "Item editor" $Version "DD2 item editor addon for Content editor"
PrepareFiles -Folder "item_editor" -FileList (
    "reframework/autorun/editor_items.lua",
    "reframework/autorun/item_editor"
)

MakeModinfo "weather_editor" "Weathers editor" $Version "DD2 human weathers editor addon for Content editor"
PrepareFiles -Folder "weather_editor" -FileList ("reframework/autorun/editor_weathers.lua")

Set-Location _build
& "C:/Program Files/7-Zip/7z.exe" a ../content_editor_full.zip *

Set-Location ..
Remove-Item .\_build -Recurse
