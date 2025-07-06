const std = @import("std");
const Allocator = std.mem.Allocator;
const crypto = @import("../crypto/crypto.zig");
const sigil = @import("sigil");
const guardian = @import("guardian");

pub const IdentityError = error{
    InvalidIdentity,
    IdentityNotFound,
    PermissionDenied,
    InvalidSignature,
    ExpiredCredential,
};

pub const Identity = struct {
    gid: [20]u8, // Ghost ID
    public_key: [32]u8,
    did: []const u8, // Decentralized Identifier
    created_at: i64,
    last_seen: i64,
    reputation: u32,
    permissions: std.EnumSet(Permission),

    pub fn deinit(self: *Identity, allocator: Allocator) void {
        allocator.free(self.did);
    }
};

pub const Permission = enum {
    execute_contracts,
    deploy_contracts,
    create_batches,
    commit_to_l1,
    admin_access,
    governance_vote,
};

pub const Credential = struct {
    issuer: [20]u8,
    subject: [20]u8,
    claims: std.StringHashMap([]const u8),
    issued_at: i64,
    expires_at: i64,
    signature: crypto.Signature,

    pub fn deinit(self: *Credential) void {
        self.claims.deinit();
    }

    pub fn isValid(self: *const Credential) bool {
        const now = std.time.timestamp();
        return now >= self.issued_at and now < self.expires_at;
    }

    pub fn verify(self: *const Credential, public_key: [32]u8, crypto_engine: *crypto.Engine) !bool {
        if (!self.isValid()) return false;
        
        // Create credential hash for verification
        var hasher = std.crypto.hash.sha3.Sha3_256.init(.{});
        hasher.update(&self.issuer);
        hasher.update(&self.subject);
        hasher.update(std.mem.asBytes(&self.issued_at));
        hasher.update(std.mem.asBytes(&self.expires_at));
        
        var hash: [32]u8 = undefined;
        hasher.final(&hash);
        
        return crypto_engine.verify(&hash, self.signature, public_key);
    }
};

