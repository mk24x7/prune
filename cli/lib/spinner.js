// Minimal ASCII spinner on stderr. A no-op unless enabled (the CLI enables it
// only when stderr is a TTY and --json is off).

const FRAMES = ['-', '\\', '|', '/'];

export function createSpinner({ enabled = false, stream = process.stderr, interval = 80 } = {}) {
  let timer = null;
  let text = '';
  let frame = 0;

  const fit = (s) => {
    const max = Math.max(10, (stream.columns || 80) - 3);
    return s.length > max ? `...${s.slice(s.length - max + 3)}` : s;
  };
  const render = () => {
    frame = (frame + 1) % FRAMES.length;
    stream.write(`\r\x1b[2K${FRAMES[frame]} ${fit(text)}`);
  };

  return {
    get active() {
      return timer !== null;
    },
    start(initial = '') {
      text = initial;
      if (!enabled || timer) return;
      stream.write('\x1b[?25l');
      render();
      timer = setInterval(render, interval);
      timer.unref?.();
    },
    update(next) {
      text = next;
    },
    stop() {
      if (!timer) return;
      clearInterval(timer);
      timer = null;
      stream.write('\r\x1b[2K\x1b[?25h');
    },
  };
}
