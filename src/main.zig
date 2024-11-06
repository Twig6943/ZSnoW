const std = @import("std");
const mem = std.mem;
const posix = std.posix;

const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;
const zwlr = wayland.client.zwlr;

const flakes = @import("flakes/flake.zig");
const snow = @import("snow.zig");

// zig fmt: off
const Context = struct { 
    shm: ?*wl.Shm,
    compositor: ?*wl.Compositor,
    layer_shell: ?*zwlr.LayerShellV1,
    // outputs: *std.ArrayList(*OutputInfo),
    alloc: *const std.mem.Allocator,
};

const OutputInfo = struct {
    output: *wl.Output,
    x_anchor: i32,
    y_anchor: i32,
    pHeight: i32,
    pWidth: i32,
};

// zig fmt: on

const DoubleBuffer = struct {
    buffer1: *wl.Buffer,
    buffer2: *wl.Buffer,
    i: bool,
    memory1: []u32,
    memory2: []u32,
    fd: i32,
    total_size: u64,

    fn new(width: comptime_int, height: comptime_int, name: []const u8, shm: *wl.Shm) !DoubleBuffer {
        const stride = width * 4;
        const size = stride * height * 2;
        const fd = try posix.memfd_create(name, 0);
        try posix.ftruncate(fd, size);

        const data = blk: {
            const raw = try posix.mmap(
                null,
                size,
                posix.PROT.READ | posix.PROT.WRITE,
                .{ .TYPE = .SHARED },
                fd,
                0,
            );
            break :blk std.mem.bytesAsSlice(u32, raw);
        };

        const pool = try shm.createPool(fd, size);

        const buffer1 = try pool.createBuffer(0, width, height, stride, wl.Shm.Format.argb8888);
        const buffer2 = try pool.createBuffer(size / 2, width, height, stride, wl.Shm.Format.argb8888);
        pool.destroy();

        return DoubleBuffer{ .buffer1 = buffer1, .buffer2 = buffer2, .memory1 = data[0..(size / (2 * 4))], .memory2 = data[(size / (2 * 4)) .. size / 4], .i = true, .fd = fd, .total_size = size };
    }

    fn current(self: *DoubleBuffer) *wl.Buffer {
        return if (self.i) {
            return self.buffer1;
        } else {
            return self.buffer2;
        };
    }

    fn next(self: *DoubleBuffer) *wl.Buffer {
        defer self.i = !self.i;
        return if (self.i) {
            return self.buffer1;
        } else {
            return self.buffer2;
        };
    }

    fn mem(self: *DoubleBuffer) []u32 {
        return if (self.i) {
            return self.memory1;
        } else {
            return self.memory2;
        };
    }

    fn destroy(self: *DoubleBuffer) void {
        self.buffer1.destroy();
        self.buffer2.destroy();
        const memory: []const u32 = self.memory1.ptr[0 .. self.memory1.len + self.memory2.len];
        const u8mem: []align(4096) const u8 = @alignCast(std.mem.bytesAsSlice(u8, memory));

        std.posix.munmap(u8mem);
        posix.close(self.fd);
    }
};

const State = struct { doubleBuffer: *DoubleBuffer, surface: *wl.Surface, flakes: *snow.FlakeArray, alloc: *const std.mem.Allocator, missing_flakes: u32, running: *const bool };

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const alloc = gpa.allocator();

    const display = try wl.Display.connect(null);
    const registry = try display.getRegistry();

    // var outputs = try std.ArrayList(*OutputInfo).initCapacity(alloc, 5);
    // defer {
    //     for (outputs.items) |output| {
    //         alloc.destroy(output);
    //     }
    //     outputs.deinit();
    // }

    // zig fmt: off
    var context = Context{ 
        .shm = null,
        .compositor = null,
        .layer_shell = null,
        // .outputs = &outputs,
        .alloc = &alloc
        };
    // zig fmt: on

    registry.setListener(*Context, registryListener, &context);

    // Blocking roundtrip call to get context
    if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed;

    // Extract all we need
    const shm = context.shm orelse return error.NoWlShm;
    const compositor = context.compositor orelse return error.NoWlCompositor;
    const layer_shell = context.layer_shell orelse return error.NoLayerShell;

    // Create new double buffer
    var doubleBuffer = try DoubleBuffer.new(1920, 1080, "waysnow", shm);
    @memset(doubleBuffer.mem(), 0x00000000);
    _ = doubleBuffer.next();
    @memset(doubleBuffer.mem(), 0x00000000);
    _ = doubleBuffer.next();

    // Create a surface to draw the buffer on
    const surface = try compositor.createSurface();
    surface.commit();
    if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed;

    // Make a layer surface
    const layer_surface: *zwlr.LayerSurfaceV1 = try layer_shell.getLayerSurface(surface, null, zwlr.LayerShellV1.Layer.bottom, "waysnow");
    layer_surface.setSize(1920, 1080);
    var running = true;
    // Listen for configure and kill calls
    layer_surface.setListener(*bool, layerSurfaceListener, &running);
    surface.commit();
    if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed;

    // Need to attach buffer once to receive frame callbacks
    surface.attach(doubleBuffer.next(), 0, 0);

    // Flake management
    var arrayList = try std.ArrayList(*flakes.Flake).initCapacity(alloc, 100);
    // defer {
    //     for (arrayList.items) |flake| {
    //         alloc.destroy(flake);
    //     }
    //     arrayList.deinit();
    // }

    // Init rendering via frame callback
    // zig fmt: off
    var state = State{ 
        .doubleBuffer = &doubleBuffer,
        .surface = surface,
        .flakes = &arrayList,
        .alloc = &alloc,
        .missing_flakes = 100,
        .running = &running 
    };
    // zig fmt: on

    // This callback exists once after that it will get destroyed and another starts
    const callback = try surface.frame();
    callback.setListener(*State, frameCallback, &state);

    surface.commit();

    // Keep running
    // while (running) {
    //     if (display.dispatch() != .SUCCESS) return error.Dispatchfailed;
    // }

    for (0..2000) |_| {
        if (display.dispatch() != .SUCCESS) return error.Dispatchfailed;
    }

    running = false;
    if (display.dispatch() != .SUCCESS) return error.Dispatchfailed;

    for (arrayList.items) |flake| {
        alloc.destroy(flake);
    }

    doubleBuffer.destroy();
    arrayList.deinit();
    surface.destroy();
    layer_surface.destroy();
    registry.destroy();
    shm.destroy();
    compositor.destroy();
    layer_shell.destroy();
    display.disconnect();
    _ = gpa.detectLeaks();
}

