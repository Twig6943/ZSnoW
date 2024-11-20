const std = @import("std");
const flakes = @import("flakes/flake.zig");

pub const FlakeArray = std.ArrayList(*flakes.Flake);

pub fn generateRandomFlake(alloc: std.mem.Allocator) !*flakes.Flake {
    var rand = std.rand.DefaultPrng.init(blk: {
        var seed: u64 = 40315527606673217;
        _ = std.posix.getrandom(std.mem.asBytes(&seed)) catch break :blk seed;
        break :blk seed;
    });

    const flake_int = rand.random().uintAtMost(u8, flakes.FlakePatterns.len - 1);

    const pattern = flakes.FlakePatterns[flake_int];
    const flake = try alloc.create(flakes.Flake);
    const dy: u3 = rand.random().int(u2);
    flake.* = flakes.Flake.new(
        pattern,
        rand.random().uintAtMost(u32, 1920),
        0,
        std.math.clamp(rand.random().int(u8), 0, 250),
        dy + 1,
        0,
    );

    return flake;
}

pub fn updateFlakes(flakeArray: *std.ArrayList(*flakes.Flake), alloc: std.mem.Allocator, width: u32, timeDelta: u32) !u32 {
    _ = timeDelta;
    const to_remove_raw = try alloc.alloc(u32, flakeArray.items.len);
    //std.debug.print("to_remove_raw {x}\n", .{@intFromPtr(to_remove_raw.ptr)});
    defer alloc.free(to_remove_raw);

    var i: u32 = 0;
    var j: u32 = 0;
    for (flakeArray.items) |flake| {
        flake.move(flake.dx, flake.dy);
        if (flake.y >= width) {
            to_remove_raw[i] = j;
            i += 1;
        }
        j += 1;
    }

    const to_remove = to_remove_raw[0..i];
    std.mem.sort(u32, to_remove, {}, comptime std.sort.desc(u32));
    for (to_remove) |index| {
        const flake = flakeArray.orderedRemove(index);
        alloc.destroy(flake);
    }

    return i;
}

fn clearBuffer(buffer_mem: []u32) void {
    @memset(buffer_mem, 0x00000000);
}

pub fn renderFlakes(flakeArray: *std.ArrayList(*flakes.Flake), buffer_mem: []u32) !void {
    clearBuffer(buffer_mem);

    for (flakeArray.items) |flake| {
        renderFlakeToBuffer(flake, buffer_mem, 1920);
    }
}

/// Returns the amount of not spawned flakes
pub fn spawnNewFlakes(flakeArray: *FlakeArray, alloc: std.mem.Allocator, i: u32) !u32 {
    var rand = std.rand.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        _ = std.posix.getrandom(std.mem.asBytes(&seed)) catch null;
        break :blk seed;
    });

    var j = i;
    for (0..i) |_| {
        if (rand.random().uintAtMost(u16, 1000) >= 999) {
            const flake = generateRandomFlake(alloc) catch |err| {
                // Handle the error (e.g., log it, retry, etc.)
                return err; // Propagate the error upwards
            };

            // Only append the flake if it's valid
            try flakeArray.append(flake);
            j -= 1;
        }
    }

    return j;
}

fn renderFlakeToBuffer(flake: *const flakes.Flake, m: []u32, width: u32) void {
    var row_num: u32 = 0;

    for (flake.pattern.pattern) |row| {
        var column_num: u32 = 0; // Reset column_num at the beginning of each row
        for (row) |pv| {
            if (pv) {
                // Calculate the index in the buffer and ensure we are within bounds
                const index = ((flake.y + row_num) * width) + (flake.x + column_num);
                if (index < m.len) {
                    const alpha: u32 = 0xFF - flake.z;
                    //Shift alpha chanel to its position and OR it with color white
                    m[index] = (alpha << 24) | 0x00FFFFFF; // Set pixel to white
                }
            }
            column_num += 1;
        }
        row_num += 1;
    }
}
