# mandelbrot.zig

This is a simple mandelbrot set renderer written in Zig.

## Compatability

In my opinion, the biggest Zig-problem is the changing language definition.
Most of the Zig code on GitHub is now outdated and does not compile anymore.

This code was written for Zig 0.13.0.
0.13.0 is the latest version at the time of writing.
I hope it will work with future versions, but I cannot guarantee it.

## Usage

```sh
zig build-exe mandelbrot.zig
./mandelbrot
convert mandelbrot.pgm mandelbrot.png
```

## Example

![Mandelbrot set](mandelbrot.png)

