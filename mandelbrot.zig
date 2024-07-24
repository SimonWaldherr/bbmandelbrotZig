const std = @import("std");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const default_filename = "mandelbrot.pgm";
    const default_resolution = "1000x750";
    const default_top_left = "-2.0,1.0";
    const default_bottom_right = "1.0,-1.0";

    const filename = if (args.len > 1) args[1] else default_filename;
    const resolution = if (args.len > 2) args[2] else default_resolution;
    const topLeft = if (args.len > 3) args[3] else default_top_left;
    const bottomRight = if (args.len > 4) args[4] else default_bottom_right;

    if (args.len > 5) {
        std.log.err("Zu viele Argumente. Benutzung: {s} [IMAGE_FILE] [IMAGE_RESOLUTION] [MANDELBROT_TOP_LEFT] [MANDELBROT_BOTTOM_RIGHT]\nBeispiel: {s} {s} {s} {s}", .{ args[0], default_filename, default_resolution, default_top_left, default_bottom_right });
        std.process.exit(1);
    }

    const imgSize = parseArg(usize, resolution, 'x') orelse {
        std.log.err("Fehler beim Parsen der Bildauflösung", .{});
        return;
    };
    const topLeftComplex = parseComplex(f64, topLeft) orelse {
        std.log.err("Fehler beim Parsen des oberen linken Punktes", .{});
        return;
    };
    const bottomRightComplex = parseComplex(f64, bottomRight) orelse {
        std.log.err("Fehler beim Parsen des unteren rechten Punktes", .{});
        return;
    };

    const pixels = try allocator.alloc(u8, imgSize[0] * imgSize[1]);
    defer allocator.free(pixels);

    render(pixels, imgSize, topLeftComplex, bottomRightComplex);

    const threadCount = try std.Thread.getCpuCount();
    var threads = try allocator.alloc(std.Thread, threadCount);
    defer allocator.free(threads);
    const rowsPerBand = imgSize[1] / threadCount + 1;

    for (0..threadCount) |i| {
        const band = pixels[i * rowsPerBand * imgSize[0] .. @min((i + 1) * rowsPerBand * imgSize[0], pixels.len)];
        const top = i * rowsPerBand;
        const height = band.len / imgSize[0];
        const bandSize = .{ imgSize[0], height };
        const bandTopLeft = pixelToPoint(imgSize, .{ 0, top }, topLeftComplex, bottomRightComplex);
        const bandBottomRight = pixelToPoint(imgSize, .{ imgSize[0], top + height }, topLeftComplex, bottomRightComplex);
        threads[i] = try std.Thread.spawn(.{}, render, .{ band, bandSize, bandTopLeft, bandBottomRight });
    }
    for (threads) |thread| {
        thread.join();
    }

    try writeImage(filename, pixels, imgSize);
}

fn parseArg(comptime T: type, str: []const u8, separator: u8) ?[2]T {
    if (str.len == 0) return null;

    const index = std.mem.indexOfScalar(u8, str, separator);
    if (index) |i| {
        const leftStr = str[0..i];
        const rightStr = str[i + 1 ..];

        const left = parseT(T, leftStr) catch return null;
        const right = parseT(T, rightStr) catch return null;

        return [2]T{ left, right };
    } else return null;
}

fn parseT(comptime T: type, str: []const u8) !T {
    switch (T) {
        f32, f64 => return std.fmt.parseFloat(T, str),
        i32, i64, usize => return std.fmt.parseInt(T, str, 10),
        else => @compileError("Nicht unterstützter Typ für parseT"),
    }
}

fn parseComplex(comptime T: type, str: []const u8) ?Complex(T) {
    const maybePair = parseArg(T, str, ',');
    if (maybePair) |pair| {
        return Complex(T){ .re = pair[0], .im = pair[1] };
    } else {
        return null;
    }
}

fn Complex(comptime T: type) type {
    return struct {
        const Self = @This();

        re: T,
        im: T,

        fn add(self: Self, other: Self) Self {
            return Complex(T){ .re = self.re + other.re, .im = self.im + other.im };
        }

        fn multiply(self: Self, other: Self) Self {
            return Complex(T){
                .re = self.re * other.re - self.im * other.im,
                .im = self.re * other.im + self.im * other.re,
            };
        }

        fn normSqr(self: Self) T {
            return self.re * self.re + self.im * self.im;
        }
    };
}

fn escapeTime(c: Complex(f64), limit: usize) ?usize {
    var z = Complex(f64){ .re = 0.0, .im = 0.0 };
    for (0..limit) |i| {
        if (z.normSqr() > 4.0) {
            return i;
        }
        z = z.multiply(z).add(c);
    }
    return null;
}

fn pixelToPoint(imgSize: [2]usize, pixel: [2]usize, pointTopLeft: Complex(f64), pointBottomRight: Complex(f64)) Complex(f64) {
    const width = pointBottomRight.re - pointTopLeft.re;
    const height = pointTopLeft.im - pointBottomRight.im;
    return Complex(f64){
        .re = pointTopLeft.re + @as(f64, @floatFromInt(pixel[0])) * width / @as(f64, @floatFromInt(imgSize[0])),
        .im = pointTopLeft.im - @as(f64, @floatFromInt(pixel[1])) * height / @as(f64, @floatFromInt(imgSize[1])),
    };
}

fn render(pixels: []u8, imgSize: [2]usize, pointTopLeft: Complex(f64), pointBottomRight: Complex(f64)) void {
    for (0..imgSize[1]) |row| {
        for (0..imgSize[0]) |col| {
            const point = pixelToPoint(imgSize, .{ col, row }, pointTopLeft, pointBottomRight);
            const escapeCount = escapeTime(point, 255);
            pixels[row * imgSize[0] + col] = if (escapeCount) |count| 255 - @as(u8, @intCast(count)) else 0;
        }
    }
}

fn writeImage(filename: []const u8, pixels: []const u8, imgSize: [2]usize) !void {
    const file = try std.fs.cwd().createFile(filename, .{});
    defer file.close();

    const width = imgSize[0];
    const height = imgSize[1];

    const header = try std.fmt.allocPrint(std.heap.page_allocator, "P5\n{d} {d}\n255\n", .{ width, height });
    defer std.heap.page_allocator.free(header);

    try file.writeAll(header);
    try file.writeAll(pixels);
}
