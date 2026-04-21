
## Limitations

**Struct fields through mappings are NOT supported.** Do not write:
```
ensures payments[id].amount == amt  // ❌ CRASHES
```
Flatten structs into separate mappings instead. See LIMITATIONS.md for full details.
