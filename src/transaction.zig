const std = @import("std");
const Allocator = std.mem.Allocator;

pub const TransactionType = enum {
    transfer,
    contract_call,
    contract_deploy,
    batch_commit,
};

pub const Transaction = struct {
    id: [32]u8,
    tx_type: TransactionType,
    from: [20]u8,
    to: ?[20]u8,
    value: u64,
    gas_limit: u64,
    gas_price: u64,
    data: []const u8,
    nonce: u64,
    signature: [65]u8,
    timestamp: i64,

    const Self = @This();

    pub fn init(allocator: Allocator, tx_type: TransactionType, from: [20]u8, data: []const u8) !Self {
        var id: [32]u8 = undefined;
        std.crypto.random.bytes(&id);

        const data_copy = try allocator.dupe(u8, data);

        return Self{
            .id = id,
            .tx_type = tx_type,
            .from = from,
            .to = null,
            .value = 0,
            .gas_limit = 21000,
            .gas_price = 1000000000,
            .data = data_copy,
            .nonce = 0,
            .signature = std.mem.zeroes([65]u8),
            .timestamp = std.time.timestamp(),
        };
    }

    pub fn deinit(self: *Self, allocator: Allocator) void {
        allocator.free(self.data);
    }

    pub fn hash(self: *const Self) [32]u8 {
        var hasher = std.crypto.hash.sha3.Sha3_256.init(.{});
        hasher.update(&self.id);
        hasher.update(std.mem.asBytes(&self.tx_type));
        hasher.update(&self.from);
        if (self.to) |to| hasher.update(&to);
        hasher.update(std.mem.asBytes(&self.value));
        hasher.update(std.mem.asBytes(&self.gas_limit));
        hasher.update(std.mem.asBytes(&self.nonce));
        hasher.update(self.data);
        
        var result: [32]u8 = undefined;
        hasher.final(&result);
        return result;
    }

    pub fn verify(self: *const Self) bool {
        // Verify signature using crypto module
        _ = self;
        return true; // Placeholder
    }

    pub fn estimateGas(self: *const Self) u64 {
        const base_gas: u64 = 21000;
        const data_gas = self.data.len * 68;
        
        return switch (self.tx_type) {
            .transfer => base_gas,
            .contract_call => base_gas + data_gas + 25000,
            .contract_deploy => base_gas + data_gas + 32000,
            .batch_commit => base_gas + data_gas + 10000,
        };
    }
};

test "transaction creation and hashing" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const from = std.mem.zeroes([20]u8);
    const data = "test contract data";

    var tx = try Transaction.init(allocator, .contract_call, from, data);
    defer tx.deinit(allocator);

    const hash1 = tx.hash();
    const hash2 = tx.hash();
    
    try testing.expectEqualSlices(u8, &hash1, &hash2);
    try testing.expect(tx.estimateGas() > 21000);
}