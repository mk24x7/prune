// Terminal styling on top of util.styleText. Color is on only when the target
// stream is a TTY, NO_COLOR is unset (or empty) and --no-color was not passed.

import { styleText } from 'node:util';

export function colorEnabled({ noColor = false, env = process.env, stream = process.stdout } = {}) {
  if (noColor) return false;
  if (typeof env.NO_COLOR === 'string' && env.NO_COLOR !== '') return false;
  return Boolean(stream?.isTTY);
}

// Palette tokens from artifacts.json mapped to styleText colors.
const PALETTE = {
  green: 'green',
  mint: 'greenBright',
  orange: 'redBright',
  red: 'red',
  brown: 'yellow',
  yellow: 'yellowBright',
  teal: 'cyan',
  blue: 'blue',
  purple: 'magenta',
  cyan: 'cyanBright',
  pink: 'magentaBright',
  gray: 'gray',
};

export function createStyle(enabled) {
  // validateStream: false because enablement is decided above (Node >= 22.13
  // would otherwise re-check process.stdout, which is wrong when human output
  // goes to stderr). Older Node versions ignore the options argument.
  const wrap = (format) => (text) => (enabled ? styleText(format, String(text), { validateStream: false }) : String(text));
  const style = {
    enabled,
    bold: wrap('bold'),
    dim: wrap('dim'),
    red: wrap('red'),
    green: wrap('green'),
    yellow: wrap('yellow'),
    cyan: wrap('cyan'),
    magenta: wrap('magenta'),
    palette: (token, text) => (PALETTE[token] ? wrap(PALETTE[token])(text) : String(text)),
  };
  return style;
}
