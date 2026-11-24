# macOS 27: why some menu bar items stay hidden (known limits and workaround)

Several of you have asked why some menu bar items stay hidden on macOS 27, even when they sit right of the arrow. This page says what we know, what we tested, and what you can do. Last checked on Hidden Bar 1.13.4 and macOS 27.2.1.

## What macOS 27 does

- **macOS hides some of its own items whenever any app hides menu bar icons.** That covers Focus, Now Playing, Camera controls, Live Activities, User, Siri and Stage Manager. Hidden Bar asks macOS to keep them visible, and macOS ignores the request. We confirmed this on macOS 27.0.1 and 27.2.1. A user reports that macOS accepts only nine system item ids in that request, and that a tenth did not keep Focus visible (not re-measured by us).
- **macOS 27 also ignores that request for third-party apps that run from outside the system Applications folder.** Only `/Applications` and folders inside it count. `~/Applications`, Downloads and `~/Library/Application Support` do not. A copy that runs from one of those places is hidden whenever Hidden Bar collapses, whatever you pick in Settings > Icons.
  - iStat Menus 7 is the common case. The app is in `/Applications`, but its menu bar part, "iStat Menus Menubar", runs from `~/Library/Application Support/iStat Menus 7/`, so macOS hides it. On 1.13.4 with the app set to Visible, Hidden Bar logs `macOS hides ["iStat Menus Menubar"] although they are allowed: they run from outside an Applications folder`.
  - Users report the same for a tool run from `~/Applications` and say moving Itsycal from `~/Applications` to `/Applications` fixed its hiding. For an app you control, move it to `/Applications` and relaunch it. For an app that starts its menu bar part from somewhere else (iStat Menus), only the workaround below helps.
- **Clicking the clock while the bar is collapsed expands the bar for a moment.** macOS ignores clicks on the clock while icons are hidden, so Notification Center would not open. Hidden Bar lifts its hiding for that click, opens Notification Center, and collapses again about a second after the panel closes (checked on 1.13.4, closing by a click elsewhere and by clicking the clock again). A bar you expanded yourself is left as it is. This is not a click Hidden Bar catches by mistake, and macOS offers no way to open Notification Center from the clock without the icons showing for that moment.

## See which apps are affected

After a collapse that macOS hid an allowed app, Settings > Advanced lists the app under the pause switch ("Seen on this Mac: ..."). When the pause switch is on and such an app sits right of the arrow, a click on the arrow that hides nothing shows a short note under the arrow that names it. Both arrived in 1.13.1 and 1.13.3.

## Workaround: pause hiding

Settings > Advanced > **Pause hiding while macOS shows Now Playing, Focus and similar items** (named "Show all icons while macOS hides one right of the arrow" in 1.13.0). It is off by default.

While one of those items shows, Hidden Bar hides nothing, so the item stays visible. The price is that your other icons stay visible too, for as long as the item is on screen. With iStat Menus that means for as long as iStat runs: checked on 1.13.4, the bar stays whole on every collapse, with the log line `hiding unavailable: an icon right of the arrow cannot be kept visible, so the bar stays whole`. If you want iStat hidden like the rest, leave the switch off and put iStat left of the arrow.

## Limit of the workaround

If an item appears while the bar is already collapsed (a scheduled Focus turning on, music starting), it stays hidden until the next expand. macOS does not report the item to apps while hiding is on, so Hidden Bar cannot see it. Expanding the bar once fixes it.

## Related issues

[#526](https://github.com/consolelabs/hidden/issues/526), [#501](https://github.com/consolelabs/hidden/issues/501), [#521](https://github.com/consolelabs/hidden/issues/521), [#514](https://github.com/consolelabs/hidden/issues/514), [#469](https://github.com/consolelabs/hidden/issues/469), [#583](https://github.com/consolelabs/hidden/issues/583) (clock), [#592](https://github.com/consolelabs/hidden/issues/592) (iStat Menus)

If the pause switch is on and an item still disappears, please comment on the matching issue with your macOS build, your Hidden Bar version and a log ("Capture a log" in the [manual](https://github.com/consolelabs/hidden/blob/develop/docs/MANUAL.md#capture-a-log)). That would be a different bug.
