const std = @import("std");

pub fn build(b: *std.build.Builder) !void {
    const qemu = b.step("qemu", "Run the kernel under qemu-system-x86_64");
    const buildKernel = kernel(b);

    const kernel_elf = "kernel.elf";
    const writer = b.addWriteFiles();
    _ = writer.addCopyFile(buildKernel.getEmittedBin(), kernel_elf);
    _ = writer.add("limine.cfg",
        \\TIMEOUT=0
        \\:Kernel
        \\    PROTOCOL=limine
        \\    KERNEL_PATH=boot:///
        ++ kernel_elf
    );
    for (&[_][2][]const u8{
        .{"./limine/BOOTX64.EFI", "EFI/BOOT/BOOTX64.EFI" },
        .{ "./limine/limine-bios-cd.bin" , "limine-bios-cd.bin"},
        .{ "./limine/limine-uefi-cd.bin" , "limine-uefi-cd.bin"},
        .{ "./limine/limine-bios.sys", "limine-bios.sys"},
    }) |pair| _ = writer.addCopyFile(.{ .path = pair[0] }, pair[1]);
    
    const emit = b.addWriteFiles();
    const isoFile = emit.add("barebones.iso", &.{});
    const makeIso = b.addSystemCommand(&.{
	    "xorriso",
        "-as", "mkisofs", 
        "-b", "limine-bios-cd.bin",
		"-no-emul-boot",
    });
    makeIso.addFileArg(writer.getDirectory());
    makeIso.addArg("-o");
    makeIso.addFileArg(isoFile);
    const limine = b.addExecutable(.{
        .name = "limine-install",
    });
    limine.addIncludePath(.{ .path = "./limine" });
    limine.addCSourceFile(.{ .file = .{ .path = "./limine/limine.c" }, .flags = &[_][]const u8{} });
    limine.linkLibC();

    const biosInstall = b.addRunArtifact(limine);
    biosInstall.addArg("bios-install");
    biosInstall.addFileArg(isoFile);
    biosInstall.step.dependOn(&makeIso.step);
    
    const qemuStep = b.addSystemCommand(&.{"qemu-system-x86_64"});
    qemuStep.addFileArg(isoFile);
    qemuStep.step.dependOn(&biosInstall.step);
    qemu.dependOn(&qemuStep.step);
}

fn kernel(b: *std.Build.Builder) *std.Build.CompileStep {

    // Define a freestanding x86_64 cross-compilation target.
    var target: std.zig.CrossTarget = .{
        .cpu_arch = .x86_64,
        .os_tag = .freestanding,
        .abi = .none,
    };

    // Disable CPU features that require additional initialization
    // like MMX, SSE/2 and AVX. That requires us to enable the soft-float feature.
    const Features = std.Target.x86.Feature;
    target.cpu_features_sub.addFeature(@intFromEnum(Features.mmx));
    target.cpu_features_sub.addFeature(@intFromEnum(Features.sse));
    target.cpu_features_sub.addFeature(@intFromEnum(Features.sse2));
    target.cpu_features_sub.addFeature(@intFromEnum(Features.avx));
    target.cpu_features_sub.addFeature(@intFromEnum(Features.avx2));
    target.cpu_features_add.addFeature(@intFromEnum(Features.soft_float));

    // Build the kernel itself.
    const optimize = b.standardOptimizeOption(.{});
    const step = b.addExecutable(.{
        .name = "kernel",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    step.setLinkerScriptPath(.{ .path = "src/linker.ld" });
    step.addAnonymousModule("limine", .{ .source_file = .{ .path = "./limine-zig/limine.zig" } });
    step.pie = true;

    return step;
}