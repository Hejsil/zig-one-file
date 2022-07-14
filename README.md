# zig-one-file

A simple program that will, given one zig file as input, output a semantically equivalent file
that contains all the code of that file, and the code of the files that file imports. The exceptions
here is `std`, `root` and `builtin` (and anything added with `--pkg-begin` but that has just not
been implemented).

Right now, this only works for files you would run `zig test` or `zig build-obj` on.
`zig build-exe` doesn't work as I've not thought of a way this generated file can export `main`
with the way it is generated.

