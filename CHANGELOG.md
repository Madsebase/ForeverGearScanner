# Changelog

## v1.2.3

- **Random-enchant stat resolution on hover & live tooltip/card refresh:** Items whose browse `ItemKey` hides rolled stats behind `<Random enchantment>` (or statless Uncommon+ gear) now display a `Stats on hover` pill instead of blank space, resolve the cheapest listing's concrete `itemLink` via a debounced `SendSearchQuery` on icon hover (and during `Buyout` inspect), and immediately update both the card's stat pills / Pawn upgrade score and the open `GameTooltip`.
- **Retrieving tooltip deferral & `requiredLevel` forwarding:** Deferred `RETRIEVING_ITEM_INFO` and 0-line tooltips to the async retry queue even when base `IsItemDataCachedByID` is already true, and forwarded `C_AuctionHouse.GetItemKeyRequiredLevel(itemKey)` to both `C_TooltipInfo.GetItemKey` and `GameTooltip:SetItemKey`.

## v1.2.2

- **Cascading Cat -> Sub -> Slot dropdowns:** Narrowed `Slot` choices dynamically to valid slots for the active `Cat` (`Weapon` / `Armor`) and `Sub` (e.g., `Plate` hides `Back` / `Neck` / `Shields`; `1H` weapons offer `Any` / `Main Hand` / `Off Hand`), auto-selected and locked `Slot` when a subcategory only has one slot (`Two-Handed Axes`, `Bows`, `Shields`, `Relic`), and cleared incompatible selections when changing category or subcategory.
- **Complete 1H Main Hand & Off Hand AH scans:** Selecting `Main Hand` (`INVTYPE_WEAPONMAINHAND`) or `Off Hand` (`INVTYPE_WEAPONOFFHAND`) on 1-handed weapons now also queries and matches generic `One-Hand` (`INVTYPE_WEAPON`) weapons so Off Hand / Main Hand searches include shared 1H axes, maces, swords, and daggers instead of returning `0` results.
- **Shield vs. Off Hand slot deduplication & contextual filters:** Disambiguated Blizzard's shared `"Off Hand"` label for `INVTYPE_SHIELD` using the localized `Shields` armor subclass name across all client languages, hid `Weapon Filters` when `Armor` (or an armor-only slot) is selected, and hid `Armour Filters` under `Weapon`, `Armor -> Miscellaneous`, or zero-armor slots (`Neck`, `Finger`, `Trinket`, `Held in Off-Hand`, `Relic`, `Shirt`, `Tabard`).

## v1.2.1

- **More complete `One-Hand` & async AH scans:** Expanded the `One-Hand` (`INVTYPE_WEAPON`) slot filter to include `Main Hand` (`INVTYPE_WEAPONMAINHAND`) and `Off Hand` (`INVTYPE_WEAPONOFFHAND`) weapons so 1-handed caster/healing maces, daggers, and swords are no longer missed, and replaced single-frame retry with timed multi-pass `C_Item.IsItemDataCachedByID` retries so uncached items aren't silently dropped on fast scans.
- **Classic green `+Healing` / `+Spell Damage` across all 11 locales:** Added shorthand green-item aliases and dual `+Healing and +Damage` rules across `enUS`/`enGB`, `deDE`, `frFR`, `esES`/`esMX`, `ptBR`, `ruRU`, `koKR`, `zhCN`, and `zhTW` (plus expanded Italian `itIT` Classic `Equip:` coverage for hit, haste, dodge, parry, block, defense, and penetrations).
- **Filter parsing & UI layout polish:** Treated `Req Level`, `Max price`, `Damage`, and `Armour` inputs strictly as integers so comma-thousands like `"1,200"` parse as `1200` instead of `1.2`, clamped overflowing green effect pills with ellipses (`...`) + hover tooltips, localized the zero-baseline Pawn `Upgrade` badge (`BADGE_UPGRADE`), and widened the left filter panel (`276px`) and label offsets for longer Russian/European labels.
- **Cleanup:** Removed the unused `/fgs` / `/gearscanner` slash command and empty `ForeverGearScannerDB` boilerplate.

## v1.2.0

