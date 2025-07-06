const std = @import("std");
const Allocator = std.mem.Allocator;
const ghostwire = @import("ghostwire");

pub const Protocol = enum {
    http,
    http3,
    quic,
    grpc,
};

pub const NetworkError = error{
    ConnectionFailed,
    InvalidProtocol,
    Timeout,
    AuthenticationFailed,
};

pub const Request = struct {
    method: []const u8,
    path: []const u8,
    headers: std.StringHashMap([]const u8),
    body: []const u8,
    protocol: Protocol,

    pub fn deinit(self: *Request) void {
        self.headers.deinit();
    }
};

pub const Response = struct {
    status: u16,
    headers: std.StringHashMap([]const u8),
    body: []const u8,
    allocator: Allocator,

    pub fn init(allocator: Allocator, status: u16, body: []const u8) !Response {
        const body_copy = try allocator.dupe(u8, body);
        return Response{
            .status = status,
            .headers = std.StringHashMap([]const u8).init(allocator),
            .body = body_copy,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Response) void {
        var iterator = self.headers.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.headers.deinit();
        self.allocator.free(self.body);
    }

    pub fn addHeader(self: *Response, key: []const u8, value: []const u8) !void {
        const key_copy = try self.allocator.dupe(u8, key);
        const value_copy = try self.allocator.dupe(u8, value);
        try self.headers.put(key_copy, value_copy);
    }
};

pub const Network = struct {
    allocator: Allocator,
    port: u16,
    protocols: std.EnumSet(Protocol),
    running: bool,

    const Self = @This();

    pub fn init(allocator: Allocator, port: u16) !Self {
        var protocols = std.EnumSet(Protocol).initEmpty();
        protocols.insert(.http);
        protocols.insert(.http3);
        protocols.insert(.quic);
        protocols.insert(.grpc);

        return Self{
            .allocator = allocator,
            .port = port,
            .protocols = protocols,
            .running = false,
        };
    }

    pub fn deinit(self: *Self) void {
        self.stop();
    }

    pub fn start(self: *Self) !void {
        if (self.running) return;
        
        std.log.info("🌐 Starting network on port {} with protocols: {}", .{ self.port, self.protocols });
        
        // Initialize QUIC server
        if (self.protocols.contains(.quic)) {
            try self.startQuicServer();
        }
        
        // Initialize HTTP/3 server
        if (self.protocols.contains(.http3)) {
            try self.startHttp3Server();
        }
        
        // Initialize gRPC server
        if (self.protocols.contains(.grpc)) {
            try self.startGrpcServer();
        }
        
        self.running = true;
    }

    pub fn stop(self: *Self) void {
        if (!self.running) return;
        
        std.log.info("⏹️ Stopping network services", .{});
        self.running = false;
    }

    pub fn handleRequest(self: *Self, request: Request) !Response {
        switch (request.protocol) {
            .http, .http3 => return self.handleHttpRequest(request),
            .quic => return self.handleQuicRequest(request),
            .grpc => return self.handleGrpcRequest(request),
        }
    }

    fn startQuicServer(self: *Self) !void {
        _ = self;
        std.log.info("📡 QUIC server starting", .{});
    }

    fn startHttp3Server(self: *Self) !void {
        _ = self;
        std.log.info("🌐 HTTP/3 server starting", .{});
    }

    fn startGrpcServer(self: *Self) !void {
        _ = self;
        std.log.info("🔗 gRPC server starting", .{});
    }

    fn handleHttpRequest(self: *Self, request: Request) !Response {
        _ = request;
        
        var response = try Response.init(self.allocator, 200, "OK");
        try response.addHeader("Content-Type", "application/json");
        try response.addHeader("Server", "Ghostplane/0.1.0");
        
        return response;
    }

    fn handleQuicRequest(self: *Self, request: Request) !Response {
        return self.handleHttpRequest(request);
    }

    fn handleGrpcRequest(self: *Self, request: Request) !Response {
        return self.handleHttpRequest(request);
    }

    pub fn enableProtocol(self: *Self, protocol: Protocol) void {
        self.protocols.insert(protocol);
    }

    pub fn disableProtocol(self: *Self, protocol: Protocol) void {
        self.protocols.remove(protocol);
    }

    pub fn isProtocolEnabled(self: *const Self, protocol: Protocol) bool {
        return self.protocols.contains(protocol);
    }
};

test "network initialization and protocol management" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var network = try Network.init(allocator, 8080);
    defer network.deinit();

    try testing.expect(network.isProtocolEnabled(.http));
    try testing.expect(network.isProtocolEnabled(.quic));
    try testing.expect(network.isProtocolEnabled(.http3));

    network.disableProtocol(.http);
    try testing.expect(!network.isProtocolEnabled(.http));

    network.enableProtocol(.http);
    try testing.expect(network.isProtocolEnabled(.http));
}

test "request handling" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var network = try Network.init(allocator, 8080);
    defer network.deinit();

    var request = Request{
        .method = "GET",
        .path = "/api/status",
        .headers = std.StringHashMap([]const u8).init(allocator),
        .body = "",
        .protocol = .http,
    };
    defer request.deinit();

    var response = try network.handleRequest(request);
    defer response.deinit();

    try testing.expect(response.status == 200);
}