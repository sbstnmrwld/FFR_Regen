# FFR_Regen

HP and MP regeneration in battle for **FINAL FANTASY RESONANCE**, as a [MogHub](https://github.com/jesus-seijas-sp/ffr-moghub) plugin.

HP and MP can come back with every normal attack or at the start of each character's turn. The game handles the regeneration itself, so you get its own green numbers, bars and animations, with no overlay and no forced UI writes.

## Features

Each stat (HP and MP) has its own settings:

| Setting | Options | Default |
|---|---|---|
| **Regen** | Off / Normal attack (heals the attacker) / Turn start | Turn start |
| **Amount as** | % of max / fixed points (do not grow with the level) | HP: % of max, MP: points |
| **Per regen** | 1–100 | 5 |
| **Chance** | 10, 20, 30, 33, 40, 50, 60, 66, 70, 80, 90, 100 % | 33 % |

You change the settings in the game (main menu → **Mods** → **Regeneration**), and they work with a controller. They are saved in `config.ini` next to the plugin, which you can also edit by hand.

Menu and messages are translated into English, German, French, Spanish, Japanese, Korean and Chinese (Simplified and Traditional).

## Requirements

- [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) (tested with 4.0.0 experimental)
- [MogHub](https://github.com/jesus-seijas-sp/ffr-moghub) (tested with 1.0.1)

## Installation

1. Install UE4SS and MogHub as their own instructions describe.
2. Download `FFR_Regen-<version>.zip` from the [latest release](https://github.com/sbstnmrwld/FFR_Regen/releases/latest) and extract it into
   `FINAL FANTASY RESONANCE\FFRS\Binaries\Win64\ue4ss\Mods\`
3. Start the game. The plugin appears under **Mods** in the main menu.

To uninstall, switch the plugin off in the Mods menu or delete the folder. The mod never writes to your save.

## How it works

The plugin only edits the game's data tables at run time. Nothing is saved, and switching it off restores the originals.

- **Effect:** each stat uses one of the game's unused `SKILL_EFFECT_DATA` rows of type *ParameterVariation* (heal). Its `ParamList` holds the amount, the stat (1 HP / 2 MP) and the mode (2 = percent of max, 0 = fixed points). The chance is the effect's `activationProbability`.
- **Normal attack:** every playable unit's `<name>_通常攻撃` and `<name>_簡易通常攻撃` skills get the effect in a free effect slot, targeting the attacker.
- **Turn start:** the effect is shaped like the game's own "オートリジェネ" / "毎ターンMP3％回復" passives (timing *ActionBegin*, no end). It is carried by passive skill 1032, an enemy-only counter talk that no unit or item uses, and that passive is appended to every playable unit's `UNIT_PARAMETER.passiveSkillList`.

## Limitations

- Battle only, no regeneration while walking.
- The game has no HP/MP threshold condition, so "only below X %" is not possible with native effects.

## AI disclosure

This mod was made by sbstnmrwld with the help of AI: [Claude Code](https://claude.com/claude-code) by Anthropic.

- **AI-generated:** the Lua code, the menu translations in `lang/` and this README, written by Claude based on sbstnmrwld's design and requests.
- **Done by a human:** the feature design, decisions and testing in the game, all by sbstnmrwld.
- **Not included:** AI-generated images, audio, voices or models. The mod only uses the game's own data and visuals.

Commits made with AI help name Claude as co-author.

## License

[MIT](LICENSE): you may use, change and share this mod, also in your own mods, as long as the copyright notice is kept. Final Fantasy Resonance and all game data belong to their owners and are not covered by this license.
