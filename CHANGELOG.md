# Changelog

## v2.0.0

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
