import { GarpError, GarpErrorCode } from "./GarpErrors.sys.mjs";

/*
 * JSON.parse() does not expose duplicate-member detection. This scanner
 * validates object member uniqueness before JSON.parse() is allowed to run.
 * JSON syntax itself remains delegated to the platform parser.
 */
export function assertNoDuplicateObjectMembers(text) {
  let index = 0;

  const fail = message => {
    throw new GarpError(GarpErrorCode.INVALID_ARGUMENT, `Invalid JSON: ${message}`);
  };

  const skipWhitespace = () => {
    while (index < text.length && /[\u0009\u000A\u000D\u0020]/.test(text[index])) index++;
  };

  const parseStringToken = () => {
    if (text[index] !== '"') fail("string expected");
    index++;
    const start = index - 1;
    while (index < text.length) {
      const char = text[index++];
      if (char === '"') return { raw: text.slice(start, index), value: JSON.parse(text.slice(start, index)) };
      if (char === '\\') {
        if (index >= text.length) fail("unterminated escape");
        const escape = text[index++];
        if (escape === 'u') {
          for (let i = 0; i < 4; i++) {
            if (index >= text.length || !/[0-9A-Fa-f]/.test(text[index++])) fail("invalid unicode escape");
          }
        } else if (!'"\\/bfnrt'.includes(escape)) {
          fail("invalid escape");
        }
      } else if (char < ' ') {
        fail("control character in string");
      }
    }
    fail("unterminated string");
  };

  const skipPrimitive = () => {
    const start = index;
    while (index < text.length && !/[\u0009\u000A\u000D\u0020,\]}]/.test(text[index])) index++;
    if (index === start) fail("value expected");
  };

  const skipValue = depth => {
    if (depth > 256) fail("JSON nesting too deep");
    skipWhitespace();
    const char = text[index];
    if (char === '"') { parseStringToken(); return; }
    if (char === '{') { parseObject(depth + 1); return; }
    if (char === '[') { parseArray(depth + 1); return; }
    skipPrimitive();
  };

  const parseArray = depth => {
    index++;
    skipWhitespace();
    if (text[index] === ']') { index++; return; }
    while (true) {
      skipValue(depth);
      skipWhitespace();
      if (text[index] === ']') { index++; return; }
      if (text[index] !== ',') fail("expected comma in array");
      index++;
    }
  };

  const parseObject = depth => {
    index++;
    const keys = new Set();
    skipWhitespace();
    if (text[index] === '}') { index++; return; }
    while (true) {
      skipWhitespace();
      const token = parseStringToken();
      if (keys.has(token.value)) fail(`duplicate object member ${token.value}`);
      keys.add(token.value);
      skipWhitespace();
      if (text[index] !== ':') fail("expected colon in object");
      index++;
      skipValue(depth);
      skipWhitespace();
      if (text[index] === '}') { index++; return; }
      if (text[index] !== ',') fail("expected comma in object");
      index++;
    }
  };

  skipWhitespace();
  skipValue(0);
  skipWhitespace();
  if (index !== text.length) fail("trailing data");
}
