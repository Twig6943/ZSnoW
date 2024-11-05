const std = @import("std");
const mem = std.mem;
const posix = std.posix;

const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;
const zwlr = wayland.client.zwlr;

const flakes = @import("flakes/flake.zig");

const FlakeArray = std.ArrayList(*flakes.Flake);

// zig fmt: off
const Context = struct { 
    shm: ?*wl.Shm,
    compositor: ?*wl.Compositor,
    wm_base: ?*xdg.WmBase,
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

const State = struct { doubleBuffer: *DoubleBuffer, surface: *wl.Surface, flakes: *std.ArrayList(*flakes.Flake), alloc: *const std.mem.Allocator, missing_flakes: u32 };

fn render_flake_to_buffer(flake: *const flakes.FlakePattern, m: []u32, x: u32, y: u32, z: u8, width: u32) void {
    var row_num: u32 = 0;

    for (flake.pattern) |row| {
        var column_num: u32 = 0; // Reset column_num at the beginning of each row
        for (row) |pv| {
            if (pv) {
                // Calculate the index in the buffer and ensure we are within bounds
                const index = ((y + row_num) * width) + (x + column_num);
                if (index < m.len) {
                    const alpha: u32 = 0xFF - z;
                    //Shift alpha chanel to its position and OR it with color white
                    m[index] = (alpha << 24) | 0x00FFFFFF; // Set pixel to white
                }
            }
            column_num += 1;
        }
        row_num += 1;
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer {
        _ = gpa.deinit();
    }

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
        .wm_base = null,
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
    const wm_base = context.wm_base orelse return error.NoXdgWmBase;
    const layer_shell = context.layer_shell orelse return error.NoLayerShell;

    _ = wm_base;

    // Create new double buffer
    var doubleBuffer = try DoubleBuffer.new(1920, 1080, "waysnow", shm);
    defer doubleBuffer.destroy();
    @memset(doubleBuffer.mem(), 0x00000000);
    _ = doubleBuffer.next();
    @memset(doubleBuffer.mem(), 0x00000000);
    _ = doubleBuffer.next();

    // Create a surface to draw the buffer on
    const surface = try compositor.createSurface();
    defer surface.destroy();
    surface.commit();
    if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed;

    // Make a layer surface
    const layer_surface: *zwlr.LayerSurfaceV1 = try layer_shell.getLayerSurface(surface, null, zwlr.LayerShellV1.Layer.bottom, "waysnow");
    defer layer_surface.destroy();
    layer_surface.setSize(1920, 1080);
    var running = true;
    // Listen for configure and kill calls
    layer_surface.setListener(*bool, layer_surface_listener, &running);
    surface.commit();
    if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed;

    // Need to attach buffer once to receive frame callbacks
    surface.attach(doubleBuffer.next(), 0, 0);

    // Flake management
    var arrayList = std.ArrayList(*flakes.Flake).init(alloc);
    defer {
        for (arrayList.items) |flake| {
            alloc.destroy(flake);
        }
        arrayList.deinit();
    }

    // Init rendering via frame callback
    const state = &State{ .doubleBuffer = &doubleBuffer, .surface = surface, .flakes = &arrayList, .alloc = &alloc, .missing_flakes = 200 };
    const callback = try surface.frame();
    callback.setListener(*State, frame_callback, @constCast(state));

    surface.commit();

    // Keep running
    while (running) {
        if (display.dispatch() != .SUCCESS) return error.DispatchFailed;
    }
    //_ = gpa.detectLeaks();
}

fn generateRandomFlake(alloc: *const std.mem.Allocator) !*flakes.Flake {
    var rand = std.rand.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        _ = std.posix.getrandom(std.mem.asBytes(&seed)) catch null;
        break :blk seed;
    });

    const flake_int = rand.random().uintAtMost(u8, flakes.FlakePatterns.len - 1);

    const pattern = flakes.FlakePatterns[flake_int];
    const flake = try alloc.create(flakes.Flake);
    flake.* = flakes.Flake.new(
        pattern,
        rand.random().uintAtMost(u32, 1920),
        0,
        rand.random().int(u8),
        std.math.clamp(rand.random().int(u2), 1, std.math.maxInt(u2)),
        0,
    );

    return flake;
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

            } else if (mem.orderZ(u8, global.interface, xdg.WmBase.getInterface().name) == .eq) {
                context.wm_base = registry.bind(global.name, xdg.WmBase, 1) catch return;

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
fn layer_surface_listener(layer_surface: *zwlr.LayerSurfaceV1, event: zwlr.LayerSurfaceV1.Event, running: *bool) void {
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



fn update_flakes(flakeArray: *std.ArrayList(*flakes.Flake), alloc:*const std.mem.Allocator) !u32{

    const to_remove_raw = try alloc.alloc(u32, flakeArray.items.len);
    //std.debug.print("to_remove_raw {x}\n", .{@intFromPtr(to_remove_raw.ptr)});
    defer alloc.free(to_remove_raw);

    var i: u32 = 0;
    var j: u32 = 0;
    for (flakeArray.items) |flake| {
        flake.move(flake.dx, flake.dy);
        if (flake.y >= 1080){
            to_remove_raw[i] = j;
            i += 1;
        }
        j += 1;
    }

    const to_remove = to_remove_raw[0..i];
    std.mem.sort(u32, to_remove, {}, comptime std.sort.desc(u32));
    for (to_remove) |index|{
        const flake  = flakeArray.orderedRemove(index);
        alloc.destroy(flake);
    }

    return i;
}

fn clear_buffer(buffer_mem: []u32) void {
    @memset(buffer_mem, 0x00000000);
}

fn render_flakes(flakeArray: *std.ArrayList(*flakes.Flake), buffer_mem: []u32) !void {
    clear_buffer(buffer_mem);

    for(flakeArray.items) |flake|{
        render_flake_to_buffer(flake.pattern, buffer_mem, flake.x, flake.y, flake.z, 1920);
    }

}

/// Returns the amount of not spawned flakes
fn spawn_new_flakes(flakeArray: *FlakeArray, alloc: *const std.mem.Allocator, i: u32) !u32 {
    var rand = std.rand.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        _ = std.posix.getrandom(std.mem.asBytes(&seed)) catch null;
        break :blk seed;
    });

    var j = i;
    for (0..i)|_| {
        if (rand.random().uintAtMost(u16, 1000) >= 999){
            const flake = generateRandomFlake(alloc) catch undefined;
            if (flake != undefined){
                try flakeArray.append(flake);
            }
            j -= 1;
        }
    }

    return j;

}

fn frame_callback(cb: *wl.Callback, event: wl.Callback.Event, state: * State) void{
    switch(event){
        .done => {
            cb.destroy();

            const cbN = state.surface.frame() catch return;
            cbN.setListener(*State, frame_callback, state);

            const buffer = state.doubleBuffer.current();

            state.surface.attach(buffer, 0, 0);
            state.surface.damage(0, 0, std.math.maxInt(i32), std.math.maxInt(i32));
            state.surface.commit();

            // Get the next buffer to work on
            _ = state.doubleBuffer.next();

            const missing = update_flakes(state.flakes, state.alloc) catch 0;
            const render_new_flakes = state.missing_flakes + missing;
            const missing_flakes = spawn_new_flakes(state.flakes, state.alloc, render_new_flakes) catch 0;
            state.missing_flakes = missing_flakes;
            render_flakes(state.flakes, state.doubleBuffer.mem()) catch return;
        }
    }
}
