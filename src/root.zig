const std = @import("std");

// Core Ghostplane modules
pub const Engine = @import("engine.zig").Engine;
pub const Transaction = @import("transaction.zig").Transaction;
pub const Batch = @import("batch.zig").Batch;

pub const runtime = @import("runtime/runtime.zig");
pub const transport = @import("transport/transport.zig");
pub const crypto = @import("crypto/crypto.zig");
pub const identity = @import("identity/identity.zig");
pub const ledger = @import("ledger/ledger.zig");

// External dependencies - Ghostchain Stack modules
pub const tokioZ = @import("tokioZ");
pub const shroud = @import("shroud");
pub const ghostbridge = @import("ghostbridge");

// Shroud v0.3.0 submodules accessed through main shroud module
pub const ghostcipher = shroud.ghostcipher;
pub const sigil = shroud.sigil;
pub const ghostwire = shroud.ghostwire;
pub const keystone = shroud.keystone;
pub const zns = shroud.zns;
pub const gwallet = shroud.gwallet;
pub const guardian = shroud.guardian;
pub const covenant = shroud.covenant;
pub const shadowcraft = shroud.shadowcraft;

// Legacy compatibility
pub const zcrypto = shroud.zcrypto;
pub const zsig = shroud.zsig;
pub const realid = shroud.realid;

test {
    std.testing.refAllDecls(@This());
}