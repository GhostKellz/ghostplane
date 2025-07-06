const std = @import("std");
const Allocator = std.mem.Allocator;
const keystone = @import("keystone");

pub const TokenType = enum {
    gcc, // Ghostchain Credits
    zman, // Zero-trust Mana
    sprt, // Spirit (governance)
    custom,
};

pub const Account = struct {
    address: [20]u8,
    balances: std.EnumMap(TokenType, u64),
    nonce: u64,
    state_root: [32]u8,
    code_hash: ?[32]u8,

    pub fn init(address: [20]u8) Account {
        return Account{
            .address = address,
            .balances = std.EnumMap(TokenType, u64).init(.{
                .gcc = 0,
                .zman = 0,
                .sprt = 0,
                .custom = 0,
            }),
            .nonce = 0,
            .state_root = std.mem.zeroes([32]u8),
            .code_hash = null,
        };
    }

    pub fn getBalance(self: *const Account, token_type: TokenType) u64 {
        return self.balances.get(token_type) orelse 0;
    }

    pub fn setBalance(self: *Account, token_type: TokenType, amount: u64) void {
        self.balances.put(token_type, amount);
    }

    pub fn incrementNonce(self: *Account) void {
        self.nonce += 1;
    }
};

pub const StateChange = struct {
    address: [20]u8,
    token_type: TokenType,
    old_balance: u64,
    new_balance: u64,
    block_height: u64,
    transaction_hash: [32]u8,
};

pub const Ledger = struct {
    allocator: Allocator,
    accounts: std.HashMap([20]u8, Account, HashContext, std.hash_map.default_max_load_percentage),
    state_changes: std.ArrayList(StateChange),
    block_height: u64,
    total_supply: std.EnumMap(TokenType, u64),

    const Self = @This();
    const HashContext = struct {
        pub fn hash(self: @This(), key: [20]u8) u64 {
            _ = self;
            return std.hash_map.hashString(std.mem.asBytes(&key));
        }
        pub fn eql(self: @This(), a: [20]u8, b: [20]u8) bool {
            _ = self;
            return std.mem.eql(u8, &a, &b);
        }
    };

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .accounts = std.HashMap([20]u8, Account, HashContext, std.hash_map.default_max_load_percentage).init(allocator),
            .state_changes = std.ArrayList(StateChange).init(allocator),
            .block_height = 0,
            .total_supply = std.EnumMap(TokenType, u64).init(.{
                .gcc = 1000000000000000000, // 1 billion GCC
                .zman = 500000000000000000, // 500 million ZMAN
                .sprt = 100000000000000000,  // 100 million SPRT
                .custom = 0,
            }),
        };
    }

    pub fn deinit(self: *Self) void {
        self.accounts.deinit();
        self.state_changes.deinit();
    }

    pub fn getAccount(self: *Self, address: [20]u8) *Account {
        const result = self.accounts.getOrPut(address) catch unreachable;
        if (!result.found_existing) {
            result.value_ptr.* = Account.init(address);
        }
        return result.value_ptr;
    }

    pub fn getBalance(self: *Self, address: [20]u8, token_type: TokenType) u64 {
        const account = self.getAccount(address);
        return account.getBalance(token_type);
    }

    pub fn transfer(
        self: *Self,
        from: [20]u8,
        to: [20]u8,
        amount: u64,
        token_type: TokenType,
        transaction_hash: [32]u8,
    ) !void {
        const from_account = self.getAccount(from);
        const to_account = self.getAccount(to);

        const from_balance = from_account.getBalance(token_type);
        if (from_balance < amount) {
            return error.InsufficientBalance;
        }

        // Record state changes
        try self.state_changes.append(StateChange{
            .address = from,
            .token_type = token_type,
            .old_balance = from_balance,
            .new_balance = from_balance - amount,
            .block_height = self.block_height,
            .transaction_hash = transaction_hash,
        });

        const to_balance = to_account.getBalance(token_type);
        try self.state_changes.append(StateChange{
            .address = to,
            .token_type = token_type,
            .old_balance = to_balance,
            .new_balance = to_balance + amount,
            .block_height = self.block_height,
            .transaction_hash = transaction_hash,
        });

        // Update balances
        from_account.setBalance(token_type, from_balance - amount);
        to_account.setBalance(token_type, to_balance + amount);
    }

    pub fn mint(
        self: *Self,
        to: [20]u8,
        amount: u64,
        token_type: TokenType,
        transaction_hash: [32]u8,
    ) !void {
        const account = self.getAccount(to);
        const old_balance = account.getBalance(token_type);
        const new_balance = old_balance + amount;

        try self.state_changes.append(StateChange{
            .address = to,
            .token_type = token_type,
            .old_balance = old_balance,
            .new_balance = new_balance,
            .block_height = self.block_height,
            .transaction_hash = transaction_hash,
        });

        account.setBalance(token_type, new_balance);
        
        // Update total supply
        const current_supply = self.total_supply.get(token_type) orelse 0;
        self.total_supply.put(token_type, current_supply + amount);
    }

    pub fn burn(
        self: *Self,
        from: [20]u8,
        amount: u64,
        token_type: TokenType,
        transaction_hash: [32]u8,
    ) !void {
        const account = self.getAccount(from);
        const old_balance = account.getBalance(token_type);

        if (old_balance < amount) {
            return error.InsufficientBalance;
        }

        const new_balance = old_balance - amount;

        try self.state_changes.append(StateChange{
            .address = from,
            .token_type = token_type,
            .old_balance = old_balance,
            .new_balance = new_balance,
            .block_height = self.block_height,
            .transaction_hash = transaction_hash,
        });

        account.setBalance(token_type, new_balance);

        // Update total supply
        const current_supply = self.total_supply.get(token_type) orelse 0;
        self.total_supply.put(token_type, current_supply - amount);
    }

    pub fn chargeGas(
        self: *Self,
        account_address: [20]u8,
        gas_used: u64,
        gas_price: u64,
        token_type: TokenType,
        transaction_hash: [32]u8,
    ) !void {
        const gas_cost = gas_used * gas_price;
        const account = self.getAccount(account_address);
        const balance = account.getBalance(token_type);

        if (balance < gas_cost) {
            return error.InsufficientGas;
        }

        try self.state_changes.append(StateChange{
            .address = account_address,
            .token_type = token_type,
            .old_balance = balance,
            .new_balance = balance - gas_cost,
            .block_height = self.block_height,
            .transaction_hash = transaction_hash,
        });

        account.setBalance(token_type, balance - gas_cost);
        account.incrementNonce();
    }

    pub fn getTotalSupply(self: *const Self, token_type: TokenType) u64 {
        return self.total_supply.get(token_type) orelse 0;
    }

    pub fn getAccountCount(self: *const Self) u32 {
        return @intCast(self.accounts.count());
    }

    pub fn advanceBlock(self: *Self) void {
        self.block_height += 1;
    }

    pub fn computeStateRoot(self: *Self) [32]u8 {
        var hasher = std.crypto.hash.sha3.Sha3_256.init(.{});
        
        var iterator = self.accounts.iterator();
        while (iterator.next()) |entry| {
            hasher.update(&entry.key_ptr.*);
            hasher.update(std.mem.asBytes(&entry.value_ptr.nonce));
            hasher.update(&entry.value_ptr.state_root);
            
            // Hash all balances
            inline for (std.meta.fields(TokenType)) |field| {
                const token_type = @field(TokenType, field.name);
                const balance = entry.value_ptr.getBalance(token_type);
                hasher.update(std.mem.asBytes(&balance));
            }
        }

        var result: [32]u8 = undefined;
        hasher.final(&result);
        return result;
    }

    pub fn getStateChangesInBlock(self: *const Self, block_height: u64) std.ArrayList(StateChange) {
        var changes = std.ArrayList(StateChange).init(self.allocator);
        
        for (self.state_changes.items) |change| {
            if (change.block_height == block_height) {
                changes.append(change) catch {};
            }
        }
        
        return changes;
    }
};

