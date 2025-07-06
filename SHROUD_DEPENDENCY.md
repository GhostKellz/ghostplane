# Using Shroud as a Dependency

## Adding Shroud to Your Project

### 1. Add to build.zig.zon

```zig
.dependencies = .{
    .shroud = .{
        .url = "https://github.com/ghostkellz/shroud/archive/main.tar.gz",
        .hash = "...", // Run `zig fetch` to get the hash
    },
},
```

### 2. Update your build.zig

```zig
const shroud_dep = b.dependency("shroud", .{
    .target = target,
    .optimize = optimize,
});

// Add to your executable/library imports:
.imports = &.{
    .{ .name = "shroud", .module = shroud_dep.module("shroud") },
},
```

### 3. Import in your source code

```zig
const shroud = @import("shroud");

// Access submodules through shroud:
const ghostcipher = shroud.ghostcipher;
const sigil = shroud.sigil;
const zns = shroud.zns;
const ghostwire = shroud.ghostwire;
const keystone = shroud.keystone;
const guardian = shroud.guardian;
const covenant = shroud.covenant;
const shadowcraft = shroud.shadowcraft;
const gwallet = shroud.gwallet;

// Legacy compatibility:
const zcrypto = shroud.zcrypto;
const zsig = shroud.zsig;
const realid = shroud.realid;
```

## Important Notes

- **Do NOT** try to import individual modules like "ghostcipher" or "sigil" directly
- **Always** import through the main "shroud" module
- All submodules are available through the unified shroud interface
- Use `shroud.version()` to check the library version

## Example Usage

```zig
const std = @import("std");
const shroud = @import("shroud");

pub fn main() !void {
    std.log.info("Using Shroud v{s}", .{shroud.version()});
    
    // Use crypto functions
    const crypto_result = try shroud.ghostcipher.someFunction();
    
    // Use identity functions  
    const identity = try shroud.sigil.createIdentity();
    
    // Use networking
    const server = try shroud.ghostwire.createServer();
}
```