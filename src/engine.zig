const std = @import("std");
const Allocator = std.mem.Allocator;
const tokioZ = @import("tokioZ");

const runtime = @import("runtime/runtime.zig");
const transport = @import("transport/transport.zig");
const crypto = @import("crypto/crypto.zig");
const identity = @import("identity/identity.zig");

const log = std.log.scoped(.engine);

// Module-level variable for TokioZ compatibility
var current_engine: ?*Engine = null;

pub const Config = struct {
    port: u16 = 8080,
    enable_quic: bool = true,
    enable_http3: bool = true,
    max_batch_size: u32 = 1000,
    gas_limit: u64 = 21000000,
};

pub const Engine = struct {
    allocator: Allocator,
    config: Config,
    vm_runtime: runtime.VMRuntime,
    network: transport.Network,
    crypto_engine: crypto.Engine,
    identity_manager: identity.Manager,
    async_runtime: *tokioZ.Runtime,
    running: std.atomic.Value(bool),

    const Self = @This();

    pub fn init(allocator: Allocator, config: Config) !Self {
        log.info("Initializing Ghostplane L2 engine with config: {}", .{config});

        const vm_runtime = try runtime.VMRuntime.init(allocator);
        const network = try transport.Network.init(allocator, config.port);
        const crypto_engine = crypto.Engine.init();
        const identity_manager = try identity.Manager.init(allocator);
        const async_runtime = try tokioZ.Runtime.init(allocator, .{
            .max_tasks = 2048,
            .enable_io = true,
            .enable_timers = true,
            .thread_pool_size = 4,
        });

        return Self{
            .allocator = allocator,
            .config = config,
            .vm_runtime = vm_runtime,
            .network = network,
            .crypto_engine = crypto_engine,
            .identity_manager = identity_manager,
            .async_runtime = async_runtime,
            .running = std.atomic.Value(bool).init(false),
        };
    }

    pub fn deinit(self: *Self) void {
        self.running.store(false, .monotonic);
        // tokioZ runtime handles its own cleanup
        self.vm_runtime.deinit();
        self.network.deinit();
        self.crypto_engine.deinit();
        self.identity_manager.deinit();
    }

    pub fn run(self: *Self) !void {
        self.running.store(true, .monotonic);
        log.info("🚀 Ghostplane L2 execution engine running", .{});

        // Use tokioZ async runtime for high-performance concurrent processing
        // Store reference to self for the wrapper function
        current_engine = self;
        
        const mainTaskWrapper = struct {
            fn run() !void {
                if (current_engine) |engine| {
                    try engine.runMainLoop();
                }
            }
        }.run;
        
        try self.async_runtime.run(mainTaskWrapper);
    }

    fn runMainLoop(self: *Self) !void {
        while (self.running.load(.monotonic)) {
            try self.processRequests();
            // TokioZ doesn't have yield, use a simple sleep instead
            std.time.sleep(1000000); // 1ms sleep
        }
    }

    pub fn stop(self: *Self) void {
        self.running.store(false, .monotonic);
        log.info("⏹️ Ghostplane engine stopping", .{});
    }

    fn processRequests(self: *Self) !void {
        _ = self;
        // Process incoming transaction requests, execute contracts, validate signatures
    }
};

test "engine initialization and lifecycle" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var engine = try Engine.init(allocator, .{
        .port = 0,
        .enable_quic = false,
        .enable_http3 = false,
    });
    defer engine.deinit();

    try testing.expect(!engine.running.load(.monotonic));
    
    engine.stop();
    try testing.expect(!engine.running.load(.monotonic));
}