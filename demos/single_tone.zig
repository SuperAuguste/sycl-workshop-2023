const std = @import("std");
const microzig = @import("microzig");
const cpu = microzig.cpu;
const rp2040 = microzig.hal;
const gpio = rp2040.gpio;
const irq = rp2040.irq;

// Peripherals
const peripherals = microzig.chip.peripherals;
const IO_BANK0 = peripherals.IO_BANK0;

const workshop = @import("workshop");
const SuperLoopFlags = workshop.SuperLoopFlags;
const Oscillator = workshop.Oscillator;
const I2S = workshop.I2S(.{
    .sample_rate = sample_rate,
    .sample_type = u32,
});

// this is guaranteed to be initialized before the interrupt fires
var i2s: I2S = undefined;

const sample_rate = 96_000;
const SampleType = u32;
var pressed = workshop.Volatile(bool).init(false);

const pins = struct {
    const button = gpio.num(9);
    const debug = gpio.num(10);
};

pub const microzig_options = struct {
    pub const interrupts = struct {
        pub fn IO_IRQ_BANK0() void {
            // this isn't really required in this example, but if there were
            // other interrupts that accessed the shared variable, it's
            // possible that they might preempt this interrupt.
            cpu.cli();
            defer cpu.sei();

            pressed.store(1 == pins.button.read());

            // Acknowledge the interrupt to the CPU, and tell it
            // we handled it. If we don't do that, the interrupt is immediatly
            // invoked again after the return.
            IO_BANK0.INTR1.modify(.{ .GPIO9_EDGE_LOW = 1 });
        }
    };
};

pub fn main() !void {
    // debug gpio for interrupt handling
    pins.debug.set_function(.sio);
    pins.debug.set_direction(.out);
    pins.debug.put(1);

    // see blinky.zig for an explanation here:
    pins.button.set_function(.sio);
    pins.button.set_direction(.in);
    pins.button.set_pull(.down);

    // here's an example of writing directly to a register
    IO_BANK0.PROC0_INTE1.modify(.{ .GPIO9_EDGE_LOW = 1 });

    // initialize nvic and tell it to route the
    // IO_IRQ_BANK0 into our code
    //irq.enable("IO_IRQ_BANK0");
    //irq.enable("PIO0_IRQ_0");

    i2s = I2S.init(.pio0, .{
        .clock_config = rp2040.clock_config,
        .clk_pin = gpio.num(2),
        .word_select_pin = gpio.num(3),
        .data_pin = gpio.num(4),
    });

    var osc = Oscillator(sample_rate).init(440);

    // lfg
    cpu.sei();

    while (true) {
        if (i2s.is_writable()) {
            osc.update();

            // our sample size is 32 bits, and it just so happens that the
            // maximum value of the oscillator corresponds to 2π radians. We
            // get a sawtooth waveform if we use the angle as the magnitude of
            // our generated wave.
            const sample: SampleType = if (1 == pins.button.read())
                @truncate(SampleType, osc.angle >> 32 - @bitSizeOf(SampleType))
            else
                (std.math.maxInt(SampleType) / 2);

            pins.debug.put(0);
            defer pins.debug.put(1);

            i2s.write(.{
                // The amplifier takes a left and right input as part of the
                // I2S standard and averages both channels to the single
                // speaker. In order to take advantage of the full volume range
                // we'll assign the same value to both channels
                .right = sample,
                .left = sample,
            });
        }
    }
}