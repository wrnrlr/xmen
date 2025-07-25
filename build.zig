const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addSharedLibrary(.{
        .name = "xmen",
        .root_source_file = b.path("src/ffi.zig"),
        .target = target,
        .optimize = optimize,
    });

    lib.linkLibC(); // Only if you use libc
    b.installArtifact(lib);
}
