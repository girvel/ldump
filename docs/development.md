# Development

Most of the development happened in [girvel/fallen](https://github.com/girvel/fallen), this repository was created afterwards.

## Testing

Via [busted](https://github.com/lunarmodules/busted):

```bash
busted
```

Also may be run to test `ldump.get_safe_env` for loading on all available test cases:

```bash
LDUMP_TEST_SAFETY=1 busted
```

## Plans

Serialization in dynamic languages such as Lua (especially serializing upvalues) has an issue of capturing large chunks of data from modules and libraries, growing the size of the output and causing issues with `==`. [girvel/fallen](https://github.com/girvel/fallen) handles this problem through the [module](https://github.com/girvel/fallen/blob/master/lib/module.lua) module, explicitly marking all static data (see [tech.sound](https://github.com/girvel/fallen/blob/master/tech/sound.lua)). This solution seems too verbose and causes boilerplate; right now, an attempt to write a better solution is in progress (see [2.0 milestone](https://github.com/girvel/ldump/milestone/2)).