/// Listen to the registry events, to update collect what we need
fn registryListener(registry: *wl.Registry, event: wl.Registry.Event, context: *Context) void {
    // zig fmt: off
    switch (event) {
        .global => |global| {
            if (mem.orderZ(u8, global.interface, wl.Compositor.getInterface().name) == .eq) {
                context.compositor = registry.bind(global.name, wl.Compositor, 6) catch return;

            } else if (mem.orderZ(u8, global.interface, wl.Shm.getInterface().name) == .eq) {
                context.shm = registry.bind(global.name, wl.Shm, 1) catch return;

            } else if (mem.orderZ(u8, global.interface, zwlr.LayerShellV1.getInterface().name) == .eq) {
                context.layer_shell = registry.bind(global.name, zwlr.LayerShellV1, 4) catch return;

            } else if (mem.orderZ(u8, global.interface, wl.Output.getInterface().name) == .eq){
                // const output : *wl.Output = registry.bind(global.name, wl.Output, 4) catch return;
                
                // const output_info: *OutputInfo = context.alloc.create(OutputInfo) catch return;
                // std.debug.print("Address of output: {x}\n", .{@intFromPtr(output_info)});
                // output_info.* = OutputInfo{
                //     .output = output,
                //     .pWidth = 0,
                //     .pHeight = 0,
                //     .x_anchor = 0,
                //     .y_anchor = 0
                // };
                //
                // output.setListener(*OutputInfo, outputListener, output_info);
                // context.outputs.append(output_info) catch return;
            }
        },
        .global_remove => {},
    }
}

/// Listen to events of our layer surface
fn layerSurfaceListener(layer_surface: *zwlr.LayerSurfaceV1, event: zwlr.LayerSurfaceV1.Event, running: *bool) void {
    switch (event) {
        .configure => |configure| {
            layer_surface.setSize(1920, 1080);
            layer_surface.setAnchor(.{ .bottom = true, .left = true });
            layer_surface.ackConfigure(configure.serial);
        },

        .closed => {
            running.* = false;
        }

    }

}

fn outputListener(_: *wl.Output, event: wl.Output.Event, output_info: *OutputInfo) void {

    switch (event) {
        .geometry => |geometry| {
            output_info.x_anchor = geometry.x;
            output_info.y_anchor = geometry.y;           
        },
        .mode => |geometry| {
            output_info.pHeight = geometry.height;
            output_info.pWidth = geometry.width;
            std.debug.print("{d}x{d}\n", .{geometry.width, geometry.height});
        },

        .name => |name|{
            std.debug.print("{s}\n", .{name.name});
        },

        else => {}

    }

}


fn frameCallback(cb: *wl.Callback, event: wl.Callback.Event, state: *State) void{
    switch(event){
        .done => {
            if(state.running.*){
                cb.destroy();

                // Do I own this now??
                const cbN = state.surface.frame() catch return;
                cbN.setListener(*State, frameCallback, state);

                const buffer = state.doubleBuffer.current();

                state.surface.attach(buffer, 0, 0);
                state.surface.damage(0, 0, std.math.maxInt(i32), std.math.maxInt(i32));
                state.surface.commit();

                // Get the next buffer to work on
                _ = state.doubleBuffer.next();

                const missing = snow.updateFlakes(state.flakes, state.alloc) catch 0;
                const render_new_flakes = state.missing_flakes + missing;
                const missing_flakes = snow.spawnNewFlakes(state.flakes, state.alloc, render_new_flakes) catch 0;
                state.missing_flakes = missing_flakes;
                snow.renderFlakes(state.flakes, state.doubleBuffer.mem()) catch return;
            }
        }
    }
}
