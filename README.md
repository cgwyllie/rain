# Rain

Rain is an experiment in collaborative code editing in the browser. Using CodeMirror, Redis, and WebSockets, it allows people to edit together.

At the moment it's basically proof of concept and can only work with one file, and has no user system or real security.

The project that sparked my interest in this was: https://github.com/laktek/realie

In order to run it, you need:
- Redis
- Python with the Tornado Web Framework

In order to build it you need:
- CoffeeScript
- Handlebars
- Stitchup
- Less

Not all tools are required at the moment, but the Makefile will try and use them.

## Building

`$ make`

## Running

`$ make run`

Visit localhost:8888 to see the editor working.