pub const Manager = struct {
    allocator: Allocator,
    identities: std.HashMap([20]u8, Identity, HashContext, std.hash_map.default_max_load_percentage),
    credentials: std.ArrayList(Credential),
    crypto_engine: crypto.Engine,

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

    pub fn init(allocator: Allocator) !Self {
        return Self{
            .allocator = allocator,
            .identities = std.HashMap([20]u8, Identity, HashContext, std.hash_map.default_max_load_percentage).init(allocator),
            .credentials = std.ArrayList(Credential).init(allocator),
            .crypto_engine = crypto.Engine.init(),
        };
    }

    pub fn deinit(self: *Self) void {
        var identity_iterator = self.identities.iterator();
        while (identity_iterator.next()) |entry| {
            var identity = entry.value_ptr;
            identity.deinit(self.allocator);
        }
        self.identities.deinit();

        for (self.credentials.items) |*credential| {
            credential.deinit();
        }
        self.credentials.deinit();
        
        self.crypto_engine.deinit();
    }

    pub fn createIdentity(self: *Self, public_key: [32]u8, did: []const u8) ![20]u8 {
        var gid: [20]u8 = undefined;
        
        // Generate GID from public key hash
        const hash = self.crypto_engine.keccak256(std.mem.asBytes(&public_key));
        @memcpy(&gid, hash[0..20]);

        const did_copy = try self.allocator.dupe(u8, did);
        
        var permissions = std.EnumSet(Permission).initEmpty();
        permissions.insert(.execute_contracts);

        const identity = Identity{
            .gid = gid,
            .public_key = public_key,
            .did = did_copy,
            .created_at = std.time.timestamp(),
            .last_seen = std.time.timestamp(),
            .reputation = 100,
            .permissions = permissions,
        };

        try self.identities.put(gid, identity);
        return gid;
    }

    pub fn getIdentity(self: *Self, gid: [20]u8) ?*Identity {
        return self.identities.getPtr(gid);
    }

    pub fn authenticate(self: *Self, gid: [20]u8, message: []const u8, signature: crypto.Signature) !bool {
        const identity = self.getIdentity(gid) orelse return IdentityError.IdentityNotFound;
        
        const is_valid = try self.crypto_engine.verify(message, signature, identity.public_key);
        if (is_valid) {
            identity.last_seen = std.time.timestamp();
        }
        
        return is_valid;
    }

    pub fn hasPermission(self: *Self, gid: [20]u8, permission: Permission) bool {
        const identity = self.getIdentity(gid) orelse return false;
        return identity.permissions.contains(permission);
    }

    pub fn grantPermission(self: *Self, gid: [20]u8, permission: Permission) !void {
        const identity = self.getIdentity(gid) orelse return IdentityError.IdentityNotFound;
        identity.permissions.insert(permission);
    }

    pub fn revokePermission(self: *Self, gid: [20]u8, permission: Permission) !void {
        const identity = self.getIdentity(gid) orelse return IdentityError.IdentityNotFound;
        identity.permissions.remove(permission);
    }

    pub fn issueCredential(
        self: *Self,
        issuer_gid: [20]u8,
        subject_gid: [20]u8,
        claims: std.StringHashMap([]const u8),
        validity_duration: i64,
    ) !void {
        const issuer = self.getIdentity(issuer_gid) orelse return IdentityError.IdentityNotFound;
        if (!issuer.permissions.contains(.admin_access)) {
            return IdentityError.PermissionDenied;
        }

        const now = std.time.timestamp();
        
        var credential = Credential{
            .issuer = issuer_gid,
            .subject = subject_gid,
            .claims = claims,
            .issued_at = now,
            .expires_at = now + validity_duration,
            .signature = undefined,
        };

        // Sign the credential
        var hasher = std.crypto.hash.sha3.Sha3_256.init(.{});
        hasher.update(&credential.issuer);
        hasher.update(&credential.subject);
        hasher.update(std.mem.asBytes(&credential.issued_at));
        hasher.update(std.mem.asBytes(&credential.expires_at));
        
        var hash: [32]u8 = undefined;
        hasher.final(&hash);
        
        // This would need the issuer's private key in a real implementation
        credential.signature = try self.crypto_engine.sign(&hash, issuer.public_key);

        try self.credentials.append(credential);
    }

    pub fn updateReputation(self: *Self, gid: [20]u8, delta: i32) !void {
        const identity = self.getIdentity(gid) orelse return IdentityError.IdentityNotFound;
        
        if (delta < 0 and @as(i32, @intCast(identity.reputation)) + delta < 0) {
            identity.reputation = 0;
        } else {
            identity.reputation = @intCast(@as(i32, @intCast(identity.reputation)) + delta);
        }
    }

    pub fn getActiveIdentityCount(self: *const Self) u32 {
        const cutoff = std.time.timestamp() - 3600; // Active in last hour
        var count: u32 = 0;
        
        var iterator = self.identities.iterator();
        while (iterator.next()) |entry| {
            if (entry.value_ptr.last_seen > cutoff) {
                count += 1;
            }
        }
        
        return count;
    }
};

test "identity creation and authentication" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var manager = try Manager.init(allocator);
    defer manager.deinit();

    const keypair = crypto.KeyPair.generate();
    const did = "did:ghost:example123";
    
    const gid = try manager.createIdentity(keypair.public_key, did);
    
    const identity = manager.getIdentity(gid).?;
    try testing.expectEqualStrings(did, identity.did);
    try testing.expect(identity.reputation == 100);
    try testing.expect(manager.hasPermission(gid, .execute_contracts));
    try testing.expect(!manager.hasPermission(gid, .admin_access));

    const message = "authenticate me";
    const signature = try manager.crypto_engine.sign(message, keypair.private_key);
    
    const is_authenticated = try manager.authenticate(gid, message, signature);
    try testing.expect(is_authenticated);
}

test "permission management" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var manager = try Manager.init(allocator);
    defer manager.deinit();

    const keypair = crypto.KeyPair.generate();
    const gid = try manager.createIdentity(keypair.public_key, "did:ghost:test");

    try testing.expect(!manager.hasPermission(gid, .deploy_contracts));
    
    try manager.grantPermission(gid, .deploy_contracts);
    try testing.expect(manager.hasPermission(gid, .deploy_contracts));
    
    try manager.revokePermission(gid, .deploy_contracts);
    try testing.expect(!manager.hasPermission(gid, .deploy_contracts));
}