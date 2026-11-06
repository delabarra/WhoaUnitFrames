WhoaUnitFrames — Media layout
=============================

Style packs (edit .blp here, then /reload):
  classic\light\   Classic geometry seeds (runtime light uses client art unless modified)
  classic\dark\    Classic dark theme + shared party/pet chrome for all styles
  whoa\light\      Custom Whoa borders (default frameStyle)
  whoa\dark\       Whoa dark theme (player/target chrome; not party/pet)
  thick\light\     Thick bar variant
  thick\dark\      Thick dark theme (player/target chrome; not party/pet)

Each style\{light|dark} pack keeps chrome the addon loads:
  UI-TargetingFrame.blp, UI-TargetingFrame-Elite.blp, UI-TargetingFrame-Rare.blp,
  UI-TargetingFrame-Rare-Elite.blp,
  UI-TARGETINGFRAME-FLASH.BLP, UI-TARGETINGFRAME-DRUID.blp,
  UI-TargetofTargetFrame.blp
  (+ classic dark also: UI-PartyFrame.blp + UI-SmallTargetingFrame* for all styles)
  (+ thick only: UI-Player-Status.blp)

  Stacked druid alt-mana (third bar): edit UI-TARGETINGFRAME-DRUID*.blp in the style pack.
  Stock alt-mana border: Media\shared\dark\classpower\UI-CharacterFrame-GroupIndicator.blp
  (not Media\shared\*\UI-GroupIndicator — that is the raid subgroup badge).

Party / party-pet / player-pet policy
------------------------------------
  Party members:
    classic:
      light  → client embed (Interface\TargetingFrame\UI-PartyFrame)
      dark   → Media\classic\dark\UI-PartyFrame.blp
      flash  → client embed
      bars   → classic 70×8 / 70×8
    whoa/thick:
      light  → Media\shared\light\UI-PartyFrame.blp
      dark   → Media\shared\dark\UI-PartyFrame.blp
      flash  → Media\shared\light\UI-PARTYFRAME-FLASH.BLP
      bars   → taller 70×12 / 70×5

  Party-pets (all styles):
    light → client embed (UI-PartyFrame)
    dark  → Media\classic\dark\UI-PartyFrame.blp
    flash → client embed

  Player pet (all styles):
    light → client embed (UI-SmallTargetingFrame*)
    dark  → Media\classic\dark\UI-SmallTargetingFrame*.blp
            (good whoa/thick dark sheets; not the stock classic stub)

Shared (not nested under classic/whoa/thick):
  shared\light\     UI-TOT-FLASH.BLP
                    UI-PartyFrame.blp + UI-PARTYFRAME-FLASH.BLP (whoa/thick party members)
  shared\dark\      UI-TOT-FLASH.BLP + UI-TargetingFrame-Minus.BLP + UI-PVP-*.blp
                    UI-PartyFrame.blp (whoa/thick party member dark)
                    castingbar\  Border + Border-Small + Small-Shield (cast + MirrorTimer)
                    classpower\  Class bars + stock alt-mana GroupIndicator + combo sheets
  shared\statusbar\ Status bar textures (flat)
  shared\dk\        DK-only runtime art

Class power dark pack (Media\shared\dark\classpower\)
-----------------------------------------------------
  Light theme keeps client Interface\… art; dark remaps basename → this folder.
  Includes: Paladin / Warlock / Monk / Priest / Eclipse / DK runes / TotemBorder,
  MonkManaBar, UI-CharacterFrame-GroupIndicator (stock alt-mana chrome),
  ComboPoint.blp, ClassOverlayComboPoints.blp,
  and when retail art is present: UIDruidComboPoints(.blp|2x), UIRogueComboPoints2x.
  Mainline ComboPoints-* atlases use ApplyClassPowerAtlas: edit the atlas source
  sheet once its basename is seeded here (see in-game GetAtlasInfo filename).

Runtime policy:
  Light theme → client textures unless the style ships modified art
  Dark theme  → Media\{style}\dark\ (+ Media\shared\dark\ for minus / PVP / castbar / classpower)
  Party/pet   → see policy above (not per-style packs)
  Minus frame → always shared; light = client, dark = shared\dark
  Cast bars   → shared\dark\castingbar\; Flash / spark / fill stay client
  MirrorTimer → same castingbar Border (breath / fatigue); fill stays client
  DK art      → Media\shared\dk\ only

Re-seed from the WoW client:
  powershell -File tools\populate-frame-media.ps1

Convert PNG edits back to BLP:
  Media\taller\ PNG2BLP tools, or tools\dist\
