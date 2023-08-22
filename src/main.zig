const std = @import("std");
const limine = @import("limine");

pub export var framebuffer_request: limine.FramebufferRequest = .{};

inline fn done() noreturn {
    while (true) {
        asm volatile ("hlt");
    }
}

export fn _start() callconv(.C) noreturn {
    if (framebuffer_request.response) |framebuffer_response| {
        for (framebuffer_response.framebuffers()) |framebuffer| {
            for (0..100) |i| {
                const pixel_offset = i * framebuffer.pitch + i * 4;

                @as(*u32, @ptrCast(@alignCast(framebuffer.address + pixel_offset))).* = 0xFFFFFFFF;
            }
        }
    }

    done();
}
