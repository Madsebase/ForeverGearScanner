# Changelog

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
