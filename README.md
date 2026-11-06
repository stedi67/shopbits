# shopcore
shopcore is supposed to grow into the core of a shopping system. The system is mostly experimental and educational.

## Requirements

[Nim](https://nim-lang.org) 2.0 or newer (developed and tested with 2.4.0).
The easiest way to install it is with [choosenim](https://github.com/nim-lang/choosenim) or [Nim's installer](https://nim-lang.org/install.html).

## Compiling

Compile the main program:

    nim c shopcore.nim

This creates the `shopcore` executable in the project directory.
To compile and run it in one step, use `nim c -r shopcore.nim`.

## Running the tests

The tests are plain `assert` statements at the bottom of each module, inside a
`when isMainModule:` block. They run when a module is compiled and executed directly:

    nim c -r pm_decimals.nim
    nim c -r shopcore.nim
    nim c -r structured_string.nim

Each run prints `running assetions` and exits silently on success. A failing
assertion aborts the program with an `AssertionDefect` and a non-zero exit code.

To run all of them at once:

    for f in pm_decimals shopcore structured_string; do nim c -r --hints:off $f.nim || break; done

Do not pass `-d:release` or `-d:danger` when running the tests, because those
flags disable `assert` and the tests would pass without checking anything.
