const std = @import("std");
const CompileOptions = @import("types.zig").CompileOptions;
const DceMode = @import("../emit_options.zig").DceMode;

pub fn consumeCompileOption(arg: []const u8, args: []const []const u8, index: *usize, options: *CompileOptions) !bool {
    if (try consumeJobsOption(arg, args, index, options)) return true;
    if (try consumeDceOption(arg, args, index, options)) return true;
    if (try consumePackageOption(arg, args, index, options)) return true;
    if (consumeProfileOption(arg, options)) return true;
    if (consumeMemReportOption(arg, options)) return true;
    if (try consumePermissionSetOption(arg, args, index, options)) return true;
    if (consumeAllowOption(arg, options)) return true;
    if (std.mem.eql(u8, arg, "--fast-math")) {
        options.fast_math = true;
        return true;
    }
    if (std.mem.eql(u8, arg, "--offline")) {
        options.offline = true;
        return true;
    }
    if (std.mem.eql(u8, arg, "--no-incremental")) {
        options.incremental_cache = false;
        return true;
    }
    if (std.mem.startsWith(u8, arg, "--project-root=")) {
        options.project_root = arg["--project-root=".len..];
        if (options.project_root.?.len == 0) return error.InvalidPath;
        return true;
    }
    if (std.mem.eql(u8, arg, "--project-root")) {
        if (index.* + 1 >= args.len) return error.InvalidPath;
        options.project_root = args[index.* + 1];
        if (options.project_root.?.len == 0) return error.InvalidPath;
        index.* += 1;
        return true;
    }
    if (std.mem.eql(u8, arg, "--ci")) {
        options.ci = true;
        return true;
    }
    if (std.mem.eql(u8, arg, "--default-immutable")) {
        options.default_immutable = true;
        // No cache bypass is needed here anymore: the mutability mode is
        // part of the project build cache key (see computeProjectBuildKey),
        // so a cached artifact from the mutable mode can never be reused
        // for the immutable mode — the two modes simply key differently.
        return true;
    }
    if (std.mem.startsWith(u8, arg, "--target=")) {
        const triple = arg["--target=".len..];
        if (triple.len == 0) return error.InvalidTarget;
        options.target_triple = triple;
        return true;
    }
    if (std.mem.eql(u8, arg, "--target")) {
        if (index.* + 1 >= args.len) return error.InvalidTarget;
        const triple = args[index.* + 1];
        if (triple.len == 0) return error.InvalidTarget;
        options.target_triple = triple;
        index.* += 1;
        return true;
    }
    if (std.mem.eql(u8, arg, "--allow-unaudited-risks")) {
        options.allow_unaudited_risks = true;
        return true;
    }
    if (std.mem.eql(u8, arg, "--yes") or std.mem.eql(u8, arg, "--auto-approve")) {
        options.auto_approve_requested = true;
        return true;
    }
    return false;
}

pub fn consumePackageOption(arg: []const u8, args: []const []const u8, index: *usize, options: *CompileOptions) !bool {
    if (std.mem.startsWith(u8, arg, "--package=")) {
        options.package_name = arg["--package=".len..];
        if (options.package_name.?.len == 0) return error.UnknownPackage;
        return true;
    }
    if (std.mem.eql(u8, arg, "--package") or std.mem.eql(u8, arg, "-p")) {
        if (index.* + 1 >= args.len) return error.UnknownPackage;
        options.package_name = args[index.* + 1];
        if (options.package_name.?.len == 0) return error.UnknownPackage;
        index.* += 1;
        return true;
    }
    if (std.mem.startsWith(u8, arg, "-p=")) {
        options.package_name = arg["-p=".len..];
        if (options.package_name.?.len == 0) return error.UnknownPackage;
        return true;
    }
    return false;
}

pub fn consumeDceOption(arg: []const u8, args: []const []const u8, index: *usize, options: *CompileOptions) !bool {
    if (std.mem.startsWith(u8, arg, "--dce=")) {
        options.dce = try parseDceValue(arg["--dce=".len..]);
        return true;
    }
    if (std.mem.eql(u8, arg, "--dce")) {
        if (index.* + 1 >= args.len) return error.MissingDceMode;
        options.dce = try parseDceValue(args[index.* + 1]);
        index.* += 1;
        return true;
    }
    if (std.mem.eql(u8, arg, "--no-dce")) {
        options.dce = .no;
        return true;
    }
    return false;
}

pub fn consumePermissionSetOption(arg: []const u8, args: []const []const u8, index: *usize, options: *CompileOptions) !bool {
    if (std.mem.startsWith(u8, arg, "--permission-set=")) {
        options.permission_set = arg["--permission-set=".len..];
        if (options.permission_set.?.len == 0) return error.InvalidPermissionSet;
        return true;
    }
    if (std.mem.eql(u8, arg, "--permission-set")) {
        if (index.* + 1 >= args.len) return error.MissingPermissionSet;
        options.permission_set = args[index.* + 1];
        index.* += 1;
        return true;
    }
    if (std.mem.startsWith(u8, arg, "-P=")) {
        options.permission_set = arg["-P=".len..];
        if (options.permission_set.?.len == 0) return error.InvalidPermissionSet;
        return true;
    }
    if (std.mem.eql(u8, arg, "-P")) {
        options.permission_set = "default";
        return true;
    }
    return false;
}

pub fn consumeAllowOption(arg: []const u8, options: *CompileOptions) bool {
    if (std.mem.eql(u8, arg, "--allow-env") or std.mem.startsWith(u8, arg, "--allow-env=")) {
        options.allow_env_requested = true;
        return true;
    }
    if (std.mem.eql(u8, arg, "--allow-net") or std.mem.startsWith(u8, arg, "--allow-net=")) {
        options.allow_net_requested = true;
        return true;
    }
    if (std.mem.eql(u8, arg, "--allow-read") or std.mem.startsWith(u8, arg, "--allow-read=")) {
        options.allow_read_requested = true;
        return true;
    }
    if (std.mem.eql(u8, arg, "--allow-write") or std.mem.startsWith(u8, arg, "--allow-write=")) {
        options.allow_write_requested = true;
        return true;
    }
    if (std.mem.eql(u8, arg, "--allow-run") or std.mem.startsWith(u8, arg, "--allow-run=")) {
        options.allow_run_requested = true;
        return true;
    }
    return false;
}

pub fn consumeJobsOption(arg: []const u8, args: []const []const u8, index: *usize, options: *CompileOptions) !bool {
    if (!std.mem.eql(u8, arg, "--jobs")) return false;
    if (index.* + 1 >= args.len) return error.MissingJobs;
    options.jobs = try parseJobsValue(args[index.* + 1]);
    options.jobs_explicit = true;
    index.* += 1;
    return true;
}

pub fn consumeProfileOption(arg: []const u8, options: *CompileOptions) bool {
    if (!std.mem.eql(u8, arg, "--profile")) return false;
    options.profile = true;
    return true;
}

pub fn consumeMemReportOption(arg: []const u8, options: *CompileOptions) bool {
    if (!std.mem.eql(u8, arg, "--mem-report")) return false;
    options.mem_report = true;
    return true;
}

pub fn parseDceValue(text: []const u8) !DceMode {
    return DceMode.parse(text) orelse error.InvalidDceMode;
}

pub fn parseJobsValue(text: []const u8) !?usize {
    if (std.mem.eql(u8, text, "auto")) return null;
    const jobs = std.fmt.parseInt(usize, text, 10) catch return error.InvalidJobs;
    if (jobs == 0) return error.InvalidJobs;
    return jobs;
}
