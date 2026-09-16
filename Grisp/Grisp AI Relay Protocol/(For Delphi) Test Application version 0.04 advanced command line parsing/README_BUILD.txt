# GARP/1.24 Delphi Client Build Notes

## Source files

```text
src\GARP124.Protocol.pas
src\GARP124.Client.pas
src\GARP124.Test.dpr
```

## Main compiler fix

`TTimeZone` was removed from `GARP124.Protocol.pas`. The timestamp implementation now uses:

```pascal
uses
    System.DateUtils;

...

DateToISO8601(Now, False)
```

This avoids a dependency on the unavailable `TTimeZone` identifier in the target Delphi environment.

## Additional compile fix

Do not write:

```pascal
GARP_FEATURE_EXT_REPLAY_STORE in FNegotiatedFeatures
```

because `FNegotiatedFeatures` is a dynamic array, not a Delphi set type.

The client now uses:

```pascal
HasNegotiatedFeature(GARP_FEATURE_EXT_REPLAY_STORE)
```

## Build

Build `src\GARP124.Test.dpr` as a Delphi console application with Indy available.

## Self-test

```text
GARP124.Test.exe --self-test
```

Expected proof vectors remain:

```text
4RiTq2SUP15gOp1alqIRdMBUM7Qv4CMZqREMXX4efQs
```

and

```text
iFaTVoYbn_pb5yCCHOTpAUyfzFaCkXXKgLAbpMX6cfI
```

## Live test

Firefox must be running with GARP/1.24 listening on:

```text
127.0.0.1:9999
```

The Delphi client must use exactly the same `GARP_SECRET`.
