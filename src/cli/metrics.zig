const std = @import("std");
const currentRssBytes = @import("types.zig").currentRssBytes;

pub const VerifierMemoryMetrics = struct {
    start_rss_bytes: ?u64 = null,
    after_classify_rss_bytes: ?u64 = null,
    after_metadata_rss_bytes: ?u64 = null,
    after_chunks_rss_bytes: ?u64 = null,
    parallel_start_rss_bytes: ?u64 = null,
    parallel_after_worker_allocators_rss_bytes: ?u64 = null,
    parallel_after_body_rss_bytes: ?u64 = null,
    parallel_merge_rss_bytes: ?u64 = null,
    after_body_rss_bytes: ?u64 = null,
    after_finalize_rss_bytes: ?u64 = null,
    empty_rss_bytes: ?u64 = null,
};

pub const CompileMemoryMetrics = struct {
    start_rss_bytes: ?u64 = null,
    after_load_rss_bytes: ?u64 = null,
    after_setup_rss_bytes: ?u64 = null,
    after_flatten_rss_bytes: ?u64 = null,
    after_verify_rss_bytes: ?u64 = null,
    after_emit_rss_bytes: ?u64 = null,
    after_link_rss_bytes: ?u64 = null,
    end_rss_bytes: ?u64 = null,
    peak_rss_bytes: ?u64 = null,
    verifier: VerifierMemoryMetrics = .{},

    pub     fn updatePeak(self: *CompileMemoryMetrics, rss: ?u64) void {
        const value = rss orelse return;
        if (self.peak_rss_bytes == null or value > self.peak_rss_bytes.?) {
            self.peak_rss_bytes = value;
        }
    }

    pub     fn recordStart(self: *CompileMemoryMetrics) void {
        const rss = currentRssBytes();
        self.start_rss_bytes = rss;
        self.updatePeak(rss);
    }

    pub     fn recordAfterLoad(self: *CompileMemoryMetrics) void {
        const rss = currentRssBytes();
        self.after_load_rss_bytes = rss;
        self.updatePeak(rss);
    }

    pub     fn recordAfterSetup(self: *CompileMemoryMetrics) void {
        const rss = currentRssBytes();
        self.after_setup_rss_bytes = rss;
        self.updatePeak(rss);
    }

    pub     fn recordAfterFlatten(self: *CompileMemoryMetrics) void {
        const rss = currentRssBytes();
        self.after_flatten_rss_bytes = rss;
        self.updatePeak(rss);
    }

    pub     fn recordAfterVerify(self: *CompileMemoryMetrics) void {
        const rss = currentRssBytes();
        self.after_verify_rss_bytes = rss;
        self.updatePeak(rss);
    }

    pub     fn recordAfterEmit(self: *CompileMemoryMetrics) void {
        const rss = currentRssBytes();
        self.after_emit_rss_bytes = rss;
        self.updatePeak(rss);
    }

    pub     fn recordAfterLink(self: *CompileMemoryMetrics) void {
        const rss = currentRssBytes();
        self.after_link_rss_bytes = rss;
        self.updatePeak(rss);
    }

    pub     fn recordEnd(self: *CompileMemoryMetrics) void {
        const rss = currentRssBytes();
        self.end_rss_bytes = rss;
        self.updatePeak(rss);
    }

    pub     fn recordVerifierStage(self: *CompileMemoryMetrics, stage: []const u8, rss: ?u64) void {
        if (std.mem.eql(u8, stage, "start")) {
            self.verifier.start_rss_bytes = rss;
        } else if (std.mem.eql(u8, stage, "after_classify")) {
            self.verifier.after_classify_rss_bytes = rss;
        } else if (std.mem.eql(u8, stage, "after_metadata")) {
            self.verifier.after_metadata_rss_bytes = rss;
        } else if (std.mem.eql(u8, stage, "after_chunks")) {
            self.verifier.after_chunks_rss_bytes = rss;
        } else if (std.mem.eql(u8, stage, "parallel_start")) {
            self.verifier.parallel_start_rss_bytes = rss;
        } else if (std.mem.eql(u8, stage, "parallel_after_worker_allocators")) {
            self.verifier.parallel_after_worker_allocators_rss_bytes = rss;
        } else if (std.mem.eql(u8, stage, "parallel_after_body")) {
            self.verifier.parallel_after_body_rss_bytes = rss;
        } else if (std.mem.eql(u8, stage, "parallel_merge")) {
            self.verifier.parallel_merge_rss_bytes = rss;
        } else if (std.mem.eql(u8, stage, "after_body")) {
            self.verifier.after_body_rss_bytes = rss;
        } else if (std.mem.eql(u8, stage, "after_finalize")) {
            self.verifier.after_finalize_rss_bytes = rss;
        } else if (std.mem.eql(u8, stage, "empty")) {
            self.verifier.empty_rss_bytes = rss;
        }
        self.updatePeak(rss);
    }
};
