module serialized.meta.reservedIdentifier;

import std.range;

enum reservedIdentifier(string id) = !id.empty && !__traits(compiles, { mixin("int " ~ id ~ ";"); });

static assert(reservedIdentifier!"void");

static assert(!reservedIdentifier!"bla");
static assert(!reservedIdentifier!"");
