const std = @import("std");
const ghostplane = @import("ghostplane");

const log = std.log.scoped(.ghostplane);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    log.info("🛸 Ghostplane L2 execution engine starting...", .{});
    
    var engine = try ghostplane.Engine.init(allocator, .{
        .port = 8080,
        .enable_quic = true,
        .enable_http3 = true,
    });
    defer engine.deinit();

    log.info("✅ Ghostplane initialized on port {}", .{engine.config.port});
    log.info("🔐 Zero-trust L2 execution layer ready", .{});
    
    try engine.run();
}

test "ghostplane engine initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var engine = try ghostplane.Engine.init(allocator, .{
        .port = 0,
        .enable_quic = false,
        .enable_http3 = false,
    });
    defer engine.deinit();
    
    try testing.expect(engine.config.port == 0);
}