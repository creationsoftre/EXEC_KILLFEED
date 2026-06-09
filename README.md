# exec_killfeed

Counter-Strike inspired killfeed for EXEC servers that hooks directly into `exec_framework`.

## Dependencies

- Required: `exec_framework`

## Installation

1. Copy the `exec_killfeed` folder into your server `resources` directory.
2. Start it after `exec_framework`.

```cfg
ensure exec_framework
ensure exec_killfeed
```

## Commands

- `/killfeed`
- `/killfeed_move`
- `/killfeed_resetpos`
- `/killfeed_preview`
- Server command: `killfeed_test`

## Config File

- `shared/config.lua`

## Notes

- No SQL import is required.
- Weapon icon overrides can be mapped in `shared/config.lua` and the matching PNGs live in `html/images`.
