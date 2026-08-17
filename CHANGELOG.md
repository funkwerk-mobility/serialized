# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.20.0] - 2026-08-17
### Added
- Allow `@(Xml.Text)` fields to be non-string; decode just like attributes.

## [1.19.1] - 2026-07-18
### Fixed
- Update dub.selections.json so that DMD buildkite passes with 2.112.

## [1.19.0] - 2026-05-18
### Added
- Handle sumtype of immutable structs when decoding XML. Adds a dependency on rebindable.

## [1.18.1] - 2026-04-27
### Fixed
- Convert AssertError to XmlError, like in text.json.Decode.

## [1.18.0] - 2026-02-04
### Added
- XML "namespaces" are supported by just defining the attribute/element with a prefix.

### Removed
- Remove TaggedAlgebraic, switch to phobos std.json.

## [1.17.2] - 2025-03-31
### Added
- JSON: Support immutable struct with single value aliased to this on the decode side.

## [1.17.1] - 2025-03-31
### Added
- JSON: Support immutable structs with one value type aliased to this.

## [1.17.0] - 2025-03-31
### Added
- Add `@(Xml.Comment)` elements - for encoding only!!!

## [1.16.1] - 2024-08-12
### Changed
- Speed up `Convert.toString(SysTime)` by reimplementing `toISOExtString` manually.

## [1.16.0] - 2024-08-09
### Changed
- Vendor dxml.writer, dxml.internal for performance optimizations.
- Remove tag stack. Move name checking to compiletime.
- Remove duplicate-attribute check.

## [1.15.2] - 2024-08-09
### Fixed
- Avoid evaluating member value if we're not sure we're including it. Those can be functions or literals!

## [1.15.1] - 2024-08-09
### Fixed
- XML: When stream encoding, pass writer as pointer. Avoids corruption issues when writer has value semantics.

## [1.15.0] - 2024-08-08
### Added
- XML: Add `void encode(value, sink);` to encode to an output stream.

## [1.14.1] - 2024-07-26
### Added
- Support `SysTime` as an element's text value.

## [1.14.0] - 2024-07-26
### Added
- XML: Allow decoding a document where the top element can be one of n different types, identified by tag name.

## [1.13.7] - 2024-05-21
### Added
- Allow `decode` helper to take std.data.json JSON stream. This allows implementation of high-performance custom decoders.

## [1.13.6] - 2023-11-09
### Fixed
- Restore non-nullable default field behavior.

## [1.13.5] - 2023-10-23
### Fixed
- Fix build on DMD 2.097.

## [1.13.4] - 2023-10-20
### Fixed
- Fix variable declaration collision when decoding enum with more than one member.

## [1.13.3] - 2023-10-20
### Fixed
- Support keywords in JSON-style enums as well.

## [1.13.2] - 2023-10-20
### Fixed
- Fix encoding/decoding of reserved-keyword enum members.

## [1.13.1] - 2023-06-30
### Fixed
- Dup string literals on decoding to ensure that references to the input stream are broken.

## [1.13.0] - 2023-06-13
### Changed
- When encoding a type with alias-this, fields in the child that were already present in the parent are not encoded.
- When decoding with alias-this, fields that were already decoded directly in the parent are not decoded a second time in the aliased field's recursive decode.

## [1.12.0] - 2023-06-12
### Removed
- Remove deprecated text.xml.tree file.

## [1.11.0] - 2023-04-18
### Added
- Json.Encode: Custom encoders can chain.

## [1.10.0] - 2023-04-18
### Changed
- Move package `meta` to `serialized.meta`. This avoids a name collision with an internal package that also uses `meta`.

## [1.9.0] - 2023-01-11
### Added
- Interpret boilerplate's `@AliasThis` equivalent to `alias this` in JSON encoding/decoding.

## [1.8.0] - 2022-11-02
### Added
- Types with `T.fromString` method are now implicitly decoded from a string.
- Types with `t.to!string` method are now implicitly encoded to a string.

## [1.7.0] - 2022-10-21
### Changed
- JSON fields that have `@(This.Default)` and are set to their default value, are not encoded.
  This does not apply to fields that are marked with a nonstandard default value, such as `@(This.Default!1)`!

## [1.6.4] - 2022-10-14
### Fixed
- Support DMD 2.100.

## [1.6.3] - 2022-09-21
### Fixed
- Improve quality of float/double encoding.

## [1.6.2] - 2022-08-10
### Changed
- XML: Handle `Nullable` values as empty tags, if they're not `@Default`.

## [1.6.1] - 2022-08-10
### Fixed
- JSON: Encode `Nullable.null` as `null`.

## [1.5.6] - 2022-07-15
### Fixed
- When an invariant is violated while JSON decoding a type, we now throw a parser exception.
  Note that this will not work in `-release` and is hence fundamentally dangerous!
  However, if you never use `-release` anyways, it's fine.

## [1.5.5] - 2022-06-22
### Fixed
- Simplify internal copy of std_data_json: remove support for strings other than `string`.
  This avoids a linker error on 2.099.1.

## [1.5.4] - 2022-06-08
### Fixed
- Fix DMD 2.099.1 DIP1000 support.

## [1.5.3] - 2022-06-07
### Fixed
- decodeJson: add forgotten parameter

