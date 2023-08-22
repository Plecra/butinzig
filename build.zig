const std = @import("std");

pub fn build(b: *std.build.Builder) !void {
    const qemu = b.step("qemu", "Run the kernel under qemu-system-x86_64");
    const buildKernel = kernel(b);
    b.step("kernel", "Build the kernel").dependOn(&buildKernel.step);
    
    const writer = b.addWriteFiles();
    for (&[_][2][]const u8{
        .{ "./limine/limine-bios-cd.bin", "limine-bios-cd.bin" },
        .{ "./limine/limine-bios.sys", "limine-bios.sys" },
        .{ "./limine.cfg", "limine.cfg" },
    }) |pair| _ = writer.addCopyFile(.{ .path = pair[0] }, pair[1]);
    
    const zigIso = BuildIso.create(b);
    for (&[_][2][]const u8{
        .{ "./limine/limine-bios-cd.bin", "limine-bios-cd.bin" },
        .{ "./limine/limine-bios.sys", "limine-bios.sys" },
        .{ "./limine.cfg", "limine.cfg" },
    }) |pair| zigIso.addCopyFile(.{ .path = pair[0] }, pair[1]);
    b.step("iso", "Build the iso").dependOn(&zigIso.step);

    const makeIso = b.addSystemCommand(&.{ "xorriso", "-as", "mkisofs" });
    makeIso.addDirectoryArg(writer.getDirectory());
    makeIso.addArg("-o");
    const iso = makeIso.addOutputFileArg("barebones.iso");

    const limine = b.addExecutable(.{
        .name = "limine-install",
    });
    limine.addIncludePath(.{ .path = "./limine" });
    limine.addCSourceFile(.{ .file = .{ .path = "./limine/limine.c" }, .flags = &[_][]const u8{} });
    limine.linkLibC();
    const notiso = .{ .generated = &zigIso.generated_file };
    _ = iso;
    const biosInstall = BiosInstall.create(b, limine, notiso, "barebones.iso");
    const patchedBios: std.Build.LazyPath = .{ .generated = &biosInstall.generated_file };

    const qemuStep = b.addSystemCommand(&.{ "qemu-system-x86_64" });
    qemuStep.addArg("-drive");
    qemuStep.addPrefixedFileArg("format=raw,file=", patchedBios);
    qemuStep.addArg("-drive");
    qemuStep.addPrefixedFileArg("format=raw,file=fat:rw:", buildKernel.getEmittedBinDirectory());

    qemu.dependOn(&qemuStep.step);
}
const iso32 = extern struct {
    bytes: [8]u8,
    fn create(n: u32) @This() {
        var bytes = [_]u8{ 0 } ** 8;
        std.mem.writeIntLittle(u32, bytes[0..4], n);
        std.mem.writeIntBig(u32, bytes[4..8], n);
        return .{
            .bytes = bytes,
        };
    }
};
const iso16 = extern struct {
    bytes: [4]u8,
    fn create(n: i16) @This() {
        var bytes = [_]u8{ 0 } ** 4;
        std.mem.writeIntLittle(i16, bytes[0..2], n);
        std.mem.writeIntBig(i16, bytes[2..4], n);
        return .{
            .bytes = bytes,
        };
    }
};
const le32 = extern struct {
    bytes: [4]u8,
    fn create(n: i32) @This() {
        var bytes = [_]u8{ 0 } ** 4;
        std.mem.writeIntLittle(i32, bytes[0..], n);
        return .{
            .bytes = bytes,
        };
    }
};
const be32 = extern struct {
    bytes: [4]u8,
    fn create(n: i32) @This() {
        var bytes = [_]u8{ 0 } ** 4;
        std.mem.writeIntBig(i32, bytes[0..], n);
        return .{
            .bytes = bytes,
        };
    }
};
const datetime = extern struct {
    year: [4]u8 = .{0,0,0,0},
    month: [2]u8 = .{0,1},
    day: [2]u8 = .{0,1},
    hour: [2]u8 = .{0,0},
    minute: [2]u8 = .{0,0},
    second: [2]u8 = .{0,0},
    hundredths: [2]u8 = .{0,0},
    timezone: u8 = 48,
};
const DirectoryRecordHeader = extern struct {
    length: u8,
    extended_attribute_length: u8 = 0,
    extent_location: iso32 = iso32.create(0),
    extent_length: iso32 = iso32.create(0),
    date: [7]u8 = std.mem.zeroes([7]u8),
    flags: packed struct {
        hidden: u1 = 0,
        directory: u1 = 0,
        associated: u1 = 0,
        format_info_available: u1 = 0,
        permissions: u1 = 0,
        unused: u1 = 0,
        unused2: u1 = 0,
        more_entries: u1 = 0,
    } = .{},
    interleaved_unit_size: u8 = 0,
    interleaved_gap_size: u8 = 0,
    volume_sequence_number: iso16 = iso16.create(1),
    name_length: u8,
};
const VolumeDescriptor = extern struct {
    Type: enum(u8) {
        boot,
        primary,
        supplementary,
        partition,
        terminator = 255,
    } = .primary,
    Identifier: [5]u8 = "CD001".*,
    Data: extern union {
        terminator: extern struct {
            Version: u8 = 1,
        },
        primary: extern struct {
            Version: u8 = 1,
            unused: u8 = 0,
            system_identifier: [32]u8 = std.mem.zeroes([32]u8),
            volume_identifier: [32]u8 = std.mem.zeroes([32]u8),
            unused2: [8]u8 = undefined,
            volume_space_size: iso32 = iso32.create(0),
            unused3: [32]u8 = undefined,
            volume_set_size: iso16 = iso16.create(1),
            volume_sequence_number: iso16 = iso16.create(1),
            logical_block_size: iso16 = iso16.create(2048),
            path_table_size: iso32 = iso32.create(0),
            type_l_path_table: le32 = le32.create(0),
            opt_type_l_path_table: le32 = le32.create(0),
            type_m_path_table: be32 = be32.create(0),
            opt_type_m_path_table: be32 = be32.create(0),
            root_directory_record: extern struct {
                header: DirectoryRecordHeader = .{
                    .length = 34,
                    .name_length = 1,
                    .flags = .{ .directory = 1 },
                },
                name: [1]u8 = .{0},
            } = .{},
            volume_set_identifier: [128]u8 = .{0} ** 128,
            publisher_identifier: [128]u8 = .{0x20} ** 128,
            data_preparer_identifier: [128]u8 = .{0x20} ** 128,
            application_identifier: [128]u8 = .{0x20} ** 128,
            copyright_file_identifier: [37]u8 = .{0x20} ** 37,
            abstract_file_identifier: [37]u8 = .{0x20} ** 37,
            bibliographic_file_identifier: [37]u8 = .{0x20} ** 37,
            creation_date: datetime = .{},
            modification_date: datetime = .{},
            expiration_date: datetime = .{},
            effective_date: datetime = .{},
            file_structure_version: u8 = 1,
            unused4: u8 = 0,
            application_data: [512]u8 = undefined,
            reserved: [653]u8 = .{0} ** 653,
        }
    }
};
comptime {
    if (@sizeOf(datetime) != 17) {
        @compileLog("datetime is not 17 bytes ,its ", @sizeOf(datetime), " bytes");
    }
    if (@sizeOf(VolumeDescriptor) != 2048) {
        @compileLog("VolumeDescriptor is not 2048 bytes ,its ", @sizeOf(VolumeDescriptor), " bytes");
    }
}
const BuildIso = struct {
    const UUID: u128 = 0x150c4c9d46e8489e993e5e36a8738bf7;
    step: std.Build.Step,
    generated_file: std.Build.GeneratedFile,
    files: std.ArrayListUnmanaged(File) = .{},
    const File = struct {
        sub_path: []const u8,
        contents: union(enum) {
            given: std.Build.Step.WriteFile.Contents,
            copied: [2]u64,
        },
    };
    fn create(b: *std.Build) *@This() {
        const self = b.allocator.create(@This()) catch @panic("OOM");
        self.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = "mkisofs",
                .owner = b,
                .makeFn = make,
            }),
            .generated_file = .{ .step = &self.step },
        };
        return self;
    }
    pub fn addCopyFile(self: *@This(), source: std.Build.LazyPath, sub_path: []const u8) void{
        const b = self.step.owner;
        const gpa = b.allocator;
        self.files.append(gpa, .{
            .sub_path = b.dupePath(sub_path),
            .contents = .{  .given = .{.copy = source } },
        }) catch @panic("OOM");

        source.addStepDependencies(&self.step);
    }
    fn make(step: *std.Build.Step, _: *std.Progress.Node) !void {
        const self = @fieldParentPtr(@This(), "step", step);
        var man = step.owner.cache.obtain();
        defer man.deinit();
        const uuid_bytes: [16]u8 = @bitCast(UUID);
        man.hash.addBytes(&uuid_bytes);
        for (self.files.items) |file| {
            man.hash.addBytes(file.sub_path);
            switch (file.contents.given) {
                .bytes => |bytes| {
                    man.hash.addBytes(bytes);
                },
                .copy => |source| {
                    _ = try man.addFile(source.getPath(step.owner), null);
                }
            }
        }
        const didhit = try step.cacheHit(&man);
        const digest = man.final();
        const image_path = try step.owner.cache_root.join(step.owner.allocator, &.{
            "o", &digest, "image.iso"
        });
        std.debug.print("{s}\n", .{image_path});
        self.generated_file.path = image_path;
        if (didhit) {
            step.result_cached = true;
            return;
        }
        try step.owner.build_root.handle.makePath(std.fs.path.dirname(image_path).?);
        var file = try step.owner.build_root.handle.createFile(image_path, .{});
        try file.seekBy(32 * 1024);
        var descriptor = VolumeDescriptor{
            .Data = .{
                .primary = .{}
            }
        };
        const primary_descriptor_at = try file.getPos();
        try file.writeAll(std.mem.asBytes(&descriptor));
        const terminator_descriptor = VolumeDescriptor{
            .Type = .terminator,
            .Data = .{
                .terminator = .{}
            }
        };
        try file.writeAll(std.mem.asBytes(&terminator_descriptor));
        const file_extents_at = std.mem.alignForward(u64, try file.getPos(), 2048);
        var start_of_file = file_extents_at;
        for (self.files.items) |*file_desc| {
            try file.seekTo(start_of_file);
            const path = file_desc.contents.given.copy.getPath(step.owner);
            const source_file = try step.owner.build_root.handle.openFile(path, .{});
            const len = try source_file.copyRangeAll(0, file, start_of_file, std.math.maxInt(u64));
            const alignedLen = std.mem.alignForward(u64, len, 2048);
            file_desc.contents = .{ .copied = .{start_of_file, len} };
            start_of_file += alignedLen;
        }
        const root_directory_at = start_of_file;
        try file.seekTo(root_directory_at);
        var root_self = DirectoryRecordHeader{
            .length = 34,
            .name_length = 1,
            .flags = .{ .directory = 1 },
        };
        try file.writeAll(std.mem.asBytes(&root_self));
        try file.writeAll(&.{0});
        const root_parent_at = try file.getPos();
        var root_parent = DirectoryRecordHeader{
            .length = 34,
            .name_length = 1,
            .flags = .{ .directory = 1 },
        };
        try file.writeAll(std.mem.asBytes(&root_parent));
        try file.writeAll(&.{1});
        for (self.files.items) |file_desc| {
            const len: u8 = @intCast(file_desc.sub_path.len + 2);
            var simple_file = DirectoryRecordHeader{
                .length = 33 + len,
                .name_length = len,
                .extent_location = iso32.create(@intCast(file_desc.contents.copied[0] / 2048)),
                .extent_length = iso32.create(@intCast(file_desc.contents.copied[1])),
            };
            try file.writeAll(std.mem.asBytes(&simple_file));
            try file.writeAll(file_desc.sub_path);
            try file.writeAll(";1");
        }
        const end_of_root_directory = std.mem.alignForward(u64, try file.getPos(), 2048);
        _ = try file.pwrite(&.{0}, end_of_root_directory);
        const root_extent_len: u32 = @intCast(end_of_root_directory - root_directory_at);
        const root_extent_loc: u32 = @intCast(root_directory_at / 2048);
        root_self.extent_length = iso32.create(root_extent_len);
        root_self.extent_location = iso32.create(root_extent_loc);
        root_parent.extent_length = iso32.create(root_extent_len);
        root_parent.extent_location = iso32.create(root_extent_loc);
        descriptor.Data.primary.root_directory_record.header.extent_location = iso32.create(root_extent_loc);
        descriptor.Data.primary.root_directory_record.header.extent_length = iso32.create(root_extent_len);
        _ = try file.pwrite(std.mem.asBytes(&root_self), root_directory_at);
        _ = try file.pwrite(std.mem.asBytes(&root_parent), root_parent_at);
        _ = try file.pwrite(std.mem.asBytes(&descriptor), primary_descriptor_at);
    }
};
// alternative to std.Build.Step.Run. see https://github.com/ziglang/zig/issues/16913
const BiosInstall = struct {
    step: std.Build.Step,
    bin_file: std.Build.LazyPath,
    iso: std.Build.LazyPath,
    basename: []const u8,
    generated_file: std.Build.GeneratedFile,

    fn create(b: *std.Build, limine: *std.Build.Step.Compile, iso: std.Build.LazyPath, basename: []const u8) *@This() {
        const self = b.allocator.create(BiosInstall) catch @panic("OOM");
        self.* = .{ .step = std.Build.Step.init(.{
            .id = .custom,
            .name = "limine-install bios-install",
            .owner = b,
            .makeFn = make,
        }), .iso = iso, .bin_file = limine.getEmittedBin(), .basename = basename, .generated_file = .{ .step = &self.step } };
        self.iso.addStepDependencies(&self.step);
        self.bin_file.addStepDependencies(&self.step);

        return self;
    }
    fn make(step: *std.Build.Step, _: *std.Progress.Node) !void {
        const b = step.owner;
        const arena = b.allocator;
        const self = @fieldParentPtr(@This(), "step", step);

        var man = b.cache.obtain();
        defer man.deinit();

        const bin_path = self.bin_file.getPath(b);
        const iso_path = self.iso.getPath(b);
        _ = try man.addFile(bin_path, null);
        _ = try man.addFile(iso_path, null);
        man.hash.addBytes(self.basename);

        if (try step.cacheHit(&man)) {
            const digest = man.final();

            self.generated_file.path = try b.cache_root.join(arena, &.{
                "o", &digest, self.basename,
            });
            step.result_cached = true;
            return;
        }

        const digest = man.final();
        const cache_path = try std.fs.path.join(arena, &.{ "o", &digest });
        var cache_dir = try b.cache_root.handle.makeOpenPath(cache_path, .{});
        defer cache_dir.close();

        try std.fs.Dir.copyFile(
            b.build_root.handle,
            iso_path,
            cache_dir,
            self.basename,
            .{},
        );
        const generated_path = try b.cache_root.join(arena, &.{ "o", &digest, self.basename });
        self.generated_file.path = generated_path;

        const argv = &.{ bin_path, "bios-install", generated_path };
        try step.handleChildProcUnsupported(null, argv);
        try std.Build.Step.handleVerbose2(step.owner, null, null, argv);
        var child = std.process.Child.init(argv, arena);
        child.cwd = b.build_root.path;
        child.cwd_dir = b.build_root.handle;
        child.env_map = b.env_map;
        child.stdin_behavior = .Ignore;
        child.stdout_behavior = .Inherit;
        child.stderr_behavior = .Inherit;
        try step.handleChildProcessTerm(try child.spawnAndWait(), null, argv);

        try step.writeManifest(&man);
    }
};

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
        .name = "kernel.elf",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    step.setLinkerScriptPath(.{ .path = "src/linker.ld" });
    step.addAnonymousModule("limine", .{ .source_file = .{ .path = "./limine-zig/limine.zig" } });
    step.pie = true;

    return step;
}
