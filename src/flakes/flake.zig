const std = @import("std");

pub const FlakePattern = struct {
    x_size: u16,
    y_size: u16,
    pattern: []const []const bool,
};

pub const flake0 = FlakePattern{ .pattern = &[_][]const bool{
    &[_]bool{ true, false, true },
    &[_]bool{ false, true, false },
    &[_]bool{ true, false, true },
}, .y_size = 3, .x_size = 3 };

pub const flake1 = FlakePattern{ .pattern = &[_][]const bool{
    &[_]bool{ false, true, false, false, false, true, false, false },
    &[_]bool{ true, true, false, true, false, true, true, false },
    &[_]bool{ false, false, true, false, true, false, false, false },
    &[_]bool{ false, true, false, true, false, true, false, false },
    &[_]bool{ false, false, true, false, true, false, false, false },
    &[_]bool{ true, true, false, true, false, true, true, false },
    &[_]bool{ false, true, false, false, false, true, false, false },
    &[_]bool{ false, false, false, false, false, false, false, false },
}, .y_size = 8, .x_size = 8 };

pub const flake2 = FlakePattern{ .pattern = &[_][]const bool{
    &[_]bool{ true, true, false, false, false, false, false, false, false, false, false, false, false, true, true, false },
    &[_]bool{ false, true, true, false, false, false, false, false, false, false, false, false, true, true, false, false },
    &[_]bool{ false, false, true, true, false, false, false, false, false, false, false, true, true, false, false, false },
    &[_]bool{ false, false, false, true, true, false, false, false, false, false, true, true, false, false, false, false },
    &[_]bool{ false, false, false, false, true, true, false, false, false, true, true, false, false, false, false, false },
    &[_]bool{ false, false, false, false, false, true, true, false, true, true, false, false, false, false, false, false },
    &[_]bool{ false, false, false, false, false, false, true, true, true, false, false, false, false, false, false, false },
    &[_]bool{ false, false, false, false, false, true, true, false, true, true, false, false, false, false, false, false },
    &[_]bool{ false, false, false, false, true, true, false, false, false, true, true, false, false, false, false, false },
    &[_]bool{ false, false, false, true, true, false, false, false, false, false, true, true, false, false, false, false },
    &[_]bool{ false, false, true, true, false, false, false, false, false, false, false, true, true, false, false, false },
    &[_]bool{ false, true, true, false, false, false, false, false, false, false, false, false, true, true, false, false },
    &[_]bool{ true, true, false, false, false, false, false, false, false, false, false, false, false, true, true, false },
}, .y_size = 13, .x_size = 16 };

pub const flake3 = FlakePattern{ .pattern = &[_][]const bool{
    &[_]bool{ false, false, true, false, true, false, false, false },
    &[_]bool{ false, false, false, true, false, false, false, false },
    &[_]bool{ true, false, false, true, false, false, true, false },
    &[_]bool{ false, true, true, false, true, true, false, false },
    &[_]bool{ true, false, false, true, false, false, true, false },
    &[_]bool{ false, false, false, true, false, false, false, false },
    &[_]bool{ false, false, true, false, true, false, false, false },
    &[_]bool{ false, false, false, false, false, false, false, false },
}, .y_size = 8, .x_size = 8 };

pub const flake4 =
    FlakePattern{ .pattern = &[_][]const bool{
    &[_]bool{ false, true, false, false, false, true, false, false },
    &[_]bool{ true, true, false, true, false, true, true, false },
    &[_]bool{ false, false, true, false, true, false, false, false },
    &[_]bool{ false, true, false, true, false, true, false, false },
    &[_]bool{ false, false, true, false, true, false, false, false },
    &[_]bool{ true, true, false, true, false, true, true, false },
    &[_]bool{ false, true, false, false, false, true, false, false },
    &[_]bool{ false, false, false, false, false, false, false, false },
}, .y_size = 8, .x_size = 8 };

pub const flake5 =
    FlakePattern{ .pattern = &[_][]const bool{
    &[_]bool{ false, false, true, false, true, false, false, false },
    &[_]bool{ false, false, false, true, false, false, false, false },
    &[_]bool{ true, false, false, true, false, false, true, false },
    &[_]bool{ false, true, true, false, true, true, false, false },
    &[_]bool{ true, false, false, true, false, false, true, false },
    &[_]bool{ false, false, false, true, false, false, false, false },
    &[_]bool{ false, false, true, false, true, false, false, false },
    &[_]bool{ false, false, false, false, false, false, false, false },
}, .y_size = 8, .x_size = 8 };

pub const flake6 = FlakePattern{ .pattern = &[_][]const bool{
    &[_]bool{ true, false, true },
    &[_]bool{ false, true, false },
    &[_]bool{ true, false, true },
}, .y_size = 3, .x_size = 3 };

pub const Flake = struct {
    pattern: *const FlakePattern,
    x: u32,
    y: u32,
    z: u8,
    dy: u2,
    dx: u2,

    pub fn new(pattern: *const FlakePattern, x: u32, y: u32, z: u8, dy: u2, dx: u2) Flake {
        return Flake{ .pattern = pattern, .x = x, .y = y, .z = z, .dy = dy, .dx = dx };
    }

    pub fn move(flake: *Flake, dx: u32, dy: u32) void {
        flake.x += dx;
        flake.y += dy;
    }
};

pub const FlakePatterns = [_]*const FlakePattern{ &flake0, &flake1, &flake3, &flake4, &flake5, &flake6 };

// TODO implement a xpm parser
// TODO Scale flakes