## [1.5.2] - 2022-05-09
### Fixed
- JSON: Allow encoding std.sumtype values with a transform function.

## [1.5.1] - 2022-05-09
### Fixed
- Avoid consuming 'streamCopy' in alias-this resolution.

## [1.5.0] - 2022-05-09
### Changed
- Remove sumtype dependency. Use std.sumtype.
  Limit unit-threaded dependency to unittest.

## [1.4.7] - 2022-03-25
### Fixed
- Encode null classes as JSON "null".
- Decode JSON "null" to null classes.

## [1.4.6] - 2022-03-23
### Fixed
- `text.json.Decode`: Only check for object null once we actually try to directly recurse into it.
  Allows null objects to be encoded with an encode function.

## [1.4.5] - 2022-03-23
### Fixed
- Fix: check that isCallable can be instantiated before trying to instantiate it.
  Clarifies a compile error in JSON decoders.

## [1.4.4] - 2022-03-22
### Fixed
- Allow decoding immutable `ParserMarker`.

## [1.4.3] - 2022-02-02
### Fixed
- Avoid combinatorial explosion if decoder fails to instantiate in deep recursion.

## [1.4.2] - 2022-01-20
### Fixed
- XML: Decode arrays of SumTypes.

## [1.4.1] - 2021-10-14
### Fixed
- text.json.Encode: create fast path for `SysTime`. (This type is very common.)

## [1.4.0] - 2021-09-24
### Added
- Add `text.json.ParserMarker`, a type that can be thrown into a decoded struct to match any JSON value.
  As opposed to `JSONValue`, `ParserMarker` just skips the region in the input stream without parsing. Later
  on, you can call `marker.decode!(T, handler)` to resume parsing inside the marker.
  Note that while faster than parsing, skipping in the input stream is not free! The JSON will still need to be
  lexed. Only use `ParserMarker` if there is no way to know the full type of the message at the time.

## [1.3.8] - 2022-02-22
### Fixed
- Avoid combinatorial explosion if decoder fails to instantiate in deep recursion.

## [1.3.7] - 2021-09-20
### Fixed
- Work around DMD 2.097.2 issue where a `FindChildrenRange` related symbol would not be found.

## [1.3.6] - 2021-08-25
### Fixed
- Allow decoding a struct member that is a struct with an immutable hashmap aliased to `this`.

## [1.3.5] - 2021-08-20
### Fixed
- Allow decoding a struct member that is an immutable hashmap.

## [1.3.4] - 2021-08-16
### Fixed
- Work around DMD 2.097.0 regression https://issues.dlang.org/show_bug.cgi?id=22214 .

## [1.3.3] - 2021-05-20
### Fixed
- Update dub boilerplate requirement. Commit dub.selections.json for reproducible unittests.

## [1.3.2] - 2021-04-15
### Fixed
- Fix deprecations and breakage on DMD 2.097.0.

## [1.3.1] - 2021-02-15
### Fixed
- Fix that decoding of nested object in array from JSONValue with alias this would drop every second value.

## [1.3.0] - 2021-02-08
### Added
- Support `@(Xml.Element)`/`@(Xml.Attribute)` without a name.
  For `Xml.Element`, the name of the type is used.
  For `Xml.Attribute`, the name of the field is used.

### Fixed
- When encountering a JSON decoding compile error, log the sequence of types that led to the error.

## [1.2.2] - 2021-01-25
### Fixed
- json: Throw `JSONException` when attempting to decode non-object as object.

## [1.2.1] - 2021-01-13
### Fixed
- Improve error handling in `text.json.Enum`.

## [1.2.0] - 2021-01-13
### Added
- add `text.json.Enum` with helper functions to encode and decode enums into JSON-style "SCREAMING_SNAKE_CASE" strings.

## [1.1.9] - 2020-11-25
### Fixed
- fix depreation for 2.094.1

## [1.1.8] - 2020-10-28
### Fixed
- Allow decoding of immutable associative arrays.

## [1.1.7] - 2020-10-01
### Fixed
- Revert 1.1.3
- Implement different solution: remove problematic `foreach (...; readArray)`.

## [1.1.6] - 2020-09-30
### Fixed
- Support `decode!(const JSONValue)`.

## [1.1.5] - 2020-09-29
### Fixed
- Fix typo in `text.json.Encode`.

## [1.1.4] - 2020-09-29
### Fixed
- Fix JSON encoding of classes.

## [1.1.3] - 2020-09-29
### Fixed
- Remove pointless `@disable this(this)` that was breaking array-of-struct decoding.

## [1.1.2] - 2020-09-24
### Fixed
- Remove file that was breaking LDC build via https://github.com/ldc-developers/ldc/issues/3344 .

## [1.1.1] - 2020-09-24
### Fixed
- Include a copy of std_data_json and taggedalgebraic directly. Work around DMD bug 21235 by hacking opEquals
  to be non-templated.
  This change should be reverted once the upstream issues are fixed. (Hah. Right.)

## [1.1.0] - 2020-09-01
### Added
- Allow loading any type with a `fromString` static method from a string, such as an XML attribute.

## [1.0.1] - 2020-07-27
### Fixed
- Remember to pop stream for numbers when decoding JSONValue.

## [1.0.0] - 2020-07-27
### Added
- Initial version: move text.xml, text.json over from internal Utilities repo; switch json decoding to stdx_data_json.