test "ledger basic operations" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var ledger = Ledger.init(allocator);
    defer ledger.deinit();

    const alice = std.mem.zeroes([20]u8);
    const bob = [_]u8{1} ++ std.mem.zeroes([19]u8);
    const tx_hash = std.mem.zeroes([32]u8);

    // Mint some GCC to Alice
    try ledger.mint(alice, 100000, .gcc, tx_hash);
    try testing.expect(ledger.getBalance(alice, .gcc) == 100000);

    // Transfer from Alice to Bob
    try ledger.transfer(alice, bob, 300, .gcc, tx_hash);
    try testing.expect(ledger.getBalance(alice, .gcc) == 99700);
    try testing.expect(ledger.getBalance(bob, .gcc) == 300);

    // Charge gas
    try ledger.chargeGas(alice, 21000, 1, .gcc, tx_hash);
    const expected_balance = 99700 - (21000 * 1);
    try testing.expect(ledger.getBalance(alice, .gcc) == expected_balance);

    try testing.expect(ledger.getAccountCount() == 2);
}

test "insufficient balance handling" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var ledger = Ledger.init(allocator);
    defer ledger.deinit();

    const alice = std.mem.zeroes([20]u8);
    const bob = [_]u8{1} ++ std.mem.zeroes([19]u8);
    const tx_hash = std.mem.zeroes([32]u8);

    // Try to transfer without sufficient balance
    const result = ledger.transfer(alice, bob, 100, .gcc, tx_hash);
    try testing.expectError(error.InsufficientBalance, result);
}