- **All 11 official WoW languages supported:** Automatically adapts UI labels, dropdowns, sort bar, card tags, stat autocomplete, and number formatting to your `GetLocale()` client language (`enUS`/`enGB`, `deDE`, `frFR`, `esES`, `esMX`, `ptBR`, `itIT`, `ruRU`, `koKR`, `zhCN`, `zhTW`). Combines Blizzard GlobalStrings (`INVTYPE_*`, `ITEM_QUALITY*_DESC`, `ITEM_MOD_*`, `ITEM_LEVEL`, `ITEM_MIN_LEVEL`, `ARMOR_TEMPLATE`, `DAMAGE_TEMPLATE`, `SPEED`, `ITEM_SET_BONUS*`) with localized Classic/Forever `Equip:` stat parsing, including WoW Forever `ruRU` overrides, French non-breaking spaces (`\194\160`), comma decimals, and Korean/Chinese suffix stats.
- **AH tab `SetPoint` fix (without `LibAHTab`):** Fixed `Action[SetPoint] failed because[Cannot anchor to itself]` in `AttachToAuctionHouse()` when Auctionator/TSM (`LibAHTab-1-0`) is not installed by capturing the previous tab before `CreateFrame` appends the new tab to `AuctionHouseFrame.Tabs` and giving the tab an addon-prefixed frame name (`FGS_AuctionHouseTab`).

## v1.1.1

- **Tooltip set-bonus & proc fix:** Ignored `(N) Set:` and active `Set:` lines during item parsing so set bonuses (e.g. *Bindings of Elements* `(3) Set:` / `(6) Set:`) are no longer added onto an individual item's stats or pills. Excluded `Use:` and temporary proc descriptions from passive stat totals while keeping passive Classic `%` (`Crit`, `Hit`, `Dodge`, `Parry`, `Block`) stats intact.

## v1.1.0

- **Sort bar & result summary:** Added a top Sort bar (`Price`, `Pawn %`, `Name`) with live sort direction and result count, plus clear empty-state prompts before scanning or when no matches are found.
- **Cleaner filter panel & placeholders:** Auto-collapsed `Weapon Filters` and `Armour Filters` under `Any Equipment` (auto-expanding when selecting `Weapon` or `Armor`), widened dropdowns to avoid truncation on `Held in Off-Hand` and `Two-Handed Axes`, and added `Stat...`, `Min`, and `Max` input placeholders.
- **Card & dropdown polish:** Sized card right-column clearance dynamically so `Req Lvl` and red lock warnings never clip early, gave cards extra vertical breathing room, and inset the 40-stat autocomplete scrollbar so rows never clip.
- **Filtering & buyout fixes:** Cleared hidden `Speed` inputs when switching to `Armor`, added `INVTYPE_RANGEDRIGHT` (Guns/Crossbows/Wands) support to `Slot = Ranged`, enforced `Req Level` min against level-0 items, matched `itemLevel` and `itemSuffix` on 2-step buyouts, cleared pending buy state on `AUCTION_HOUSE_CLOSED`, broadened combined spell power tooltip rules, and re-filtered cached results live when switching Pawn `Spec`.

## v1.0.0

- **WoW: Forever architecture (`Interface: 16001`):** Rebuilt Auction House scanning on `C_AuctionHouse` browse queries, `C_TooltipInfo` / tooltip scanning, and `AUCTION_HOUSE_THROTTLED_SYSTEM_READY` backoff handling.
- **Equipable-only AH scoping:** Searches target `Weapon` and `Armor` classes only - no Trade Goods, Containers, or Consumables cluttering results.
- **Dedicated Held in Off-Hand slot:** Added a first-class `Held in Off-Hand` slot filter mapped directly to `Armor / Generic / INVTYPE_HOLDABLE`.
- **Forever stat parsing:** Extracts base stats plus Classic/Forever `Equip:` wording (combined Spell Power, split Healing + Spell Damage, school-specific spell damage, MP5/HP5, Crit, Hit, Haste, Expertise, Penetration, Defense, Block Value, Resistances).
- **Searchable stat dropdown:** Clicking an empty stat filter box now opens a scrollable list of all 40 supported stats without aliases or duplicate entries.
- **Clickable & filterable weapon pills:** Weapon cards render separate `Min Dmg`, `Max Dmg`, `DPS`, and `Speed` pills alongside stat pills (left-click to sort, right-click any pill to add a Stat Filter), plus a new `Speed` min-max filter in Weapon Filters.
- **Native Max price filter:** Replaced min/max price with a single `Max price` row using numeric Gold, Silver, and Copper inputs.
- **Unusable gear indicators:** Items you cannot equip tint soft red on the icon and highlight the failing requirement (proficiency, level, or class lock) directly on the card.
- **Optional Pawn integration:** Adds green `%` upgrade badges per card, resolved item comparison links in tooltips, a `Spec` filter/sort selector (`Any (Best)` or a specific scale), and hides cleanly if Pawn is not installed.
- **Hardware-safe 2-step buyout:** First click queries live auction pricing and switches the button to `Confirm Buy`; second click runs `PlaceBid` directly inside your click event.
