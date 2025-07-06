const std = @import("std");
const Allocator = std.mem.Allocator;
const Transaction = @import("transaction.zig").Transaction;

pub const BatchStatus = enum {
    pending,
    processing,
    committed,
    failed,
};

pub const Batch = struct {
    id: [32]u8,
    transactions: std.ArrayList(Transaction),
    status: BatchStatus,
    timestamp: i64,
    block_height: u64,
    merkle_root: [32]u8,
    l1_commit_hash: ?[32]u8,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        var id: [32]u8 = undefined;
        std.crypto.random.bytes(&id);

        return Self{
            .id = id,
            .transactions = std.ArrayList(Transaction).init(allocator),
            .status = .pending,
            .timestamp = std.time.timestamp(),
            .block_height = 0,
            .merkle_root = std.mem.zeroes([32]u8),
            .l1_commit_hash = null,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.transactions.items) |*tx| {
            tx.deinit(self.transactions.allocator);
        }
        self.transactions.deinit();
    }

    pub fn addTransaction(self: *Self, transaction: Transaction) !void {
        try self.transactions.append(transaction);
        self.computeMerkleRoot();
    }

    pub fn process(self: *Self) !void {
        self.status = .processing;
        
        // Validate all transactions
        for (self.transactions.items) |tx| {
            if (!tx.verify()) {
                self.status = .failed;
                return error.InvalidTransaction;
            }
        }

        // Execute all transactions
        for (self.transactions.items) |tx| {
            try self.executeTransaction(tx);
        }

        self.status = .committed;
    }

    pub fn commitToL1(self: *Self) !void {
        if (self.status != .committed) {
            return error.BatchNotCommitted;
        }

        // Generate L1 commit hash
        var commit_hash: [32]u8 = undefined;
        std.crypto.random.bytes(&commit_hash);
        self.l1_commit_hash = commit_hash;
    }

    fn computeMerkleRoot(self: *Self) void {
        if (self.transactions.items.len == 0) {
            self.merkle_root = std.mem.zeroes([32]u8);
            return;
        }

        var hasher = std.crypto.hash.sha3.Sha3_256.init(.{});
        for (self.transactions.items) |tx| {
            const tx_hash = tx.hash();
            hasher.update(&tx_hash);
        }
        hasher.final(&self.merkle_root);
    }

    fn executeTransaction(self: *Self, transaction: Transaction) !void {
        _ = self;
        _ = transaction;
        // Execute transaction using VM runtime
    }

    pub fn size(self: *const Self) usize {
        return self.transactions.items.len;
    }

    pub fn totalGas(self: *const Self) u64 {
        var total: u64 = 0;
        for (self.transactions.items) |tx| {
            total += tx.estimateGas();
        }
        return total;
    }
};

test "batch creation and transaction management" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var batch = Batch.init(allocator);
    defer batch.deinit();

    try testing.expect(batch.size() == 0);
    try testing.expect(batch.status == .pending);

    const from = std.mem.zeroes([20]u8);
    const tx = try Transaction.init(allocator, .transfer, from, "");
    try batch.addTransaction(tx);

    try testing.expect(batch.size() == 1);
    try testing.expect(batch.totalGas() > 0);
}